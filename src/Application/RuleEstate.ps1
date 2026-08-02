function Get-RuleEstateNormalizedPath([string]$Path, [string]$BasePath = '') {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ($expanded -eq '~' -or $expanded.StartsWith('~\') -or $expanded.StartsWith('~/')) {
        $home = [Environment]::GetFolderPath('UserProfile')
        $expanded = if ($expanded.Length -eq 1) { $home } else { Join-Path $home $expanded.Substring(2) }
    }
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        if ([string]::IsNullOrWhiteSpace($BasePath)) { throw 'Relative paths require an explicit base path.' }
        $expanded = Join-Path $BasePath $expanded
    }
    return [System.IO.Path]::GetFullPath($expanded).TrimEnd('\', '/')
}

function Get-RuleEstateTargets {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [string[]]$ExcludeNames = @('external', '文档'),
        [object[]]$RegistryTargets = @(),
        [int]$MaxTargets = 64
    )
    $root = Get-RuleEstateNormalizedPath $WorkspaceRoot
    if (-not [System.IO.Directory]::Exists($root)) { throw ('Workspace root does not exist: {0}' -f $root) }
    if ($MaxTargets -lt 1 -or $MaxTargets -gt 512) { throw 'MaxTargets must be between 1 and 512.' }
    $excluded = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($ExcludeNames)) { if (-not [string]::IsNullOrWhiteSpace($name)) { $excluded.Add($name.Trim()) | Out-Null } }
    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($directory in @([System.IO.Directory]::GetDirectories($root) | Sort-Object)) {
        $name = [System.IO.Path]::GetFileName($directory)
        if ($excluded.Contains($name)) { continue }
        $gitMarker = Join-Path $directory '.git'
        if (-not [System.IO.Directory]::Exists($gitMarker) -and -not [System.IO.File]::Exists($gitMarker)) { continue }
        $targets.Add([pscustomobject][ordered]@{
            name = $name
            path = [System.IO.Path]::GetFullPath($directory).TrimEnd('\', '/')
            git_marker = $gitMarker
            agents_path = Join-Path $directory 'AGENTS.md'
            agents_exists = [System.IO.File]::Exists((Join-Path $directory 'AGENTS.md'))
            claude_path = Join-Path $directory 'CLAUDE.md'
            claude_exists = [System.IO.File]::Exists((Join-Path $directory 'CLAUDE.md'))
        }) | Out-Null
    }
    if ($targets.Count -gt $MaxTargets) { throw ('Discovered target count exceeds the bounded limit: {0} > {1}.' -f $targets.Count, $MaxTargets) }

    $discovered = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($target in $targets) { $discovered.Add([string]$target.path) | Out-Null }
    $registered = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($RegistryTargets)) {
        $enabled = if ($null -ne $entry -and $entry.PSObject.Properties.Match('enabled').Count -gt 0) { [bool]$entry.enabled } else { $true }
        if (-not $enabled) { continue }
        $path = Get-RuleEstateNormalizedPath ([string]$entry.path) $root
        if (-not [string]::IsNullOrWhiteSpace($path)) { $registered.Add($path) | Out-Null }
    }
    $registrySupplied = (@($RegistryTargets).Count -gt 0)
    $unregistered = if ($registrySupplied) { @($targets | Where-Object { -not $registered.Contains([string]$_.path) } | ForEach-Object { [string]$_.path }) } else { @() }
    $missing = if ($registrySupplied) { @($registered | Where-Object { -not $discovered.Contains([string]$_) } | Sort-Object) } else { @() }
    return [pscustomobject][ordered]@{
        schema_version = 1
        workspace_root = $root
        exclusion_names = @($excluded | Sort-Object)
        targets = @($targets.ToArray())
        target_count = $targets.Count
        registry = [pscustomobject][ordered]@{
            supplied = $registrySupplied
            registered_count = $registered.Count
            unregistered_paths = @($unregistered)
            missing_paths = @($missing)
            in_sync = ($unregistered.Count -eq 0 -and $missing.Count -eq 0)
        }
        writes = 0
    }
}

function Get-RuleEstateMarkdownSection([string]$Text, [string]$SectionName) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $pattern = '(?ms)^##\s+' + [regex]::Escape($SectionName) + '(?:\.|\b).*?(?=^##\s+|\z)'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return '' }
    return ($match.Value -replace "`r`n", "`n").Trim()
}

