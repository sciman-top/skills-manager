function ConvertFrom-CodexPluginInventorySnapshot {
    param($Snapshot, [ValidateSet('official', 'personal', 'workspace')][string]$Scope)

    $descriptors = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($state in @('installed', 'available')) {
        $items = Get-OperationObjectProperty $Snapshot $state
        if (-not (Test-OperationArray $items)) {
            $findings.Add((New-OperationFinding 'plugin_snapshot_array_missing' 'error' ('$.{0}' -f $state) ('Snapshot scope {0} must contain an array.' -f $Scope))) | Out-Null
            continue
        }
        foreach ($item in @($items)) {
            $pluginId = [string](Get-OperationObjectProperty $item 'pluginId')
            $name = [string](Get-OperationObjectProperty $item 'name')
            $marketplace = [string](Get-OperationObjectProperty $item 'marketplaceName')
            $version = [string](Get-OperationObjectProperty $item 'version')
            if ([string]::IsNullOrWhiteSpace($pluginId) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($marketplace)) {
                $findings.Add((New-OperationFinding 'plugin_snapshot_item_invalid' 'error' ('$.{0}' -f $state) 'pluginId, name, and marketplaceName are required.')) | Out-Null
                continue
            }
            $source = [pscustomobject]@{
                type = 'codex_plugin_snapshot'
                path_or_url = 'codex-plugin://{0}/{1}' -f $Scope, $pluginId
                revision = $(if ([string]::IsNullOrWhiteSpace($version)) { $null } else { $version })
                checksum = $null
                license = $null
                trust_tier = $Scope
            }
            $origin = if ($Scope -eq 'official') { 'official' } elseif ([bool](Get-OperationObjectProperty $item 'installed')) { 'host_installed' } else { 'candidate' }
            $components = @([pscustomobject][ordered]@{
                kind = 'plugin_bundle'
                distribution_scope = $Scope
                inventory_state = $state
                marketplace = $marketplace
                installed = [bool](Get-OperationObjectProperty $item 'installed')
                enabled = [bool](Get-OperationObjectProperty $item 'enabled')
                install_policy = [string](Get-OperationObjectProperty $item 'installPolicy')
                auth_policy = [string](Get-OperationObjectProperty $item 'authPolicy')
            })
            $descriptors.Add((New-CapabilityDescriptor -Kind plugin -Name $name -TruthOrigin $origin -Source $source -Lifecycle active -HostCompatibility @('codex') -Components $components -VerificationState static_validated)) | Out-Null
        }
    }
    return [pscustomobject][ordered]@{ scope = $Scope; descriptors = $descriptors.ToArray(); findings = $findings.ToArray() }
}

function New-PluginInventoryFromSnapshots {
    param($Official, $Personal = $null, $Workspace = $null)

    $descriptors = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(
        [pscustomobject]@{ scope = 'official'; value = $Official },
        [pscustomobject]@{ scope = 'personal'; value = $Personal },
        [pscustomobject]@{ scope = 'workspace'; value = $Workspace }
    )) {
        if ($null -eq $entry.value) { continue }
        $result = ConvertFrom-CodexPluginInventorySnapshot $entry.value $entry.scope
        foreach ($item in @($result.descriptors)) { $descriptors.Add($item) | Out-Null }
        foreach ($finding in @($result.findings)) { $findings.Add($finding) | Out-Null }
    }
    $inventory = New-CapabilityInventory $descriptors.ToArray()
    foreach ($finding in @($findings.ToArray())) { $inventory.findings += $finding }
    return [pscustomobject][ordered]@{
        schema_version = 1
        read_only = $true
        pass = (@($inventory.findings | Where-Object severity -eq 'error').Count -eq 0)
        descriptors = @($inventory.descriptors)
        decisions = @($inventory.decisions)
        findings = @($inventory.findings)
        provider_calls = 0
        native_mutations = 0
        writes = 0
        profile_changed = $false
    }
}

