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
    $notificationMethod = ([string](Get-NativeSkillProjectionProperty $settings @('notification_method'))).Trim()
    $notificationMode = ([string](Get-NativeSkillProjectionProperty $settings @('notification_mode'))).Trim()
    if ([string]::IsNullOrWhiteSpace($owner)) { throw 'skill_projection.native_projection.owner is required.' }
    if ([string]::IsNullOrWhiteSpace($targetRoot)) { throw 'skill_projection.native_projection.target_root is required.' }
    if ([string]::IsNullOrWhiteSpace($receiptPath)) { throw 'skill_projection.native_projection.receipt_path is required.' }
    if ([string]::IsNullOrWhiteSpace($userSkillRoot)) { throw 'skill_projection.user_skill_root is required for native projection.' }
    if (-not [string]::Equals($targetRoot.TrimEnd('\', '/'), $userSkillRoot.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'skill_projection.native_projection.target_root must equal skill_projection.user_skill_root.' }
    if ([string]::Equals($targetRoot.TrimEnd('\', '/'), [IO.Path]::GetPathRoot($targetRoot).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'skill_projection.native_projection.target_root must not be a filesystem root.' }
    if (-not (Test-NativeSkillProjectionPathWithinRoot $receiptPath $receiptRoot) -or [string]::Equals($receiptPath.TrimEnd('\', '/'), $receiptRoot.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { throw 'skill_projection.native_projection.receipt_path must be a file under reports/skill-projection.' }
    Assert-NativeSkillProjectionPathHasNoReparseAncestor (Split-Path $receiptPath -Parent) $receiptRoot
    if ([string]::IsNullOrWhiteSpace($notificationMethod)) { $notificationMethod = 'skills/changed' }
    if ([string]::IsNullOrWhiteSpace($notificationMode)) { $notificationMode = 'plan_only' }
    return [pscustomobject][ordered]@{
        enabled = $enabled
        owner = $owner
        target_root = $targetRoot
        receipt_path = $receiptPath
        apply_requires_token = if (Test-OperationObjectProperty $settings 'apply_requires_token') { [bool](Get-OperationObjectProperty $settings 'apply_requires_token') } else { $true }
        notification_method = $notificationMethod
        notification_mode = $notificationMode
    }
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
        apply_requires_token = [bool]$Settings.apply_requires_token
        apply_token = ''
        catalog_id = [string](Get-NativeSkillProjectionProperty $Catalog @('catalog_id'))
        enabled = [object[]]@($EnabledNames | Sort-Object)
        kept = [object[]]@()
        omitted = [object[]]@($EnabledNames | Sort-Object)
        skills = [object[]]@()
        actions = [object[]]@()
        enabled_total = @($EnabledNames).Count
        kept_total = 0
        omitted_total = @($EnabledNames).Count
        truncated = $true
        findings = [object[]]@($Findings)
        notification = [ordered]@{
            method = [string]$Settings.notification_method
            mode = [string]$Settings.notification_mode
            status = 'blocked'
            changed_names = @()
            host_mutation = $false
        }
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
            }) | Out-Null
    }

    $enabledNamesSorted = @($enabledNames.ToArray() | Sort-Object)
    if ($findings.Count -gt 0) { return New-NativeSkillProjectionBlockedPlan $settings $Catalog $enabledNamesSorted $findings.ToArray() }

    $skillRows = @($rows.ToArray() | Sort-Object name)
    $identity = [ordered]@{
        target_root = [string]$settings.target_root
        owner = [string]$settings.owner
        catalog_id = [string](Get-NativeSkillProjectionProperty $Catalog @('catalog_id'))
        skills = @($skillRows | ForEach-Object { [ordered]@{ name = $_.name; source_path = $_.source_path; target_path = $_.target_path; content_hash = $_.content_hash; metadata_hash = $_.metadata_hash } })
    }
    $planId = 'nsp-{0}' -f (Get-OperationSha256 ($identity | ConvertTo-Json -Depth 20 -Compress)).Substring(0, 16)
    $applyToken = 'nsp-token-{0}' -f (Get-OperationSha256 ('{0}|apply' -f $planId)).Substring(0, 16)
    $actions = @($skillRows | ForEach-Object {
            [ordered]@{
                action_id = 'nspa-{0}' -f (Get-OperationSha256 ('{0}|{1}' -f $planId, $_.name)).Substring(0, 16)
                type = 'junction'
                name = $_.name
                source_directory = $_.source_directory
                target_directory = $_.target_directory
                target_path = $_.target_path
                expected_content_hash = $_.content_hash
                metadata_materialization = 'source_package_junction'
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
        apply_requires_token = [bool]$settings.apply_requires_token
        apply_token = $applyToken
        catalog_id = [string](Get-NativeSkillProjectionProperty $Catalog @('catalog_id'))
        enabled = [object[]]$enabledNamesSorted
        kept = [object[]]@($skillRows | ForEach-Object name)
        omitted = [object[]]@()
        skills = [object[]]$skillRows
        actions = [object[]]$actions
        enabled_total = $enabledNamesSorted.Count
        kept_total = $skillRows.Count
        omitted_total = 0
        truncated = $false
        findings = [object[]]@()
        notification = [ordered]@{
            method = [string]$settings.notification_method
            mode = [string]$settings.notification_mode
            status = 'planned_only'
            changed_names = @($skillRows | ForEach-Object name)
            host_mutation = $false
        }
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
    foreach ($field in @('enabled', 'kept', 'omitted', 'skills', 'actions', 'findings')) { if (-not (Test-OperationArray (Get-OperationObjectProperty $Plan $field))) { $findings.Add((New-OperationFinding 'array_field_invalid' 'error' ('$.{0}' -f $field) 'Projection plan field must be an array.')) | Out-Null } }
    $enabled = @((Get-NativeSkillProjectionProperty $Plan @('enabled')))
    $kept = @((Get-NativeSkillProjectionProperty $Plan @('kept')))
    $omitted = @((Get-NativeSkillProjectionProperty $Plan @('omitted')))
    if ([int](Get-NativeSkillProjectionProperty $Plan @('enabled_total')) -ne $enabled.Count) { $findings.Add((New-OperationFinding 'enabled_count_invalid' 'error' '$.enabled_total' 'enabled_total must match enabled names.')) | Out-Null }
    if ([int](Get-NativeSkillProjectionProperty $Plan @('kept_total')) -ne $kept.Count) { $findings.Add((New-OperationFinding 'kept_count_invalid' 'error' '$.kept_total' 'kept_total must match kept names.')) | Out-Null }
    if ([int](Get-NativeSkillProjectionProperty $Plan @('omitted_total')) -ne $omitted.Count) { $findings.Add((New-OperationFinding 'omitted_count_invalid' 'error' '$.omitted_total' 'omitted_total must match omitted names.')) | Out-Null }
    if ((Get-NativeSkillProjectionProperty $Plan @('status')) -eq 'ready') {
        if ([bool](Get-NativeSkillProjectionProperty $Plan @('pass')) -ne $true -or $kept.Count -ne $enabled.Count -or $omitted.Count -ne 0 -or (Get-NativeSkillProjectionProperty $Plan @('truncated')) -ne $false) { $findings.Add((New-OperationFinding 'complete_projection_invalid' 'error' '$' 'A ready plan must retain every eligible enabled skill.')) | Out-Null }
        if ([string](Get-NativeSkillProjectionProperty $Plan @('apply_token')) -notmatch '^nsp-token-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'apply_token_invalid' 'error' '$.apply_token' 'Ready plans require an explicit apply token.')) | Out-Null }
    }
    if ((Get-NativeSkillProjectionProperty $Plan @('semantic_selection_applied')) -ne $false) { $findings.Add((New-OperationFinding 'semantic_boundary_breached' 'error' '$' 'Projection cannot apply semantic selection.')) | Out-Null }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) { if ([long](Get-NativeSkillProjectionProperty $Plan @($field)) -ne 0) { $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Planning must not mutate the native surface.')) | Out-Null } }
    $notification = Get-NativeSkillProjectionProperty $Plan @('notification')
    if ([string](Get-NativeSkillProjectionProperty $notification @('method')) -ne 'skills/changed') { $findings.Add((New-OperationFinding 'notification_method_invalid' 'error' '$.notification.method' 'Native projection uses the skills/changed notification plan.')) | Out-Null }
    if ([string](Get-NativeSkillProjectionProperty $notification @('status')) -notin @('planned_only', 'blocked')) { $findings.Add((New-OperationFinding 'notification_status_invalid' 'error' '$.notification.status' 'Notification must remain a plan-only or blocked action.')) | Out-Null }
    foreach ($skill in @((Get-NativeSkillProjectionProperty $Plan @('skills')))) {
        foreach ($field in @('name', 'source_path', 'target_path', 'content_hash', 'metadata_hash')) { if ([string]::IsNullOrWhiteSpace([string](Get-NativeSkillProjectionProperty $skill @($field)))) { $findings.Add((New-OperationFinding 'skill_field_missing' 'error' '$.skills' ('Projected skill field is missing: {0}' -f $field))) | Out-Null } }
        if ([string](Get-NativeSkillProjectionProperty $skill @('content_hash')) -notmatch '^[0-9a-f]{64}$' -or [string](Get-NativeSkillProjectionProperty $skill @('metadata_hash')) -notmatch '^[0-9a-f]{64}$') { $findings.Add((New-OperationFinding 'skill_hash_invalid' 'error' '$.skills' 'Projected skill hashes must be SHA-256.')) | Out-Null }
    }
    return New-OperationValidationResult $findings.ToArray()
}