function Get-RuleEstateGlobalDocument([string]$UserRoot, [ValidateSet('codex', 'claude')][string]$HostName) {
    if ([string]::IsNullOrWhiteSpace($UserRoot)) { return $null }
    $root = Get-RuleEstateNormalizedPath $UserRoot
    $names = if ($HostName -eq 'codex') { @('AGENTS.override.md', 'AGENTS.md') } else { @('CLAUDE.md') }
    foreach ($name in $names) {
        $path = Join-Path $root $name
        if ([System.IO.File]::Exists($path)) {
            $text = [System.IO.File]::ReadAllText($path)
            return [pscustomobject][ordered]@{ host = $HostName; path = $path; text = $text; hash = Get-RulePatchTextHash $text }
        }
    }
    return $null
}

function Get-RuleEstateGlobalAlignment([string]$CodexUserRoot, [string]$ClaudeUserRoot) {
    $codex = Get-RuleEstateGlobalDocument $CodexUserRoot codex
    $claude = Get-RuleEstateGlobalDocument $ClaudeUserRoot claude
    $sections = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($name in @('A', 'C', 'D')) {
        $codexText = if ($null -eq $codex) { '' } else { Get-RuleEstateMarkdownSection ([string]$codex.text) $name }
        $claudeText = if ($null -eq $claude) { '' } else { Get-RuleEstateMarkdownSection ([string]$claude.text) $name }
        $aligned = -not [string]::IsNullOrWhiteSpace($codexText) -and $codexText -ceq $claudeText
        $sections.Add([pscustomobject][ordered]@{
            section = $name
            aligned = $aligned
            codex_hash = if ([string]::IsNullOrWhiteSpace($codexText)) { '' } else { Get-RulePatchTextHash $codexText }
            claude_hash = if ([string]::IsNullOrWhiteSpace($claudeText)) { '' } else { Get-RulePatchTextHash $claudeText }
        }) | Out-Null
        if (-not $aligned) { $findings.Add([pscustomobject][ordered]@{ code = 'global_common_section_drift'; severity = 'warning'; section = $name; disposition = 'adapt'; message = ('Codex and Claude global common section {0} is absent or different.' -f $name) }) | Out-Null }
    }
    $codexDelta = if ($null -eq $codex) { '' } else { Get-RuleEstateMarkdownSection ([string]$codex.text) 'B' }
    $claudeDelta = if ($null -eq $claude) { '' } else { Get-RuleEstateMarkdownSection ([string]$claude.text) 'B' }
    if ([string]::IsNullOrWhiteSpace($codexDelta)) { $findings.Add([pscustomobject]@{ code = 'codex_platform_delta_missing'; severity = 'warning'; section = 'B'; disposition = 'adapt'; message = 'Codex global platform delta section B is missing.' }) | Out-Null }
    if ([string]::IsNullOrWhiteSpace($claudeDelta)) { $findings.Add([pscustomobject]@{ code = 'claude_platform_delta_missing'; severity = 'warning'; section = 'B'; disposition = 'adapt'; message = 'Claude global platform delta section B is missing.' }) | Out-Null }
    return [pscustomobject][ordered]@{
        codex_path = if ($null -eq $codex) { '' } else { [string]$codex.path }
        claude_path = if ($null -eq $claude) { '' } else { [string]$claude.path }
        common_sections = @($sections.ToArray())
        common_aligned = (@($sections | Where-Object { -not $_.aligned }).Count -eq 0)
        codex_delta_present = -not [string]::IsNullOrWhiteSpace($codexDelta)
        claude_delta_present = -not [string]::IsNullOrWhiteSpace($claudeDelta)
        findings = @($findings.ToArray())
    }
}

function Expand-RuleEstateConstraintId([string]$ConstraintId) {
    $value = $ConstraintId.Trim()
    if ($value -match '^(?<prefix>[A-Za-z]+)(?<start>\d+)\s*-\s*(?:[A-Za-z]+)?(?<end>\d+)$') {
        $result = New-Object System.Collections.Generic.List[string]
        $start = [int]$Matches['start']; $end = [int]$Matches['end']; $prefix = [string]$Matches['prefix']
        if ($end -ge $start -and ($end - $start) -le 32) { for ($i = $start; $i -le $end; $i++) { $result.Add(('{0}{1}' -f $prefix.ToUpperInvariant(), $i)) | Out-Null }; return @($result.ToArray()) }
    }
    $parts = @($value -split '/' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ -match '^[A-Z]+\d+$' })
    if ($parts.Count -gt 0) { return $parts }
    return @($value.ToUpperInvariant())
}

