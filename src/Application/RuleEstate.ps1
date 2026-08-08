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

function Get-RuleEstateInlineField([string]$Line, [string]$Name) {
    $match = [regex]::Match($Line, '(?i)(?:^|[`、,，;；\s])' + [regex]::Escape($Name) + '\s*=\s*(?:`(?<quoted>[^`]+)`|(?<plain>[^`、,，;；\r\n]+))')
    if (-not $match.Success) { return '' }
    $value = if ($match.Groups['quoted'].Success) { [string]$match.Groups['quoted'].Value } else { [string]$match.Groups['plain'].Value }
    return $value.Trim()
}

function Get-RuleEstateNaFindings([string]$ProjectText, [string]$AgentsPath) {
    $findings = New-Object System.Collections.Generic.List[object]
    $lines = @($ProjectText -split "`r?`n")
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        if ($line -notmatch '(?i)`(?:platform_na|gate_na)`') { continue }
        $invalid = New-Object System.Collections.Generic.List[string]
        $values = [ordered]@{}
        foreach ($field in @('reason','alternative_verification','evidence_link','expires_at','recovery_condition')) {
            $values[$field] = Get-RuleEstateInlineField $line $field
            if ([string]::IsNullOrWhiteSpace([string]$values[$field])) { $invalid.Add($field) | Out-Null }
        }
        $expires = [string]$values['expires_at']
        $parsedExpiry = [datetime]::MinValue
        if (-not [string]::IsNullOrWhiteSpace($expires) -and ($expires -notmatch '^\d{4}-\d{2}-\d{2}$' -or -not [datetime]::TryParseExact($expires, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedExpiry))) {
            $invalid.Add('expires_at_iso_date') | Out-Null
        }
        elseif ($parsedExpiry -ne [datetime]::MinValue -and $parsedExpiry.Date -lt [datetime]::UtcNow.Date) {
            $findings.Add([pscustomobject][ordered]@{
                code = 'project_na_expired'; severity = 'error'; path = $AgentsPath; line = $index + 1
                expires_at = $expires; disposition = 'adapt'
                message = 'N/A record has expired and must be revalidated or removed.'
            }) | Out-Null
        }
        $evidence = [string]$values['evidence_link']
        if (-not [string]::IsNullOrWhiteSpace($evidence)) {
            $evidencePath = ($evidence -split '#', 2)[0].Trim()
            if ([string]::IsNullOrWhiteSpace($evidencePath) -or $evidencePath.EndsWith('/') -or $evidencePath.EndsWith('\') -or [System.IO.Path]::GetExtension($evidencePath) -notin @('.md','.json','.csv','.txt','.log')) { $invalid.Add('evidence_link_file') | Out-Null }
            elseif ($invalid.Count -eq 0) {
                try {
                    $repoRoot = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($AgentsPath))
                    $resolvedEvidence = if ([System.IO.Path]::IsPathRooted($evidencePath)) { [System.IO.Path]::GetFullPath($evidencePath) } else { [System.IO.Path]::GetFullPath((Join-Path $repoRoot $evidencePath)) }
                    if (-not (Test-RuleDiscoveryPathWithin $resolvedEvidence $repoRoot) -or -not [System.IO.File]::Exists($resolvedEvidence)) {
                        $findings.Add([pscustomobject][ordered]@{
                            code = 'project_na_evidence_missing'; severity = 'error'; path = $AgentsPath; line = $index + 1
                            evidence_link = $evidence; resolved_path = $resolvedEvidence; disposition = 'adapt'
                            message = 'N/A evidence_link must resolve to an existing file inside the repository.'
                        }) | Out-Null
                    }
                }
                catch {
                    $findings.Add([pscustomobject][ordered]@{
                        code = 'project_na_evidence_missing'; severity = 'error'; path = $AgentsPath; line = $index + 1
                        evidence_link = $evidence; resolved_path = ''; disposition = 'adapt'
                        message = 'N/A evidence_link could not be resolved inside the repository.'
                    }) | Out-Null
                }
            }
            else {
                try {
                    $repoRoot = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($AgentsPath))
                    $resolvedEvidence = if ([System.IO.Path]::IsPathRooted($evidencePath)) { [System.IO.Path]::GetFullPath($evidencePath) } else { [System.IO.Path]::GetFullPath((Join-Path $repoRoot $evidencePath)) }
                    if (-not (Test-RuleDiscoveryPathWithin $resolvedEvidence $repoRoot) -or -not [System.IO.File]::Exists($resolvedEvidence)) {
                        $findings.Add([pscustomobject][ordered]@{ code = 'project_na_evidence_missing'; severity = 'error'; path = $AgentsPath; line = $index + 1; evidence_link = $evidence; resolved_path = $resolvedEvidence; disposition = 'adapt'; message = 'N/A evidence_link must resolve to an existing repository file.' }) | Out-Null
                    }
                }
                catch {
                    $findings.Add([pscustomobject][ordered]@{ code = 'project_na_evidence_missing'; severity = 'error'; path = $AgentsPath; line = $index + 1; evidence_link = $evidence; resolved_path = ''; disposition = 'adapt'; message = 'N/A evidence_link could not be resolved inside the repository.' }) | Out-Null
                }
            }
        }
        if ($invalid.Count -gt 0) {
            $findings.Add([pscustomobject][ordered]@{
                code = 'project_na_invalid'; severity = 'error'; path = $AgentsPath; line = $index + 1
                invalid_fields = @($invalid.ToArray() | Sort-Object -Unique); disposition = 'adapt'
                message = 'N/A record must provide reason, alternative verification, a concrete evidence file, an ISO expiry date, and a recovery condition.'
            }) | Out-Null
        }
    }
    return @($findings.ToArray())
}