function Get-PluginFileInventory([string]$Root) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Sort-Object FullName)) {
        $relative = $file.FullName.Substring(([System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar).Length).Replace('\', '/')
        $items.Add([pscustomobject][ordered]@{ relative_path = $relative; length = [int64]$file.Length; sha256 = (Get-FileContentHash $file.FullName) }) | Out-Null
    }
    return $items.ToArray()
}

function Test-PluginCandidateContract($Candidate, [string]$FixtureRoot) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ([int](Get-OperationObjectProperty $Candidate 'schema_version') -ne 1) { $findings.Add((New-PluginContractFinding 'candidate_schema_invalid' '$.schema_version' 'Candidate schema_version must be 1.')) | Out-Null }
    foreach ($field in @('name', 'version', 'description', 'repository', 'license')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Candidate $field))) { $findings.Add((New-PluginContractFinding 'candidate_field_missing' ('$.{0}' -f $field) 'Candidate field is required.')) | Out-Null }
    }
    foreach ($field in @('audiences', 'source_skills', 'evidence_refs')) {
        if (-not (Test-OperationArray (Get-OperationObjectProperty $Candidate $field)) -or @((Get-OperationObjectProperty $Candidate $field)).Count -eq 0) { $findings.Add((New-PluginContractFinding 'candidate_array_invalid' ('$.{0}' -f $field) 'Candidate array must be non-empty.')) | Out-Null }
    }
    if ([string](Get-OperationObjectProperty $Candidate 'distribution_need') -ne 'repeated') { $findings.Add((New-PluginContractFinding 'candidate_distribution_need_unproven' '$.distribution_need' 'Exporter requires repeated distribution evidence.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Candidate 'official_equivalent') -ne 'absent_after_review') { $findings.Add((New-PluginContractFinding 'candidate_official_equivalent_unresolved' '$.official_equivalent' 'Official equivalent review must be explicitly absent.')) | Out-Null }
    $manifest = [pscustomobject][ordered]@{
        name = [string](Get-OperationObjectProperty $Candidate 'name')
        version = [string](Get-OperationObjectProperty $Candidate 'version')
        description = [string](Get-OperationObjectProperty $Candidate 'description')
        repository = [string](Get-OperationObjectProperty $Candidate 'repository')
        license = [string](Get-OperationObjectProperty $Candidate 'license')
        skills = './skills/'
    }
    $manifestValidation = Test-PluginManifestContract $manifest '' $true
    foreach ($finding in @($manifestValidation.findings | Where-Object code -notin @('plugin_component_missing'))) { $findings.Add($finding) | Out-Null }
    $sources = New-Object System.Collections.Generic.List[object]
    foreach ($relative in @((Get-OperationObjectProperty $Candidate 'source_skills'))) {
        $text = [string]$relative
        if (-not (Test-PluginRelativeComponentPath $text)) { $findings.Add((New-PluginContractFinding 'candidate_source_path_invalid' '$.source_skills' ('Invalid source path: {0}' -f $text))) | Out-Null; continue }
        $full = [System.IO.Path]::GetFullPath((Join-Path $FixtureRoot $text.Substring(2)))
        if (-not (Test-PluginPathWithin $full $FixtureRoot) -or -not (Test-Path -LiteralPath $full -PathType Container)) { $findings.Add((New-PluginContractFinding 'candidate_source_missing' '$.source_skills' ('Source skill is missing or outside fixture: {0}' -f $text))) | Out-Null; continue }
        if (Test-PluginReparsePoint $full) { $findings.Add((New-PluginContractFinding 'candidate_source_reparse_forbidden' '$.source_skills' ('Source skill is a reparse point: {0}' -f $text))) | Out-Null; continue }
        if (Test-PluginExistingAncestorReparsePoint $full $FixtureRoot) { $findings.Add((New-PluginContractFinding 'candidate_source_ancestor_reparse_forbidden' '$.source_skills' ('Source skill crosses a reparse point: {0}' -f $text))) | Out-Null; continue }
        if (Test-PluginTreeContainsReparsePoint $full) { $findings.Add((New-PluginContractFinding 'candidate_source_tree_reparse_forbidden' '$.source_skills' ('Source skill contains a reparse point: {0}' -f $text))) | Out-Null; continue }
        if (-not (Test-Path -LiteralPath (Join-Path $full 'SKILL.md') -PathType Leaf)) { $findings.Add((New-PluginContractFinding 'candidate_skill_manifest_missing' '$.source_skills' ('Source skill lacks SKILL.md: {0}' -f $text))) | Out-Null; continue }
        $sources.Add([pscustomobject]@{ relative = $text; full_path = $full; name = (Split-Path $full -Leaf) }) | Out-Null
    }
    if ($sources.Count -gt 8) { $findings.Add((New-PluginContractFinding 'candidate_skill_limit_exceeded' '$.source_skills' 'At most 8 skills may be exported.')) | Out-Null }
    return [pscustomobject][ordered]@{ pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0); findings = $findings.ToArray(); manifest = $manifest; sources = $sources.ToArray() }
}

function Test-PluginSkillBehaviorFixture([string]$PluginRoot) {
    $findings = New-Object System.Collections.Generic.List[object]
    $skillsRoot = Join-Path $PluginRoot 'skills'
    foreach ($skillDir in @(Get-ChildItem -LiteralPath $skillsRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        $path = Join-Path $skillDir.FullName 'SKILL.md'
        if (-not (Test-YamlFrontmatterSkillFile $path)) { $findings.Add((New-PluginContractFinding 'skill_frontmatter_invalid' ('skills/{0}/SKILL.md' -f $skillDir.Name) 'Skill must start with YAML frontmatter.')) | Out-Null; continue }
        $text = Get-ContentUtf8 $path
        if ($text -notmatch '(?m)^name:\s*\S+' -or $text -notmatch '(?m)^description:\s*\S+') { $findings.Add((New-PluginContractFinding 'skill_metadata_incomplete' ('skills/{0}/SKILL.md' -f $skillDir.Name) 'Skill frontmatter must declare name and description.')) | Out-Null }
    }
    return [pscustomobject][ordered]@{ pass = ($findings.Count -eq 0); state = $(if ($findings.Count -eq 0) { 'pass' } else { 'fail' }); findings = $findings.ToArray() }
}

function New-PluginEvaluationReport([string]$PluginRoot, $ModelSnapshot = $null) {
    $manifestPath = Join-Path $PluginRoot '.codex-plugin\plugin.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Plugin manifest does not exist.' }
    $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $static = Test-PluginManifestContract $manifest $PluginRoot $true
    $behavior = if ($static.pass -and (Get-PluginShape $manifest) -eq 'skills_only') { Test-PluginSkillBehaviorFixture $PluginRoot } else { [pscustomobject]@{ pass = $false; state = 'blocked'; findings = @() } }
    $modelState = if ($null -eq $ModelSnapshot) { 'not_run' } else { [string](Get-OperationObjectProperty $ModelSnapshot 'state') }
    if ($modelState -notin @('pass', 'fail', 'not_run')) { $modelState = 'invalid_snapshot' }
    return [pscustomobject][ordered]@{
        schema_version = 1
        pass = ([bool]$static.pass -and [bool]$behavior.pass)
        truth_boundary = 'repo_fixture_evaluation'
        layers = [pscustomobject][ordered]@{
            static = [pscustomobject]@{ state = $(if ($static.pass) { 'pass' } else { 'fail' }); blocking = $true; findings = @($static.findings) }
            behavior_fixture = [pscustomobject]@{ state = $behavior.state; blocking = $true; findings = @($behavior.findings) }
            model_snapshot = [pscustomobject]@{ state = $modelState; blocking = $false }
            host_load = [pscustomobject]@{ state = 'not_run'; blocking = $false }
            live_workflow = [pscustomobject]@{ state = 'not_run'; blocking = $false }
        }
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function Export-PluginFixture {
    param($Candidate, [string]$FixtureRoot, [string]$OutPath, [string]$Token)

    $root = [System.IO.Path]::GetFullPath($FixtureRoot)
    $out = [System.IO.Path]::GetFullPath($OutPath)
    $findings = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $root -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $root '.skills-manager-fixture') -PathType Leaf)) { $findings.Add((New-PluginContractFinding 'fixture_marker_missing' '$.fixture_root' 'Fixture root must exist and contain .skills-manager-fixture.')) | Out-Null }
    if ($Token -ne 'EXPORT_PLUGIN_FIXTURE') { $findings.Add((New-PluginContractFinding 'export_token_invalid' '$.token' 'Exact token EXPORT_PLUGIN_FIXTURE is required.')) | Out-Null }
    if (-not (Test-PluginPathWithin $out $root) -or $out.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { $findings.Add((New-PluginContractFinding 'export_output_outside_fixture' '$.out' 'Output must be a new child path inside the fixture root.')) | Out-Null }
    if (Test-Path -LiteralPath $out) { $findings.Add((New-PluginContractFinding 'export_output_exists' '$.out' 'Exporter never overwrites an existing output.')) | Out-Null }
    if (Test-PluginReparsePoint $root) { $findings.Add((New-PluginContractFinding 'fixture_root_reparse_forbidden' '$.fixture_root' 'Reparse fixture roots are not supported.')) | Out-Null }
    if ((Test-PluginPathWithin $out $root) -and (Test-PluginExistingAncestorReparsePoint $out $root)) { $findings.Add((New-PluginContractFinding 'export_path_reparse_forbidden' '$.out' 'Output must not cross an existing reparse-point ancestor.')) | Out-Null }
    $candidateValidation = Test-PluginCandidateContract $Candidate $root
    foreach ($finding in @($candidateValidation.findings)) { $findings.Add($finding) | Out-Null }

    $sourceFiles = New-Object System.Collections.Generic.List[object]
    foreach ($source in @($candidateValidation.sources)) {
        foreach ($item in @(Get-PluginFileInventory $source.full_path)) {
            $sourceFiles.Add([pscustomobject]@{ skill_name = $source.name; source_path = $source.full_path; relative_path = $item.relative_path; length = $item.length; sha256 = $item.sha256 }) | Out-Null
        }
    }
    if ($sourceFiles.Count -gt 256) { $findings.Add((New-PluginContractFinding 'export_file_limit_exceeded' '$.source_skills' 'Export is limited to 256 files.')) | Out-Null }
    $totalBytes = [int64](($sourceFiles.ToArray() | Measure-Object length -Sum).Sum)
    if ($totalBytes -gt 2097152) { $findings.Add((New-PluginContractFinding 'export_byte_limit_exceeded' '$.source_skills' 'Export is limited to 2 MiB.')) | Out-Null }
    if ($findings.Count -gt 0) { return [pscustomobject][ordered]@{ schema_version = 1; pass = $false; status = 'blocked'; findings = $findings.ToArray(); writes = 0; provider_calls = 0; native_mutations = 0 } }

    $parent = Split-Path $out -Parent
    $stage = Join-Path $parent ('.{0}.staging-{1}' -f (Split-Path $out -Leaf), [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.Directory]::CreateDirectory((Join-Path $stage '.codex-plugin')) | Out-Null
        [System.IO.Directory]::CreateDirectory((Join-Path $stage 'skills')) | Out-Null
        $manifestJson = $candidateValidation.manifest | ConvertTo-Json -Depth 20
        Write-Utf8FileAtomic -Path (Join-Path $stage '.codex-plugin\plugin.json') -Content $manifestJson
        foreach ($sourceFile in @($sourceFiles.ToArray())) {
            $destination = Join-Path (Join-Path (Join-Path $stage 'skills') $sourceFile.skill_name) $sourceFile.relative_path
            [System.IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
            [System.IO.File]::Copy((Join-Path $sourceFile.source_path $sourceFile.relative_path), $destination, $false)
        }
        $lint = Test-PluginManifestContract $candidateValidation.manifest $stage $true
        if (-not $lint.pass) { throw ('Exported manifest failed lint: {0}' -f (@($lint.findings.code) -join ',')) }
        foreach ($sourceFile in @($sourceFiles.ToArray())) {
            $destination = Join-Path (Join-Path (Join-Path $stage 'skills') $sourceFile.skill_name) $sourceFile.relative_path
            if ((Get-FileContentHash $destination) -ne $sourceFile.sha256) { throw ('Round-trip hash mismatch: {0}' -f $sourceFile.relative_path) }
        }
        [System.IO.Directory]::Move($stage, $out)
        $evaluation = New-PluginEvaluationReport $out
        return [pscustomobject][ordered]@{
            schema_version = 1; pass = [bool]$evaluation.pass; status = 'exported'; output_path = $out
            skill_count = @($candidateValidation.sources).Count; file_count = $sourceFiles.Count; byte_count = $totalBytes
            verification = [pscustomobject][ordered]@{ static_validated = 'pass'; repo_gates_passed = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }
            evaluation = $evaluation; findings = @(); writes = 1; provider_calls = 0; native_mutations = 0
        }
    }
    catch {
        if (Test-Path -LiteralPath $stage -PathType Container) { [System.IO.Directory]::Delete($stage, $true) }
        return [pscustomobject][ordered]@{ schema_version = 1; pass = $false; status = 'failed'; findings = @((New-PluginContractFinding 'plugin_export_failed' '$.out' $_.Exception.Message)); writes = 0; provider_calls = 0; native_mutations = 0 }
    }
}