function Get-RuleEstateProjectActions([string]$AgentsPath) {
    if (-not [System.IO.File]::Exists($AgentsPath)) { return @() }
    $document = New-ObservedRuleDocument $AgentsPath codex repo 0 project_action
    $raw = @(Get-RuleAuditResponsibilityConstraints -Documents @($document))
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($item in $raw) {
        foreach ($id in @(Expand-RuleEstateConstraintId ([string]$item.constraint_id))) {
            $actions.Add([pscustomobject][ordered]@{ constraint_id = $id; action = [string]$item.common_intent; evidence = @($item.evidence) }) | Out-Null
        }
    }
    return @($actions.ToArray())
}

function Get-RuleEstateExpectedConstraintIds([string]$CodexGlobalText, [string]$ClaudeGlobalText, [object[]]$ProjectActions) {
    $ids = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($action in @($ProjectActions)) { $ids.Add([string]$action.constraint_id) | Out-Null }
    $contractText = (Get-RuleEstateMarkdownSection $CodexGlobalText 'C') + "`n" + (Get-RuleEstateMarkdownSection $ClaudeGlobalText 'C')
    foreach ($match in @([regex]::Matches($contractText, '(?i)\b(?:R\d+(?:\s*-\s*R?\d+)?|E\d+(?:/E\d+)+)\b'))) {
        foreach ($id in @(Expand-RuleEstateConstraintId ([string]$match.Value))) { $ids.Add($id) | Out-Null }
    }
    return @($ids | Sort-Object)
}

function Get-RuleEstateRelease([string]$Text, [ValidateSet('global', 'project')][string]$Scope) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $patterns = if ($Scope -eq 'global') {
        @('(?im)^\*\*版本\*\*\s*:\s*(?<version>\d+\.\d+)\s*$', '(?i)GlobalUser/(?:AGENTS|CLAUDE)\.md\s+v(?<version>\d+\.\d+)')
    }
    else {
        @('(?im)^\*\*全局规则复核\*\*\s*:\s*(?<version>\d+\.\d+)\s*$', '(?i)GlobalUser/(?:AGENTS|CLAUDE)\.md\s+v(?<version>\d+\.\d+)')
    }
    foreach ($pattern in $patterns) { $match = [regex]::Match($Text, $pattern); if ($match.Success) { return [string]$match.Groups['version'].Value } }
    return ''
}

function Get-RuleEstateCoverage {
    param([string]$AgentsPath, $GlobalAlignment, [string]$CodexGlobalText, [string]$ClaudeGlobalText)
    $actions = @(Get-RuleEstateProjectActions $AgentsPath)
    $constraints = New-Object System.Collections.Generic.List[object]
    foreach ($id in @(Get-RuleEstateExpectedConstraintIds $CodexGlobalText $ClaudeGlobalText $actions)) {
        $matches = @($actions | Where-Object { [string]$_.constraint_id -eq $id })
        $codexHas = $CodexGlobalText -match ('(?i)(?<![A-Z0-9])' + [regex]::Escape($id) + '(?![A-Z0-9])')
        $claudeHas = $ClaudeGlobalText -match ('(?i)(?<![A-Z0-9])' + [regex]::Escape($id) + '(?![A-Z0-9])')
        $platformDeltas = New-Object System.Collections.Generic.List[string]
        if ($GlobalAlignment.codex_delta_present) { $platformDeltas.Add([string]$GlobalAlignment.codex_path) | Out-Null }
        if ($GlobalAlignment.claude_delta_present) { $platformDeltas.Add([string]$GlobalAlignment.claude_path) | Out-Null }
        $constraints.Add([pscustomobject][ordered]@{
            constraint_id = $id
            common_intent = if ($codexHas -and $claudeHas) { 'declared_by_both_global_rules' } else { '' }
            platform_deltas = @($platformDeltas.ToArray())
            project_actions = @($matches | ForEach-Object { [string]$_.action })
            enforcement_refs = @()
            evidence = @($matches | ForEach-Object { $_.evidence } | ForEach-Object { $_ })
            recovery_condition = if ($matches.Count -eq 0) { 'Add an evidence-backed repository action or an explicit N/A with recovery condition.' } else { '' }
            need_kind = 'project_guidance'
        }) | Out-Null
    }
    return Invoke-RuleAdvisor -Constraints @($constraints.ToArray())
}