function Invoke-RuleEstateGitQuery([string]$RepoRoot, [string[]]$Arguments) {
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true
    $start.ArgumentList.Add('-C')
    $start.ArgumentList.Add($RepoRoot)
    foreach ($argument in @($Arguments)) { $start.ArgumentList.Add([string]$argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    if (-not $process.Start()) { return [pscustomobject]@{ exit_code = 1; output = ''; error = 'git process did not start' } }
    $output = $process.StandardOutput.ReadToEnd().Trim()
    $errorText = $process.StandardError.ReadToEnd().Trim()
    $process.WaitForExit()
    return [pscustomobject]@{ exit_code = $process.ExitCode; output = $output; error = $errorText }
}

function Get-RuleEstateGitProfileFindings([string]$ProjectText, [string]$AgentsPath) {
    $findings = New-Object System.Collections.Generic.List[object]
    $repoRoot = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($AgentsPath))
    $profileLine = @($ProjectText -split "`r?`n" | Where-Object { $_ -match '(?i)Git\s+profile\s*:' } | Select-Object -First 1)
    if ($profileLine.Count -eq 0) {
        $findings.Add([pscustomobject]@{ code = 'project_git_profile_missing'; severity = 'error'; path = $AgentsPath; disposition = 'adapt'; message = 'Project contract must declare Git profile baseline and upstream.' }) | Out-Null
        return @($findings.ToArray())
    }
    $line = [string]$profileLine[0]
    $baseline = Get-RuleEstateInlineField $line 'baseline'
    $upstream = Get-RuleEstateInlineField $line 'upstream'
    if ([string]::IsNullOrWhiteSpace($baseline) -or [string]::IsNullOrWhiteSpace($upstream)) {
        $findings.Add([pscustomobject]@{ code = 'project_git_profile_invalid'; severity = 'error'; path = $AgentsPath; disposition = 'adapt'; message = 'Git profile must provide non-empty baseline and upstream fields.' }) | Out-Null
        return @($findings.ToArray())
    }

    $head = Invoke-RuleEstateGitQuery $repoRoot @('symbolic-ref', '--quiet', '--short', 'HEAD')
    $baselineRef = Invoke-RuleEstateGitQuery $repoRoot @('show-ref', '--verify', '--quiet', ('refs/heads/{0}' -f $baseline))
    if (($head.exit_code -ne 0 -or $head.output -ne $baseline) -and $baselineRef.exit_code -ne 0) {
        $findings.Add([pscustomobject]@{ code = 'project_git_baseline_mismatch'; severity = 'error'; path = $AgentsPath; declared = $baseline; observed_head = $head.output; disposition = 'adapt'; message = 'Declared Git baseline is neither the symbolic HEAD nor an existing local branch.' }) | Out-Null
    }

    $remotesResult = Invoke-RuleEstateGitQuery $repoRoot @('remote')
    $remotes = @($remotesResult.output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($upstream -eq 'none') {
        $hasNoRemoteNa = [regex]::IsMatch($ProjectText, '(?im)^.*`gate_na`.*(?:Git\s+remote|upstream|remote).*?$')
        if ($remotes.Count -ne 0 -or -not $hasNoRemoteNa) {
            $findings.Add([pscustomobject]@{ code = 'project_git_upstream_mismatch'; severity = 'error'; path = $AgentsPath; declared = 'none'; observed_remotes = $remotes; disposition = 'adapt'; message = 'A no-upstream Git profile requires zero configured remotes and a bounded gate_na record.' }) | Out-Null
        }
    }
    else {
        $parts = @($upstream -split '/', 2)
        $remoteExists = $parts.Count -eq 2 -and $remotes -contains $parts[0]
        $remoteRef = if ($parts.Count -eq 2) { Invoke-RuleEstateGitQuery $repoRoot @('show-ref', '--verify', '--quiet', ('refs/remotes/{0}' -f $upstream)) } else { [pscustomobject]@{ exit_code = 1 } }
        $tracking = Invoke-RuleEstateGitQuery $repoRoot @('for-each-ref', '--format=%(upstream:short)', ('refs/heads/{0}' -f $baseline))
        if (-not $remoteExists -or $remoteRef.exit_code -ne 0 -or $tracking.output -ne $upstream) {
            $findings.Add([pscustomobject]@{ code = 'project_git_upstream_mismatch'; severity = 'error'; path = $AgentsPath; declared = $upstream; observed_tracking = $tracking.output; observed_remotes = $remotes; disposition = 'adapt'; message = 'Declared Git upstream must exist as a remote-tracking ref and match the baseline branch tracking configuration.' }) | Out-Null
        }
    }
    return @($findings.ToArray())
}

function Get-RuleEstateGlobalDocument([string]$UserRoot, [ValidateSet('codex', 'claude')][string]$HostName) {
    if ([string]::IsNullOrWhiteSpace($UserRoot)) { return $null }
    $root = Get-RuleEstateNormalizedPath $UserRoot
    $names = if ($HostName -eq 'codex') { @('AGENTS.override.md', 'AGENTS.md') } else { @('CLAUDE.md') }
    foreach ($name in $names) {
        $path = Join-Path $root $name
        if ([System.IO.File]::Exists($path)) {
            $text = [System.IO.File]::ReadAllText($path)
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
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
    foreach ($document in @(
        [pscustomobject]@{ host = 'codex'; value = $codex },
        [pscustomobject]@{ host = 'claude'; value = $claude }
    )) {
        $text = if ($null -eq $document.value) { '' } else { [string]$document.value.text }
        if ([string]::IsNullOrWhiteSpace((Get-RuleEstateMarkdownSection $text '1'))) {
            $findings.Add([pscustomobject][ordered]@{ code = 'global_contract_section_missing'; severity = 'error'; host = [string]$document.host; section = '1'; path = if ($null -eq $document.value) { '' } else { [string]$document.value.path }; disposition = 'adapt'; message = 'Global rule contract section 1 is missing.' }) | Out-Null
        }
    }
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
        if (-not $aligned) { $findings.Add([pscustomobject][ordered]@{ code = 'global_common_section_drift'; severity = 'error'; section = $name; disposition = 'adapt'; message = ('Codex and Claude global common section {0} is absent or different.' -f $name) }) | Out-Null }
        if ($name -eq 'A' -and $codexText -match '(?i)send_message_to_thread|codex_delegation|source_thread_id|non-managed hook|specialized tool path') {
            $tokens = @([regex]::Matches($codexText, '(?i)send_message_to_thread|codex_delegation|source_thread_id|non-managed hook|specialized tool path') | ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique)
            $findings.Add([pscustomobject][ordered]@{ code = 'global_common_platform_leak'; severity = 'error'; section = 'A'; tokens = $tokens; disposition = 'adapt'; message = 'Common section A contains Codex-specific tool or hook implementation details that belong in platform delta B.' }) | Out-Null
        }
    }
    $codexDelta = if ($null -eq $codex) { '' } else { Get-RuleEstateMarkdownSection ([string]$codex.text) 'B' }
    $claudeDelta = if ($null -eq $claude) { '' } else { Get-RuleEstateMarkdownSection ([string]$claude.text) 'B' }
    if ([string]::IsNullOrWhiteSpace($codexDelta)) { $findings.Add([pscustomobject]@{ code = 'codex_platform_delta_missing'; severity = 'error'; section = 'B'; disposition = 'adapt'; message = 'Codex global platform delta section B is missing.' }) | Out-Null }
    if ([string]::IsNullOrWhiteSpace($claudeDelta)) { $findings.Add([pscustomobject]@{ code = 'claude_platform_delta_missing'; severity = 'error'; section = 'B'; disposition = 'adapt'; message = 'Claude global platform delta section B is missing.' }) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($codexDelta) -and $codexDelta -ceq $claudeDelta) { $findings.Add([pscustomobject]@{ code = 'platform_delta_not_distinct'; severity = 'error'; section = 'B'; disposition = 'adapt'; message = 'Codex and Claude platform delta sections are identical; verify that host-specific loading and enforcement facts were not flattened.' }) | Out-Null }

    $budgets = New-Object System.Collections.Generic.List[object]
    foreach ($document in @($codex, $claude)) {
        if ($null -eq $document) { continue }
        $text = [string]$document.text
        $byteCount = [System.Text.Encoding]::UTF8.GetByteCount($text)
        $lineCount = @($text -split "`r?`n").Count
        $withinBudget = $byteCount -le 16384 -and $lineCount -le 130
        $byteHeadroom = 16384 - $byteCount; $lineHeadroom = 130 - $lineCount
        $budgetRatio = [math]::Max(($byteCount / 16384), ($lineCount / 130))
        $budgetState = if (-not $withinBudget) { 'exceeded' } elseif ($budgetRatio -ge 0.95) { 'addition_blocked' } elseif ($budgetRatio -ge 0.85) { 'warning' } else { 'healthy' }
        $lowHeadroom = $budgetState -in @('warning', 'addition_blocked')
        $budgets.Add([pscustomobject][ordered]@{ host = [string]$document.host; path = [string]$document.path; bytes = $byteCount; lines = $lineCount; max_bytes = 16384; max_lines = 130; byte_headroom = $byteHeadroom; line_headroom = $lineHeadroom; ratio = [math]::Round($budgetRatio, 4); state = $budgetState; within_budget = $withinBudget; low_headroom = $lowHeadroom }) | Out-Null
        if (-not $withinBudget) { $findings.Add([pscustomobject]@{ code = 'global_rule_budget_exceeded'; severity = 'error'; path = [string]$document.path; disposition = 'adapt'; message = ('Global rule uses {0} bytes/{1} lines; profile budget is 16384 bytes/130 lines.' -f $byteCount, $lineCount) }) | Out-Null }
        elseif ($lowHeadroom) {
            $stateCode = if ($budgetState -eq 'addition_blocked') { 'global_rule_budget_addition_blocked' } else { 'global_rule_budget_warning' }
            $findings.Add([pscustomobject]@{ code = $stateCode; severity = 'warning'; path = [string]$document.path; disposition = 'adapt'; message = ('Global rule budget state is {0}: {1} bytes and {2} lines remain.' -f $budgetState, $byteHeadroom, $lineHeadroom) }) | Out-Null
            $findings.Add([pscustomobject]@{ code = 'global_rule_budget_low_headroom'; severity = 'warning'; path = [string]$document.path; disposition = 'adapt'; message = ('Global rule has low headroom: {0} bytes and {1} lines remain.' -f $byteHeadroom, $lineHeadroom) }) | Out-Null
        }
    }

    $codexRelease = if ($null -eq $codex) { '' } else { Get-RuleEstateRelease ([string]$codex.text) global }
    $claudeRelease = if ($null -eq $claude) { '' } else { Get-RuleEstateRelease ([string]$claude.text) global }
    $releaseAligned = -not [string]::IsNullOrWhiteSpace($codexRelease) -and $codexRelease -eq $claudeRelease
    if (-not $releaseAligned) { $findings.Add([pscustomobject]@{ code = 'global_release_mismatch'; severity = 'error'; disposition = 'adapt'; expected = $codexRelease; observed = $claudeRelease; message = 'Codex and Claude global rule releases are absent or different.' }) | Out-Null }
    return [pscustomobject][ordered]@{
        codex_path = if ($null -eq $codex) { '' } else { [string]$codex.path }
        claude_path = if ($null -eq $claude) { '' } else { [string]$claude.path }
        common_sections = @($sections.ToArray())
        common_aligned = (@($sections | Where-Object { -not $_.aligned }).Count -eq 0)
        codex_delta_present = -not [string]::IsNullOrWhiteSpace($codexDelta)
        claude_delta_present = -not [string]::IsNullOrWhiteSpace($claudeDelta)
        platform_deltas_distinct = (-not [string]::IsNullOrWhiteSpace($codexDelta) -and -not [string]::IsNullOrWhiteSpace($claudeDelta) -and $codexDelta -cne $claudeDelta)
        releases = [pscustomobject][ordered]@{ codex = $codexRelease; claude = $claudeRelease; aligned = $releaseAligned }
        budgets = @($budgets.ToArray())
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
        $expandedIds = @(Expand-RuleEstateConstraintId ([string]$item.constraint_id))
        $projectActions = @($item.project_actions)
        if ($projectActions.Count -eq 0) { $projectActions = @([string]$item.common_intent) }
        $evidenceItems = @($item.evidence)
        foreach ($id in $expandedIds) {
            if ($id -notmatch '^[RES]\d+$') { continue }
            for ($index = 0; $index -lt $projectActions.Count; $index++) {
                $evidence = if ($index -lt $evidenceItems.Count) { @($evidenceItems[$index]) } else { @($evidenceItems) }
                $actions.Add([pscustomobject][ordered]@{ constraint_id = $id; source_constraint_id = [string]$item.constraint_id; grouped = ($expandedIds.Count -gt 1); action = [string]$projectActions[$index]; evidence = $evidence }) | Out-Null
            }
        }
    }
    return @($actions.ToArray())
}

function Get-RuleEstateExpectedConstraintIds([string]$CodexGlobalText, [string]$ClaudeGlobalText) {
    $ids = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $contractText = (Get-RuleEstateMarkdownSection $CodexGlobalText 'C') + "`n" + (Get-RuleEstateMarkdownSection $ClaudeGlobalText 'C')
    foreach ($match in @([regex]::Matches($contractText, '(?i)\b(?:[RS]\d+(?:\s*-\s*[RS]?\d+)?|E\d+(?:/E\d+)+)\b'))) {
        foreach ($id in @(Expand-RuleEstateConstraintId ([string]$match.Value))) { $ids.Add($id) | Out-Null }
    }
    return @($ids | Sort-Object)
}

function Get-RuleEstateEnforcementChecks([string]$RepoRoot, [object[]]$ActionMatches) {
    $checks = New-Object System.Collections.Generic.List[object]
    foreach ($actionMatch in @($ActionMatches)) {
        foreach ($match in @([regex]::Matches([string]$actionMatch.action, '`(?<value>[^`\r\n]+)`'))) {
            $value = ([string]$match.Groups['value'].Value).Trim()
            if ($value -match '\s' -or $value -notmatch '(?i)(?:^|[\\/])(?:scripts?|hooks?|config|ci)(?:[\\/]|$)|\.(?:ps1|py|json|ya?ml|toml)$') { continue }
            try {
                $resolved = if ([System.IO.Path]::IsPathRooted($value)) { [System.IO.Path]::GetFullPath($value) } else { [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $value)) }
                $contained = Test-RuleDiscoveryPathWithin $resolved $RepoRoot
                $fileExists = $contained -and [System.IO.File]::Exists($resolved)
                $directoryExists = $contained -and [System.IO.Directory]::Exists($resolved)
                $exists = $fileExists -or $directoryExists
                $kind = if ($fileExists) { 'file' } elseif ($directoryExists) { 'directory' } elseif (-not $contained) { 'outside_repository' } else { 'missing' }
            }
            catch { $resolved = ''; $contained = $false; $exists = $false; $fileExists = $false; $directoryExists = $false; $kind = 'invalid' }
            $checks.Add([pscustomobject][ordered]@{ value = $value; resolved_path = $resolved; contained = $contained; exists = $exists; is_file = $fileExists; is_directory = $directoryExists; kind = $kind; enforceable_file = $fileExists }) | Out-Null
        }
    }
    return @($checks.ToArray() | Sort-Object value -Unique)
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
    $repoRoot = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($AgentsPath))
    $constraints = New-Object System.Collections.Generic.List[object]
    $enforcementChecks = New-Object System.Collections.Generic.List[object]
    $groupedMappings = @($actions | Where-Object grouped | Select-Object source_constraint_id,evidence -Unique)
    $expectedIds = @(Get-RuleEstateExpectedConstraintIds $CodexGlobalText $ClaudeGlobalText)
    $expectedSet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $expectedIds) { $expectedSet.Add([string]$id) | Out-Null }
    $unknownMappings = @($actions | Where-Object { -not $expectedSet.Contains([string]$_.constraint_id) } | Group-Object constraint_id | ForEach-Object {
        [pscustomobject][ordered]@{ constraint_id = [string]$_.Name; count = $_.Count; evidence = @($_.Group | ForEach-Object { $_.evidence } | ForEach-Object { $_ }) }
    })
    $duplicateMappings = @($actions | Group-Object constraint_id | Where-Object Count -gt 1 | ForEach-Object {
        [pscustomobject][ordered]@{ constraint_id = [string]$_.Name; count = $_.Count; evidence = @($_.Group | ForEach-Object { $_.evidence } | ForEach-Object { $_ }) }
    })
    foreach ($id in $expectedIds) {
        $actionMatches = @($actions | Where-Object { [string]$_.constraint_id -eq $id })
        $checks = @(Get-RuleEstateEnforcementChecks -RepoRoot $repoRoot -ActionMatches $actionMatches)
        foreach ($check in $checks) { $enforcementChecks.Add($check) | Out-Null }
        $constraintPattern = '(?i)(?<![A-Z0-9])' + [regex]::Escape($id) + '(?![A-Z0-9])'
        $codexHas = [regex]::IsMatch($CodexGlobalText, $constraintPattern)
        $claudeHas = [regex]::IsMatch($ClaudeGlobalText, $constraintPattern)
        $platformDeltas = New-Object System.Collections.Generic.List[string]
        if ($GlobalAlignment.codex_delta_present) { $platformDeltas.Add([string]$GlobalAlignment.codex_path) | Out-Null }
        if ($GlobalAlignment.claude_delta_present) { $platformDeltas.Add([string]$GlobalAlignment.claude_path) | Out-Null }
        $constraints.Add([pscustomobject][ordered]@{
            constraint_id = $id
            common_intent = if ($codexHas -and $claudeHas) { 'declared_by_both_global_rules' } else { '' }
            platform_deltas = @($platformDeltas.ToArray())
            project_actions = @($actionMatches | ForEach-Object { [string]$_.action })
            enforcement_refs = @($checks | ForEach-Object { [string]$_.value })
            evidence = @($actionMatches | ForEach-Object { $_.evidence } | ForEach-Object { $_ })
            recovery_condition = if ($actionMatches.Count -eq 0) { 'Add an evidence-backed repository action or an explicit N/A with recovery condition.' } else { '' }
            need_kind = 'project_guidance'
        }) | Out-Null
    }
    $advisor = Invoke-RuleAdvisor -Constraints @($constraints.ToArray())
    $advisor | Add-Member -NotePropertyName enforcement_checks -NotePropertyValue @($enforcementChecks.ToArray())
    $advisor | Add-Member -NotePropertyName grouped_mappings -NotePropertyValue @($groupedMappings)
    $advisor | Add-Member -NotePropertyName unknown_mappings -NotePropertyValue @($unknownMappings)
    $advisor | Add-Member -NotePropertyName duplicate_mappings -NotePropertyValue @($duplicateMappings)
    $advisor | Add-Member -NotePropertyName coverage_kind -NotePropertyValue 'textual_mapping_coverage'
    return $advisor
}

