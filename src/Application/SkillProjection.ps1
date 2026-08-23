$skillProjectionApplicationRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) { . (Join-Path $skillProjectionApplicationRepoRoot 'src\Domain\OperationPlan.ps1') }
if ($null -eq (Get-Command Get-SkillCatalogProperty -ErrorAction SilentlyContinue)) { . (Join-Path $skillProjectionApplicationRepoRoot 'src\Domain\SkillCatalog.ps1') }

function Get-NativeSkillProjectionProperty {
    param($Object, [string[]]$Names)

    foreach ($name in @($Names)) {
        if (Test-OperationObjectProperty $Object $name) { return (Get-OperationObjectProperty $Object $name) }
    }
    return $null
}

function Resolve-NativeSkillProjectionPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $resolved = $Path.Trim()
    if ($resolved.StartsWith('~')) { $resolved = $resolved -replace '^~', [Environment]::GetFolderPath('UserProfile') }
    if (-not [IO.Path]::IsPathRooted($resolved)) { $resolved = Join-Path $skillProjectionApplicationRepoRoot $resolved }
    return [IO.Path]::GetFullPath($resolved)
}

function Test-NativeSkillProjectionPathWithinRoot {
    param([string]$Path, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return [string]::Equals($candidate, $boundary, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith(($boundary + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
}

function Get-NativeSkillProjectionPackageHash {
    param([string]$SkillDirectory)

    if ([string]::IsNullOrWhiteSpace($SkillDirectory) -or -not (Test-Path -LiteralPath $SkillDirectory -PathType Container)) { return '' }
    $base = [IO.Path]::GetFullPath($SkillDirectory).TrimEnd('\', '/')
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction Stop | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($base.Length).TrimStart('\', '/').Replace('\', '/')
        # Package-root catalog.json is a generated projection artifact (see
        # Get-SkillPackageContentHash); it must not affect package identity.
        if ($relative -eq 'catalog.json') { continue }
        $hash = ([string](Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash).ToLowerInvariant()
        $parts.Add(('{0}|{1}' -f $relative, $hash)) | Out-Null
    }
    return Get-OperationSha256 ($parts.ToArray() -join "`n")
}

function Assert-NativeSkillProjectionPathHasNoReparseAncestor {
    param([string]$Path, [string]$AllowedRoot)
    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
    $cursor = [IO.Path]::GetFullPath($Path)
    while (Test-NativeSkillProjectionPathWithinRoot $cursor $root) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Native projection path crosses a reparse point: $cursor" }
        }
        if ([string]::Equals($cursor.TrimEnd('\', '/'), $root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = Split-Path $cursor -Parent
    }
}

function Get-NativeSkillProjectionSettings {
    param([Parameter(Mandatory = $true)]$Config)

    $skillProjection = Get-NativeSkillProjectionProperty $Config @('skill_projection')
    $settings = Get-NativeSkillProjectionProperty $skillProjection @('native_projection')
    if ($null -eq $settings) { throw 'skill_projection.native_projection is required for native projection.' }
    $enabled = if (Test-OperationObjectProperty $settings 'enabled') { [bool](Get-OperationObjectProperty $settings 'enabled') } else { $true }
    $owner = ([string](Get-NativeSkillProjectionProperty $settings @('owner'))).Trim()
    $targetRoot = Resolve-NativeSkillProjectionPath ([string](Get-NativeSkillProjectionProperty $settings @('target_root', 'user_skill_root')))
    $receiptPath = Resolve-NativeSkillProjectionPath ([string](Get-NativeSkillProjectionProperty $settings @('receipt_path')))
    $userSkillRoot = Resolve-NativeSkillProjectionPath ([string](Get-NativeSkillProjectionProperty $skillProjection @('user_skill_root')))
    $receiptRoot = [IO.Path]::GetFullPath((Join-Path $skillProjectionApplicationRepoRoot 'reports\skill-projection'))
    if ([string]::IsNullOrWhiteSpace($owner)) { throw 'skill_projection.native_projection.owner is required.' }
    if ([string]::IsNullOrWhiteSpace($targetRoot)) { throw 'skill_projection.native_projection.target_root is required.' }
    if ([string]::IsNullOrWhiteSpace($receiptPath)) { throw 'skill_projection.native_projection.receipt_path is required.' }
    if ([string]::IsNullOrWhiteSpace($userSkillRoot)) { throw 'skill_projection.user_skill_root is required for native projection.' }
    if (-not [string]::Equals($targetRoot.TrimEnd('\', '/'), $userSkillRoot.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'skill_projection.native_projection.target_root must equal skill_projection.user_skill_root.' }
    if ([string]::Equals($targetRoot.TrimEnd('\', '/'), [IO.Path]::GetPathRoot($targetRoot).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'skill_projection.native_projection.target_root must not be a filesystem root.' }
    if (-not (Test-NativeSkillProjectionPathWithinRoot $receiptPath $receiptRoot) -or [string]::Equals($receiptPath.TrimEnd('\', '/'), $receiptRoot.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'skill_projection.native_projection.receipt_path must be a file under reports/skill-projection.' }
    Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path $receiptPath -Parent) $receiptRoot
    return [pscustomobject][ordered]@{
        enabled = $enabled
        owner = $owner
        target_root = $targetRoot
        receipt_path = $receiptPath
    }
}

function Get-NativeSkillProjectionReceiptOwnedLinks {
    param($Settings)

    $owned = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $receiptPath = [string]$Settings.receipt_path
    if ([string]::IsNullOrWhiteSpace($receiptPath) -or -not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { return $owned }
    try { $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json }
    catch { throw ('Native projection ownership receipt is invalid: {0}' -f $receiptPath) }
    if ([int]$receipt.schema_version -ne 1 -or [string]$receipt.status -ne 'applied') { return $owned }
    if ([string]$receipt.receipt_id -notmatch '^nsr-[a-f0-9]{16}$' -or [string]$receipt.plan_id -notmatch '^nsp-[a-f0-9]{16}$') { return $owned }
    if (-not [string]::Equals([string]$receipt.owner, [string]$Settings.owner, [StringComparison]::Ordinal)) { return $owned }
    if ([string]::IsNullOrWhiteSpace([string]$receipt.target_root)) { return $owned }
    if (-not [string]::Equals(([IO.Path]::GetFullPath([string]$receipt.target_root).TrimEnd('\', '/')), ([IO.Path]::GetFullPath([string]$Settings.target_root).TrimEnd('\', '/')), [StringComparison]::OrdinalIgnoreCase)) { return $owned }
    foreach ($state in @($receipt.after)) {
        if ($null -eq $state -or -not [bool]$state.exists -or [string]$state.kind -ne 'junction') { continue }
        if ([string]::IsNullOrWhiteSpace([string]$state.directory_path) -or [string]::IsNullOrWhiteSpace([string]$state.link_target)) { continue }
        $directoryPath = [IO.Path]::GetFullPath([string]$state.directory_path).TrimEnd('\', '/')
        $linkTarget = [IO.Path]::GetFullPath([string]$state.link_target).TrimEnd('\', '/')
        if ((Test-NativeSkillProjectionPathWithinRoot $directoryPath ([string]$Settings.target_root)) -and -not [string]::IsNullOrWhiteSpace($linkTarget)) {
            $owned[$directoryPath] = $linkTarget
        }
    }
    return $owned
}

function Get-NativeSkillProjectionEligibilityByName {
    param([object[]]$Eligibility)

    $result = @{}
    foreach ($item in @($Eligibility)) {
        $name = ([string](Get-NativeSkillProjectionProperty $item @('skill_name', 'name'))).Trim()
        if (-not [string]::IsNullOrWhiteSpace($name)) { $result[$name] = $item }
    }
    return $result
}

function New-NativeSkillProjectionBlockedPlan {
    param(
        $Settings,
        $Catalog,
        [string[]]$EnabledNames,
        [object[]]$Findings
    )

    $identity = [ordered]@{
        status = 'blocked'
        target_root = [string]$Settings.target_root
        catalog_id = [string](Get-NativeSkillProjectionProperty $Catalog @('catalog_id'))
        enabled = @($EnabledNames | Sort-Object)
        findings = @($Findings | ForEach-Object { [ordered]@{ code = [string]$_.code; path = [string]$_.path; message = [string]$_.message } })
    }
    $planId = 'nsp-{0}' -f (Get-OperationSha256 ($identity | ConvertTo-Json -Depth 20 -Compress)).Substring(0, 16)
    return [pscustomobject][ordered]@{
        schema_version = 1
        plan_id = $planId
        status = 'blocked'
        pass = $false
        owner = [string]$Settings.owner
        target_root = [string]$Settings.target_root
        receipt_path = [string]$Settings.receipt_path
        catalog_id = [string](Get-NativeSkillProjectionProperty $Catalog @('catalog_id'))
        enabled = [object[]]@($EnabledNames | Sort-Object)
        kept = [object[]]@()
        omitted = [object[]]@($EnabledNames | Sort-Object)
        skills = [object[]]@()
        actions = [object[]]@()
        removals = [object[]]@()
        enabled_total = @($EnabledNames).Count
        kept_total = 0
        omitted_total = @($EnabledNames).Count
        truncated = $true
        findings = [object[]]@($Findings)
        decision_owner = 'deterministic_projection'
        semantic_selection_applied = $false
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function New-NativeSkillProjectionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)][object[]]$Eligibility,
        [Parameter(Mandatory = $true)]$Config
    )

    $settings = Get-NativeSkillProjectionSettings $Config
    if (-not $settings.enabled) {
        return New-NativeSkillProjectionBlockedPlan $settings $Catalog @() @((New-OperationFinding 'native_projection_disabled' 'error' '$.skill_projection.native_projection.enabled' 'Native projection is disabled.'))
    }
    $entries = @(Get-NativeSkillProjectionProperty $Catalog @('entries'))
    $eligibilityByName = Get-NativeSkillProjectionEligibilityByName $Eligibility
    $entryByName = @{}
    $eligibleEntries = New-Object System.Collections.Generic.List[object]
    $enabledNames = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $entries) {
        $name = ([string](Get-NativeSkillProjectionProperty $entry @('name', 'id'))).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $entryByName[$name] = $entry
        $enabled = -not (Test-OperationObjectProperty $entry 'enabled') -or [bool](Get-NativeSkillProjectionProperty $entry @('enabled'))
        if (-not $enabled) { continue }
        $decision = if ($eligibilityByName.ContainsKey($name)) { $eligibilityByName[$name] } else { $null }
        if ($null -ne $decision -and [string](Get-NativeSkillProjectionProperty $decision @('decision')) -eq 'allow') {
            $eligibleEntries.Add($entry) | Out-Null
            $enabledNames.Add($name) | Out-Null
        }
    }

    $findings = New-Object System.Collections.Generic.List[object]
    $rows = New-Object System.Collections.Generic.List[object]
    $targetLeaves = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($eligibleEntries.ToArray() | Sort-Object name)) {
        $name = ([string](Get-NativeSkillProjectionProperty $entry @('name', 'id'))).Trim()
        $sourcePath = [string](Get-NativeSkillProjectionProperty $entry @('path'))
        $sourcePath = if ([string]::IsNullOrWhiteSpace($sourcePath)) { '' } else { [IO.Path]::GetFullPath($sourcePath) }
        $sourceRoot = [string](Get-NativeSkillProjectionProperty $entry @('source_root'))
        if (-not [string]::IsNullOrWhiteSpace($sourceRoot)) { $sourceRoot = [IO.Path]::GetFullPath($sourceRoot) }
        if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            $findings.Add((New-OperationFinding 'source_path_missing' 'error' ('$.skills[{0}].source_path' -f $name) 'Native projection source path must exist.')) | Out-Null
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($sourceRoot) -and -not (Test-OperationPathWithinRoot $sourcePath $sourceRoot)) {
            $findings.Add((New-OperationFinding 'source_path_outside_root' 'error' ('$.skills[{0}].source_path' -f $name) 'Native projection source path is outside its declared source root.')) | Out-Null
            continue
        }
        $contentHash = ([string](Get-NativeSkillProjectionProperty $entry @('content_hash'))).Trim().ToLowerInvariant()
        $metadataHash = ([string](Get-NativeSkillProjectionProperty $entry @('metadata_hash'))).Trim().ToLowerInvariant()
        if ($contentHash -notmatch '^[0-9a-f]{64}$') { $findings.Add((New-OperationFinding 'content_hash_missing' 'error' ('$.skills[{0}].content_hash' -f $name) 'Native projection requires a SHA-256 content hash.')) | Out-Null }
        if ($metadataHash -notmatch '^[0-9a-f]{64}$') { $findings.Add((New-OperationFinding 'metadata_hash_missing' 'error' ('$.skills[{0}].metadata_hash' -f $name) 'Native projection requires a SHA-256 metadata hash.')) | Out-Null }
        $sourceDirectory = [IO.Path]::GetDirectoryName($sourcePath)
        $packageHash = Get-NativeSkillProjectionPackageHash $sourceDirectory
        if ($packageHash -notmatch '^[0-9a-f]{64}$') { $findings.Add((New-OperationFinding 'package_hash_missing' 'error' ('$.skills[{0}].package_hash' -f $name) 'Native projection requires a SHA-256 package hash.')) | Out-Null }
        $targetLeaf = [IO.Path]::GetFileName($sourceDirectory.TrimEnd('\', '/'))
        if ([string]::IsNullOrWhiteSpace($targetLeaf) -or $targetLeaf -in @('.', '..') -or $targetLeaf.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            $findings.Add((New-OperationFinding 'target_leaf_unsafe' 'error' ('$.entries[{0}].path' -f $name) 'The managed package directory leaf is unsafe for native projection.')) | Out-Null
            continue
        }
        if (-not $targetLeaves.Add($targetLeaf)) {
            $findings.Add((New-OperationFinding 'target_leaf_duplicate' 'error' ('$.entries[{0}].path' -f $name) 'Multiple semantic skills resolve to the same native package directory.')) | Out-Null
            continue
        }
        $targetDirectory = Join-Path $settings.target_root $targetLeaf
        $targetPath = Join-Path $targetDirectory 'SKILL.md'
        $rows.Add([pscustomobject][ordered]@{
                kind = 'skill'
                name = $name
                target_name = $targetLeaf
                source_path = $sourcePath
                source_directory = $sourceDirectory
                source_root = $sourceRoot
                target_directory = $targetDirectory
                target_path = $targetPath
                content_hash = $contentHash
                metadata_hash = $metadataHash
                package_hash = $packageHash
            }) | Out-Null
    }

    $enabledNamesSorted = @($enabledNames.ToArray() | Sort-Object)
    if ($findings.Count -gt 0) { return New-NativeSkillProjectionBlockedPlan $settings $Catalog $enabledNamesSorted $findings.ToArray() }

    $skillRows = @($rows.ToArray() | Sort-Object name)
    $desiredTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $managedRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($skill in $skillRows) {
        $desiredTargets.Add(([IO.Path]::GetFullPath([string]$skill.target_directory).TrimEnd('\', '/'))) | Out-Null
        if (-not [string]::IsNullOrWhiteSpace([string]$skill.source_root)) { $managedRoots.Add(([IO.Path]::GetFullPath([string]$skill.source_root).TrimEnd('\', '/'))) | Out-Null }
    }
    $removalRows = [Collections.Generic.List[object]]::new()
    $receiptOwnedLinks = Get-NativeSkillProjectionReceiptOwnedLinks $settings
    if (Test-Path -LiteralPath $settings.target_root -PathType Container) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $settings.target_root -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $targetDirectory = [IO.Path]::GetFullPath($entry.FullName).TrimEnd('\', '/')
            if ($desiredTargets.Contains($targetDirectory) -or -not [bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
            $linkTargetProperty = $entry.PSObject.Properties['Target']
            $linkTarget = if ($null -eq $linkTargetProperty) { '' } else { @($linkTargetProperty.Value)[0] }
            if ([string]::IsNullOrWhiteSpace([string]$linkTarget)) { continue }
            $linkTarget = [IO.Path]::GetFullPath([string]$linkTarget).TrimEnd('\', '/')
            $owned = $false
            foreach ($managedRoot in $managedRoots) {
                if ($linkTarget.StartsWith(($managedRoot + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { $owned = $true; break }
            }
            if (-not $owned -and $receiptOwnedLinks.ContainsKey($targetDirectory) -and [string]::Equals($receiptOwnedLinks[$targetDirectory], $linkTarget, [StringComparison]::OrdinalIgnoreCase)) { $owned = $true }
            if ($owned) { $removalRows.Add([pscustomobject][ordered]@{ name = $entry.Name; target_directory = $targetDirectory; previous_link_target = $linkTarget }) | Out-Null }
        }
    }
    $identity = [ordered]@{
        target_root = [string]$settings.target_root
        owner = [string]$settings.owner
        catalog_id = [string](Get-NativeSkillProjectionProperty $Catalog @('catalog_id'))
        skills = @($skillRows | ForEach-Object { [ordered]@{ name = $_.name; source_path = $_.source_path; target_path = $_.target_path; content_hash = $_.content_hash; metadata_hash = $_.metadata_hash; package_hash = $_.package_hash } })
        removals = @($removalRows.ToArray() | ForEach-Object { [ordered]@{ name = $_.name; target_directory = $_.target_directory; previous_link_target = $_.previous_link_target } })
    }
    $planId = 'nsp-{0}' -f (Get-OperationSha256 ($identity | ConvertTo-Json -Depth 20 -Compress)).Substring(0, 16)
    $actions = @($skillRows | ForEach-Object {
            [ordered]@{
                action_id = 'nspa-{0}' -f (Get-OperationSha256 ('{0}|{1}' -f $planId, $_.name)).Substring(0, 16)
                type = 'junction'
                name = $_.name
                source_directory = $_.source_directory
                target_directory = $_.target_directory
                target_path = $_.target_path
                expected_content_hash = $_.content_hash
                expected_package_hash = $_.package_hash
                metadata_materialization = 'source_package_junction'
                risk = 'explicit_native_root_write'
            }
        }) + @($removalRows.ToArray() | ForEach-Object {
            [ordered]@{
                action_id = 'nspa-{0}' -f (Get-OperationSha256 ('{0}|remove|{1}' -f $planId, $_.name)).Substring(0, 16)
                type = 'remove_owned_junction'
                name = $_.name
                target_directory = $_.target_directory
                previous_link_target = $_.previous_link_target
                risk = 'explicit_native_root_write'
            }
        })
    return [pscustomobject][ordered]@{
        schema_version = 1
        plan_id = $planId
        status = 'ready'
        pass = $true
        owner = [string]$settings.owner
        target_root = [string]$settings.target_root
        receipt_path = [string]$settings.receipt_path
        catalog_id = [string](Get-NativeSkillProjectionProperty $Catalog @('catalog_id'))
        enabled = [object[]]$enabledNamesSorted
        kept = [object[]]@($skillRows | ForEach-Object name)
        omitted = [object[]]@()
        skills = [object[]]$skillRows
        actions = [object[]]$actions
        removals = [object[]]@($removalRows.ToArray())
        enabled_total = $enabledNamesSorted.Count
        kept_total = $skillRows.Count
        omitted_total = 0
        truncated = $false
        findings = [object[]]@()
        decision_owner = 'deterministic_projection'
        semantic_selection_applied = $false
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function Test-NativeSkillProjectionPlanContract {
    param($Plan)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Plan) { return New-OperationValidationResult @((New-OperationFinding 'projection_plan_missing' 'error' '$' 'Native skill projection plan is required.')) }
    if ((Get-NativeSkillProjectionProperty $Plan @('schema_version')) -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only native skill projection schema version 1 is supported.')) | Out-Null }
    if ([string](Get-NativeSkillProjectionProperty $Plan @('plan_id')) -notmatch '^nsp-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'plan_id_invalid' 'error' '$.plan_id' 'Projection plan id is invalid.')) | Out-Null }
    if ([string](Get-NativeSkillProjectionProperty $Plan @('status')) -notin @('ready', 'blocked')) { $findings.Add((New-OperationFinding 'status_invalid' 'error' '$.status' 'Projection plan status is invalid.')) | Out-Null }
    foreach ($field in @('owner', 'target_root', 'receipt_path')) { if ([string]::IsNullOrWhiteSpace([string](Get-NativeSkillProjectionProperty $Plan @($field)))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Projection plan field is required.')) | Out-Null } }
    foreach ($field in @('enabled', 'kept', 'omitted', 'skills', 'actions', 'removals', 'findings')) { if (-not (Test-OperationArray (Get-OperationObjectProperty $Plan $field))) { $findings.Add((New-OperationFinding 'array_field_invalid' 'error' ('$.{0}' -f $field) 'Projection plan field must be an array.')) | Out-Null } }
    $enabled = @((Get-NativeSkillProjectionProperty $Plan @('enabled')))
    $kept = @((Get-NativeSkillProjectionProperty $Plan @('kept')))
    $omitted = @((Get-NativeSkillProjectionProperty $Plan @('omitted')))
    if ([int](Get-NativeSkillProjectionProperty $Plan @('enabled_total')) -ne $enabled.Count) { $findings.Add((New-OperationFinding 'enabled_count_invalid' 'error' '$.enabled_total' 'enabled_total must match enabled names.')) | Out-Null }
    if ([int](Get-NativeSkillProjectionProperty $Plan @('kept_total')) -ne $kept.Count) { $findings.Add((New-OperationFinding 'kept_count_invalid' 'error' '$.kept_total' 'kept_total must match kept names.')) | Out-Null }
    if ([int](Get-NativeSkillProjectionProperty $Plan @('omitted_total')) -ne $omitted.Count) { $findings.Add((New-OperationFinding 'omitted_count_invalid' 'error' '$.omitted_total' 'omitted_total must match omitted names.')) | Out-Null }
    if ((Get-NativeSkillProjectionProperty $Plan @('status')) -eq 'ready') {
        if ([bool](Get-NativeSkillProjectionProperty $Plan @('pass')) -ne $true -or $kept.Count -ne $enabled.Count -or $omitted.Count -ne 0 -or (Get-NativeSkillProjectionProperty $Plan @('truncated')) -ne $false) { $findings.Add((New-OperationFinding 'complete_projection_invalid' 'error' '$' 'A ready plan must retain every eligible enabled skill.')) | Out-Null }
    }
    if ((Get-NativeSkillProjectionProperty $Plan @('semantic_selection_applied')) -ne $false) { $findings.Add((New-OperationFinding 'semantic_boundary_breached' 'error' '$' 'Projection cannot apply semantic selection.')) | Out-Null }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) { if ([long](Get-NativeSkillProjectionProperty $Plan @($field)) -ne 0) { $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Planning must not mutate the native surface.')) | Out-Null } }
    foreach ($skill in @((Get-NativeSkillProjectionProperty $Plan @('skills')))) {
        foreach ($field in @('name', 'source_path', 'target_path', 'content_hash', 'metadata_hash', 'package_hash')) { if ([string]::IsNullOrWhiteSpace([string](Get-NativeSkillProjectionProperty $skill @($field)))) { $findings.Add((New-OperationFinding 'skill_field_missing' 'error' '$.skills' ('Projected skill field is missing: {0}' -f $field))) | Out-Null } }
        if ([string](Get-NativeSkillProjectionProperty $skill @('content_hash')) -notmatch '^[0-9a-f]{64}$' -or [string](Get-NativeSkillProjectionProperty $skill @('metadata_hash')) -notmatch '^[0-9a-f]{64}$' -or [string](Get-NativeSkillProjectionProperty $skill @('package_hash')) -notmatch '^[0-9a-f]{64}$') { $findings.Add((New-OperationFinding 'skill_hash_invalid' 'error' '$.skills' 'Projected skill hashes must be SHA-256.')) | Out-Null }
    }
    return New-OperationValidationResult $findings.ToArray()
}

function Get-SkillProjectionProfileObjectNames($Object, [string]$FieldName) {
    if ($Object -is [System.Collections.IDictionary]) { return @($Object.Keys | ForEach-Object { [string]$_ }) }
    if ($Object -is [pscustomobject]) { return @($Object.PSObject.Properties | ForEach-Object { [string]$_.Name }) }
    throw ("{0} 必须是对象" -f $FieldName)
}

function Get-SkillProjectionProfileNames($Values, [string]$FieldName) {
    if ($null -eq $Values) { return @() }
    if ($Values -is [string] -or $Values -isnot [System.Collections.IEnumerable]) { throw ("{0} 必须是数组" -f $FieldName) }

    $names = [Collections.Generic.List[string]]::new()
    foreach ($value in @($Values)) {
        $name = ([string]$value).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($name)) { throw ("{0} 不能包含空字符串" -f $FieldName) }
        if ($name -notmatch '^[a-z0-9][a-z0-9-]*$') { throw ("{0} 包含非法技能名：{1}" -f $FieldName, $name) }
        $names.Add($name) | Out-Null
    }
    $duplicates = @($names | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name | Sort-Object)
    if ($duplicates.Count -gt 0) { throw ("{0} 重复：{1}" -f $FieldName, ($duplicates -join ', ')) }
    return @($names.ToArray())
}

function Get-SkillProjectionTargetHost($TargetConfig) {
    $configuredHost = ([string](Get-OperationObjectProperty $TargetConfig 'host')).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($configuredHost)) {
        if ($configuredHost -notin @('codex', 'claude', 'zcode')) { throw ("managed_link_only target.host 不受支持：{0}" -f $configuredHost) }
        return $configuredHost
    }

    $path = ([string](Get-OperationObjectProperty $TargetConfig 'path')).Trim().Replace('/', '\').TrimEnd('\')
    if ($path -match '(?i)\\\.claude\\skills$') { return 'claude' }
    if ($path -match '(?i)\\\.zcode\\skills$') { return 'zcode' }
    throw ("managed_link_only target 缺少 host，且无法由 path 推导宿主：{0}" -f $path)
}

function Resolve-SkillProjectionSelection {
    param(
        [Parameter(Mandatory = $true)]$ProjectionConfig,
        [Parameter(Mandatory = $true)][ValidateSet('codex', 'claude', 'zcode')][string]$HostName,
        [string]$RequestedProfile = ''
    )

    $requested = $RequestedProfile.Trim().ToLowerInvariant()
    $profilesConfig = Get-OperationObjectProperty $ProjectionConfig 'projection_profiles'
    if ($null -eq $profilesConfig) {
        if (-not [string]::IsNullOrWhiteSpace($requested)) { throw ("skill_projection 未配置 projection_profiles，不能选择 profile：{0}" -f $requested) }
        return [pscustomobject][ordered]@{
            host = $HostName
            profile = 'legacy'
            include_all = $false
            included_names = @(Get-SkillProjectionProfileNames (Get-OperationObjectProperty $ProjectionConfig 'managed_link_includes') 'skill_projection.managed_link_includes')
            excluded_names = @(Get-SkillProjectionProfileNames (Get-OperationObjectProperty $ProjectionConfig 'managed_link_excludes') 'skill_projection.managed_link_excludes')
            uses_profiles = $false
        }
    }

    $schemaVersion = Get-OperationObjectProperty $profilesConfig 'schema_version'
    if ([string]$schemaVersion -ne '1') { throw 'skill_projection.projection_profiles.schema_version 必须为 1' }
    $profiles = Get-OperationObjectProperty $profilesConfig 'profiles'
    $profileNames = @(Get-SkillProjectionProfileObjectNames $profiles 'skill_projection.projection_profiles.profiles')
    if ($profileNames.Count -eq 0) { throw 'skill_projection.projection_profiles.profiles 至少需要一个 profile' }
    foreach ($profileName in $profileNames) {
        if ($profileName -notmatch '^[a-z0-9][a-z0-9-]*$') { throw ("skill_projection.projection_profiles.profiles 包含非法 profile 名：{0}" -f $profileName) }
    }

    $hosts = Get-OperationObjectProperty $profilesConfig 'hosts'
    if ($null -ne $hosts) {
        foreach ($configuredHost in @(Get-SkillProjectionProfileObjectNames $hosts 'skill_projection.projection_profiles.hosts')) {
            if ($configuredHost -notin @('codex', 'claude', 'zcode')) { throw ("skill_projection.projection_profiles.hosts 包含不受支持宿主：{0}" -f $configuredHost) }
        }
    }
    $hostConfig = if ($null -eq $hosts) { $null } else { Get-OperationObjectProperty $hosts $HostName }
    $defaultProfile = if (-not [string]::IsNullOrWhiteSpace($requested)) {
        $requested
    }
    elseif ($null -ne $hostConfig -and -not [string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $hostConfig 'default_profile'))) {
        ([string](Get-OperationObjectProperty $hostConfig 'default_profile')).Trim().ToLowerInvariant()
    }
    else {
        ([string](Get-OperationObjectProperty $profilesConfig 'default_profile')).Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($defaultProfile)) { throw ("skill_projection.projection_profiles 缺少 {0} 的 default_profile" -f $HostName) }
    if ($defaultProfile -notin $profileNames) { throw ("skill_projection.projection_profiles 引用了不存在的 profile：{0}" -f $defaultProfile) }

    $profile = Get-OperationObjectProperty $profiles $defaultProfile
    if ($profile -isnot [pscustomobject] -and $profile -isnot [System.Collections.IDictionary]) { throw ("skill_projection.projection_profiles.profiles.{0} 必须是对象" -f $defaultProfile) }
    $includeAllRaw = Get-OperationObjectProperty $profile 'include_all'
    if ($null -ne $includeAllRaw -and $includeAllRaw -isnot [bool]) { throw ("skill_projection.projection_profiles.profiles.{0}.include_all 必须是布尔值" -f $defaultProfile) }
    $includeAll = ($includeAllRaw -eq $true)
    $included = @(Get-SkillProjectionProfileNames (Get-OperationObjectProperty $profile 'include') ("skill_projection.projection_profiles.profiles.{0}.include" -f $defaultProfile))
    $excluded = @(Get-SkillProjectionProfileNames (Get-OperationObjectProperty $profile 'exclude') ("skill_projection.projection_profiles.profiles.{0}.exclude" -f $defaultProfile))
    if ($includeAll -and $included.Count -gt 0) { throw ("skill_projection.projection_profiles.profiles.{0} 的 include_all=true 时 include 必须为空" -f $defaultProfile) }
    if (-not $includeAll -and $included.Count -eq 0) { throw ("skill_projection.projection_profiles.profiles.{0} 必须提供 include 或 include_all=true" -f $defaultProfile) }
    $profileConflicts = @($included | Where-Object { $excluded -contains $_ } | Sort-Object -Unique)
    if ($profileConflicts.Count -gt 0) { throw ("skill_projection.projection_profiles.profiles.{0} include/exclude 冲突：{1}" -f $defaultProfile, ($profileConflicts -join ', ')) }

    $hostExcludes = if ($null -eq $hostConfig) { @() } else { @(Get-SkillProjectionProfileNames (Get-OperationObjectProperty $hostConfig 'exclude') ("skill_projection.projection_profiles.hosts.{0}.exclude" -f $HostName)) }
    return [pscustomobject][ordered]@{
        host = $HostName
        profile = $defaultProfile
        include_all = $includeAll
        included_names = @($included)
        excluded_names = @($excluded + $hostExcludes | Sort-Object -Unique)
        uses_profiles = $true
    }
}

function Get-SkillProjectionEffectiveSelection {
    param($ProjectionConfig, [ValidateSet('codex', 'claude', 'zcode')][string]$DefaultHost = 'codex')

    $selection = Get-OperationObjectProperty $ProjectionConfig 'resolved_projection_selection'
    if ($null -ne $selection) {
        $selectionHost = ([string](Get-OperationObjectProperty $selection 'host')).Trim().ToLowerInvariant()
        if ($selectionHost -notin @('codex', 'claude', 'zcode')) { throw 'resolved_projection_selection.host 不受支持' }
        return $selection
    }
    return Resolve-SkillProjectionSelection -ProjectionConfig $ProjectionConfig -HostName $DefaultHost
}

function New-SkillProjectionHostConfig {
    param(
        [Parameter(Mandatory = $true)]$ProjectionConfig,
        [Parameter(Mandatory = $true)]$Selection
    )

    $copy = [ordered]@{}
    if ($ProjectionConfig -is [System.Collections.IDictionary]) {
        foreach ($key in @($ProjectionConfig.Keys)) { $copy[[string]$key] = $ProjectionConfig[$key] }
    }
    else {
        foreach ($property in @($ProjectionConfig.PSObject.Properties)) { $copy[[string]$property.Name] = $property.Value }
    }
    $copy['managed_link_includes'] = @((Get-OperationObjectProperty $Selection 'included_names') | ForEach-Object { [string]$_ })
    $copy['managed_link_excludes'] = @((Get-OperationObjectProperty $Selection 'excluded_names') | ForEach-Object { [string]$_ })
    $copy['resolved_projection_selection'] = $Selection
    return [pscustomobject]$copy
}

function Get-SkillProjectionProfileContractErrors($ProjectionConfig, $Targets = @()) {
    $profilesConfig = Get-OperationObjectProperty $ProjectionConfig 'projection_profiles'
    if ($null -eq $profilesConfig) { return @() }

    $errors = [Collections.Generic.List[string]]::new()
    try {
        $profiles = Get-OperationObjectProperty $profilesConfig 'profiles'
        $profileNames = @(Get-SkillProjectionProfileObjectNames $profiles 'skill_projection.projection_profiles.profiles')
        foreach ($projectionHost in @('codex', 'claude', 'zcode')) {
            Resolve-SkillProjectionSelection -ProjectionConfig $ProjectionConfig -HostName $projectionHost | Out-Null
            foreach ($profileName in $profileNames) { Resolve-SkillProjectionSelection -ProjectionConfig $ProjectionConfig -HostName $projectionHost -RequestedProfile $profileName | Out-Null }
        }
        foreach ($target in @($Targets | Where-Object { [bool](Get-OperationObjectProperty $_ 'managed_link_only') })) {
            $targetHost = Get-SkillProjectionTargetHost $target
            Resolve-SkillProjectionSelection -ProjectionConfig $ProjectionConfig -HostName $targetHost | Out-Null
        }
    }
    catch { $errors.Add($_.Exception.Message) | Out-Null }
    return @($errors.ToArray())
}