function New-RuleEstateTargetAudit {
    param($Target, [string]$CodexUserRoot, [string]$ClaudeUserRoot, $GlobalAlignment, [string]$CodexGlobalText, [string]$ClaudeGlobalText)
    $codexDiscovery = Get-RuleDiscovery -RepoRoot $Target.path -CurrentDirectory $Target.path -HostName codex -UserRuleRoot $CodexUserRoot
    $claudeDiscovery = Get-RuleDiscovery -RepoRoot $Target.path -CurrentDirectory $Target.path -HostName claude -UserRuleRoot $ClaudeUserRoot
    $codexDiagnostics = Invoke-RuleDiagnostics $codexDiscovery ([pscustomobject]@{ max_bytes = 10240; max_lines = 80; blocking_codes = @('file_missing') })
    $claudeDiagnostics = Invoke-RuleDiagnostics $claudeDiscovery ([pscustomobject]@{ max_bytes = 16384; max_lines = 130; blocking_codes = @('file_missing') })
    $coverage = Get-RuleEstateCoverage $Target.agents_path $GlobalAlignment $CodexGlobalText $ClaudeGlobalText
    $projectText = if ([System.IO.File]::Exists([string]$Target.agents_path)) { [System.IO.File]::ReadAllText([string]$Target.agents_path) } else { '' }
    $globalRelease = Get-RuleEstateRelease $CodexGlobalText global
    $projectRelease = Get-RuleEstateRelease $projectText project
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @($codexDiagnostics.findings) + @($claudeDiagnostics.findings)) {
        $findingPath = [string](Get-OperationObjectProperty $finding 'path')
        if (-not [string]::IsNullOrWhiteSpace($findingPath) -and (Test-RuleDiscoveryPathWithin $findingPath $Target.path)) { $findings.Add($finding) | Out-Null }
    }
    if (-not [bool]$Target.agents_exists) { $findings.Add([pscustomobject]@{ code = 'project_agents_missing'; severity = 'error'; path = $Target.agents_path; disposition = 'adapt'; message = 'Target repository has no AGENTS.md project contract.' }) | Out-Null }
    if (-not [bool]$Target.claude_exists) { $findings.Add([pscustomobject]@{ code = 'project_claude_wrapper_missing'; severity = 'warning'; path = $Target.claude_path; disposition = 'adapt'; message = 'Target repository has no CLAUDE.md adapter or Claude-specific project rule.' }) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($globalRelease) -and $projectRelease -ne $globalRelease) { $findings.Add([pscustomobject]@{ code = 'project_global_release_mismatch'; severity = 'warning'; path = $Target.agents_path; disposition = 'adapt'; expected = $globalRelease; observed = $projectRelease; message = ('Project global-rule review is {0}; current global release is {1}.' -f $(if ([string]::IsNullOrWhiteSpace($projectRelease)) { 'undeclared' } else { $projectRelease }), $globalRelease) }) | Out-Null }
    foreach ($item in @($coverage.coverage | Where-Object { $_.coverage -ne 'covered' })) { $findings.Add([pscustomobject]@{ code = 'global_repo_action_gap'; severity = 'warning'; path = $Target.agents_path; constraint_id = $item.constraint_id; disposition = 'adapt'; message = ('Constraint {0} coverage is {1}.' -f $item.constraint_id, $item.coverage) }) | Out-Null }
    $patchCandidates = @()
    if ([bool]$Target.agents_exists -and -not [bool]$Target.claude_exists) {
        $desired = "@AGENTS.md`n"
        $patchCandidates = @([pscustomobject][ordered]@{
            finding_code = 'project_claude_wrapper_missing'; operation = 'create'; target_path = $Target.claude_path
            desired_text = $desired; desired_hash = Get-RulePatchTextHash $desired; risk = 'low'; review_required = $true
            verification = @('UTF-8 without BOM', 'first physical line equals @AGENTS.md', 'Claude native load remains separate')
        })
    }
    return [pscustomobject][ordered]@{
        name = $Target.name; path = $Target.path
        codex = [pscustomobject][ordered]@{ documents = @($codexDiscovery.documents); findings = @($codexDiagnostics.findings); load_verification = 'not_run' }
        claude = [pscustomobject][ordered]@{ documents = @($claudeDiscovery.documents); findings = @($claudeDiagnostics.findings); load_verification = 'not_run' }
        responsibility = $coverage
        release = [pscustomobject][ordered]@{ global = $globalRelease; project_review = $projectRelease; aligned = (-not [string]::IsNullOrWhiteSpace($globalRelease) -and $projectRelease -eq $globalRelease) }
        findings = @($findings.ToArray())
        patch_candidates = @($patchCandidates)
        writes = 0; provider_calls = 0; native_mutations = 0
    }
}