function New-RuleEstateTargetAudit {
    param($Target, [string]$CodexUserRoot, [string]$ClaudeUserRoot, $GlobalAlignment, [string]$CodexGlobalText, [string]$ClaudeGlobalText)
    $codexDiscovery = Get-RuleDiscovery -RepoRoot $Target.path -CurrentDirectory $Target.path -HostName codex -UserRuleRoot $CodexUserRoot
    $claudeDiscovery = Get-RuleDiscovery -RepoRoot $Target.path -CurrentDirectory $Target.path -HostName claude -UserRuleRoot $ClaudeUserRoot
    $scopeProfile = [pscustomobject]@{ max_bytes = 10240; max_lines = 80; global_max_bytes = 16384; global_max_lines = 130; project_max_bytes = 10240; project_max_lines = 80; blocking_codes = @('file_missing') }
    $codexDiagnostics = Invoke-RuleDiagnostics $codexDiscovery $scopeProfile
    $claudeDiagnostics = Invoke-RuleDiagnostics $claudeDiscovery $scopeProfile
    $coverage = Get-RuleEstateCoverage $Target.agents_path $GlobalAlignment $CodexGlobalText $ClaudeGlobalText
    $projectText = if ([System.IO.File]::Exists([string]$Target.agents_path)) { [System.IO.File]::ReadAllText([string]$Target.agents_path) } else { '' }
    $globalRelease = Get-RuleEstateRelease $CodexGlobalText global
    $projectRelease = Get-RuleEstateRelease $projectText project
    $projectBytes = [System.Text.Encoding]::UTF8.GetByteCount($projectText)
    $projectLines = @($projectText -split "`r?`n").Count
    $projectWithinBudget = $projectBytes -le 10240 -and $projectLines -le 80
    $projectByteHeadroom = 10240 - $projectBytes; $projectLineHeadroom = 80 - $projectLines
    $projectLowHeadroom = $projectWithinBudget -and ($projectBytes -ge [math]::Floor(10240 * 0.85) -or $projectByteHeadroom -lt 1024 -or $projectLineHeadroom -lt 5)
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($finding in @($codexDiagnostics.findings) + @($claudeDiagnostics.findings)) {
        $findingPath = [string](Get-OperationObjectProperty $finding 'path')
        if (-not [string]::IsNullOrWhiteSpace($findingPath) -and (Test-RuleDiscoveryPathWithin $findingPath $Target.path)) { $findings.Add($finding) | Out-Null }
    }
    if (-not [bool]$Target.agents_exists) { $findings.Add([pscustomobject]@{ code = 'project_agents_missing'; severity = 'error'; path = $Target.agents_path; disposition = 'adapt'; message = 'Target repository has no AGENTS.md project contract.' }) | Out-Null }
    if (-not [bool]$Target.claude_exists) { $findings.Add([pscustomobject]@{ code = 'project_claude_wrapper_missing'; severity = 'error'; path = $Target.claude_path; disposition = 'adapt'; message = 'Target repository has no CLAUDE.md adapter or Claude-specific project rule.' }) | Out-Null }
    if ([bool]$Target.agents_exists) {
        foreach ($sectionName in @('1', 'A', 'B', 'C', 'D')) {
            if ([string]::IsNullOrWhiteSpace((Get-RuleEstateMarkdownSection $projectText $sectionName))) { $findings.Add([pscustomobject]@{ code = 'project_contract_section_missing'; severity = 'error'; path = $Target.agents_path; section = $sectionName; disposition = 'adapt'; message = ('Project contract section {0} is missing from the active profile.' -f $sectionName) }) | Out-Null }
        }
    }
    if ([bool]$Target.claude_exists) {
        $claudeBytes = [System.IO.File]::ReadAllBytes([string]$Target.claude_path)
        $claudeText = [System.IO.File]::ReadAllText([string]$Target.claude_path)
        $claudeLines = @($claudeText -split "`r?`n")
        if ($claudeBytes.Length -ge 3 -and $claudeBytes[0] -eq 0xEF -and $claudeBytes[1] -eq 0xBB -and $claudeBytes[2] -eq 0xBF) { $findings.Add([pscustomobject]@{ code = 'project_claude_wrapper_bom'; severity = 'error'; path = $Target.claude_path; disposition = 'adapt'; message = 'Claude project wrapper must begin without a UTF-8 BOM.' }) | Out-Null }
        if ($claudeLines.Count -eq 0 -or $claudeLines[0] -cne '@AGENTS.md') { $findings.Add([pscustomobject]@{ code = 'project_claude_wrapper_first_line_mismatch'; severity = 'error'; path = $Target.claude_path; disposition = 'adapt'; message = 'Claude project wrapper first physical line must be @AGENTS.md for the active shared-contract profile.' }) | Out-Null }
    }
    if (-not [string]::IsNullOrWhiteSpace($globalRelease) -and $projectRelease -ne $globalRelease) { $findings.Add([pscustomobject]@{ code = 'project_global_release_mismatch'; severity = 'warning'; path = $Target.agents_path; disposition = 'adapt'; expected = $globalRelease; observed = $projectRelease; message = ('Project global-rule review is {0}; current global release is {1}.' -f $(if ([string]::IsNullOrWhiteSpace($projectRelease)) { 'undeclared' } else { $projectRelease }), $globalRelease) }) | Out-Null }
    foreach ($item in @($coverage.coverage | Where-Object { $_.coverage -ne 'covered' })) { $findings.Add([pscustomobject]@{ code = 'global_repo_action_gap'; severity = 'warning'; path = $Target.agents_path; constraint_id = $item.constraint_id; disposition = 'adapt'; message = ('Constraint {0} coverage is {1}.' -f $item.constraint_id, $item.coverage) }) | Out-Null }
    foreach ($item in @($coverage.coverage | Where-Object { $_.constraint_id -eq 'S5' -and @($_.enforcement_refs).Count -eq 0 })) { $findings.Add([pscustomobject]@{ code = 'enforcement_reference_required'; severity = 'error'; path = $Target.agents_path; constraint_id = 'S5'; disposition = 'adapt'; message = 'S5 must map to at least one concrete script/config/hook/CI reference.' }) | Out-Null }
    foreach ($check in @($coverage.enforcement_checks | Where-Object { -not $_.exists })) { $findings.Add([pscustomobject]@{ code = 'enforcement_reference_missing'; severity = 'error'; path = $Target.agents_path; reference = $check.value; resolved_path = $check.resolved_path; disposition = 'adapt'; message = ('Mapped deterministic enforcement reference is absent or outside the repository: {0}' -f $check.value) }) | Out-Null }
    foreach ($check in @($coverage.enforcement_checks | Where-Object is_directory)) { $findings.Add([pscustomobject]@{ code = 'enforcement_reference_not_file'; severity = 'error'; path = $Target.agents_path; reference = $check.value; resolved_path = $check.resolved_path; observed_kind = $check.kind; disposition = 'adapt'; message = ('Mapped deterministic enforcement reference must be a concrete file: {0}' -f $check.value) }) | Out-Null }
    foreach ($mapping in @($coverage.grouped_mappings)) { $findings.Add([pscustomobject]@{ code = 'project_mapping_grouped'; severity = 'warning'; path = $Target.agents_path; constraint_id = [string]$mapping.source_constraint_id; disposition = 'adapt'; message = 'Grouped mappings are textual coverage only; map each global constraint to its own repository action.' }) | Out-Null }
    foreach ($mapping in @($coverage.unknown_mappings)) { $findings.Add([pscustomobject]@{ code = 'project_mapping_unknown'; severity = 'warning'; path = $Target.agents_path; constraint_id = [string]$mapping.constraint_id; disposition = 'adapt'; message = 'Project mapping id is not declared by the current global project contract.' }) | Out-Null }
    foreach ($mapping in @($coverage.duplicate_mappings)) { $findings.Add([pscustomobject]@{ code = 'project_mapping_duplicate'; severity = 'warning'; path = $Target.agents_path; constraint_id = [string]$mapping.constraint_id; count = [int]$mapping.count; disposition = 'adapt'; message = 'Map each global constraint exactly once to avoid duplicate or conflicting repository actions.' }) | Out-Null }
    foreach ($finding in @(Get-RuleEstateNaFindings $projectText $Target.agents_path)) { $findings.Add($finding) | Out-Null }
    foreach ($finding in @(Get-RuleEstateGitProfileFindings $projectText $Target.agents_path)) { $findings.Add($finding) | Out-Null }
    if (-not $projectWithinBudget) { $findings.Add([pscustomobject]@{ code = 'project_rule_budget_exceeded'; severity = 'error'; path = $Target.agents_path; disposition = 'adapt'; message = ('Project rule uses {0} bytes/{1} lines; root budget is 10240 bytes/80 lines.' -f $projectBytes, $projectLines) }) | Out-Null }
    elseif ($projectLowHeadroom) { $findings.Add([pscustomobject]@{ code = 'project_rule_budget_low_headroom'; severity = 'warning'; path = $Target.agents_path; disposition = 'adapt'; message = ('Project rule has low headroom: {0} bytes and {1} lines remain.' -f $projectByteHeadroom, $projectLineHeadroom) }) | Out-Null }
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
        budget = [pscustomobject][ordered]@{ bytes = $projectBytes; lines = $projectLines; max_bytes = 10240; max_lines = 80; byte_headroom = $projectByteHeadroom; line_headroom = $projectLineHeadroom; within_budget = $projectWithinBudget; low_headroom = $projectLowHeadroom }
        findings = @($findings.ToArray())
        patch_candidates = @($patchCandidates)
        writes = 0; provider_calls = 0; native_mutations = 0
    }
}

function Invoke-RuleEstateAudit {
    param([string]$WorkspaceRoot, [string[]]$ExcludeNames, [object[]]$RegistryTargets = @(), [string]$CodexUserRoot, [string]$ClaudeUserRoot, [int]$MaxTargets = 64)
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
    $gapCount = @($audits | ForEach-Object { $_.responsibility.coverage } | Where-Object coverage -ne 'covered').Count
    $enforcementCodes = @('enforcement_reference_missing', 'enforcement_reference_required', 'enforcement_reference_not_file')
    $mappingCodes = @('project_mapping_grouped', 'project_mapping_unknown', 'project_mapping_duplicate')
    $mappingIssueCount = @($findings | Where-Object code -in $mappingCodes).Count
    $structuralPass = @($findings | Where-Object severity -eq 'error' | Where-Object code -notin $enforcementCodes).Count -eq 0
    $semanticCoveragePass = $gapCount -eq 0 -and $mappingIssueCount -eq 0
    $enforcementVerified = @($findings | Where-Object code -in $enforcementCodes).Count -eq 0
    return [pscustomobject][ordered]@{
        schema_version = 1; truth_boundary = 'workspace_static_audit'; generated_at = [datetimeoffset]::UtcNow.ToString('o')
        inventory = $inventory; global_alignment = $alignment; targets = @($audits.ToArray())
        summary = [pscustomobject][ordered]@{
            target_count = $inventory.target_count; finding_count = @($findings).Count
            patch_candidate_count = @($audits | ForEach-Object { $_.patch_candidates }).Count
            textual_mapping_covered_count = @($audits | ForEach-Object { $_.responsibility.coverage } | Where-Object coverage -eq 'covered').Count
            semantic_gap_count = $gapCount + $mappingIssueCount
            covered_count = @($audits | ForEach-Object { $_.responsibility.coverage } | Where-Object coverage -eq 'covered').Count
            gap_count = $gapCount
        }
        findings = @($findings); patch_candidates = @($audits | ForEach-Object { $_.patch_candidates })
        command_succeeded = $true; structural_pass = $structuralPass; findings_present = (@($findings).Count -gt 0)
        semantic_coverage_pass = $semanticCoveragePass; enforcement_verified = $enforcementVerified
        reference_basis = @(
            [pscustomobject]@{ authority = 'official'; source = 'https://learn.chatgpt.com/docs/agent-configuration/agents-md'; disposition = 'adopt'; use = 'Codex global/project/nested discovery and precedence' },
            [pscustomobject]@{ authority = 'official'; source = 'https://learn.chatgpt.com/docs/agent-configuration/rules'; disposition = 'adopt'; use = 'Separate prose guidance from deterministic command policy' },
            [pscustomobject]@{ authority = 'repository_evidence'; source = 'docs/product/rule-governance-adoption-matrix.md'; disposition = 'adapt'; use = 'Pinned provenance for the common/platform_delta/project_action responsibility model; referenced runtime remains retired' }
        )
        writes = 0; provider_calls = 0; native_mutations = 0; host_loaded = 'not_run'; live_accepted = 'not_run'
    }
}