function Invoke-RuleEstateAudit {
    param([string]$WorkspaceRoot, [string[]]$ExcludeNames, [object[]]$RegistryTargets, [string]$CodexUserRoot, [string]$ClaudeUserRoot, [int]$MaxTargets = 64)
    $inventory = Get-RuleEstateTargets -WorkspaceRoot $WorkspaceRoot -ExcludeNames $ExcludeNames -RegistryTargets $RegistryTargets -MaxTargets $MaxTargets
    $alignment = Get-RuleEstateGlobalAlignment $CodexUserRoot $ClaudeUserRoot
    $codexGlobal = Get-RuleEstateGlobalDocument $CodexUserRoot codex
    $claudeGlobal = Get-RuleEstateGlobalDocument $ClaudeUserRoot claude
    $codexText = if ($null -eq $codexGlobal) { '' } else { [string]$codexGlobal.text }
    $claudeText = if ($null -eq $claudeGlobal) { '' } else { [string]$claudeGlobal.text }
    $audits = New-Object System.Collections.Generic.List[object]
    foreach ($target in @($inventory.targets)) { $audits.Add((New-RuleEstateTargetAudit $target $CodexUserRoot $ClaudeUserRoot $alignment $codexText $claudeText)) | Out-Null }
    $findings = @($alignment.findings) + @($audits | ForEach-Object { $_.findings })
    if (-not $inventory.registry.in_sync) { $findings += [pscustomobject]@{ code = 'target_registry_drift'; severity = 'warning'; path = $inventory.workspace_root; disposition = 'adapt'; message = 'Configured audit targets differ from the discovered workspace Git roots.' } }
    return [pscustomobject][ordered]@{
        schema_version = 1; truth_boundary = 'workspace_static_audit'; generated_at = [datetimeoffset]::UtcNow.ToString('o')
        inventory = $inventory; global_alignment = $alignment; targets = @($audits.ToArray())
        summary = [pscustomobject][ordered]@{
            target_count = $inventory.target_count; finding_count = @($findings).Count
            patch_candidate_count = @($audits | ForEach-Object { $_.patch_candidates }).Count
            covered_count = @($audits | ForEach-Object { $_.responsibility.coverage } | Where-Object coverage -eq 'covered').Count
            gap_count = @($audits | ForEach-Object { $_.responsibility.coverage } | Where-Object coverage -ne 'covered').Count
        }
        findings = @($findings); patch_candidates = @($audits | ForEach-Object { $_.patch_candidates })
        reference_basis = @(
            [pscustomobject]@{ authority = 'official'; source = 'https://learn.chatgpt.com/docs/agent-configuration/agents-md'; disposition = 'adopt'; use = 'Codex global/project/nested discovery and precedence' },
            [pscustomobject]@{ authority = 'official'; source = 'https://learn.chatgpt.com/docs/agent-configuration/rules'; disposition = 'adopt'; use = 'Separate prose guidance from deterministic command policy' },
            [pscustomobject]@{ authority = 'local_reference'; source = 'D:\CODE-other\governed-ai-coding-runtime'; disposition = 'adapt'; use = 'common/platform_delta/project_action responsibility model; runtime remains retired' }
        )
        writes = 0; provider_calls = 0; native_mutations = 0; host_loaded = 'not_run'; live_accepted = 'not_run'
    }
}
