function Invoke-RuleDiagnostics {
    param($Discovery, $Profile = $null)
    $maxBytes = [int](Get-OperationObjectProperty $Profile 'max_bytes')
    if ($maxBytes -le 0) { $maxBytes = 10240 }
    $maxLines = [int](Get-OperationObjectProperty $Profile 'max_lines')
    if ($maxLines -le 0) { $maxLines = 80 }
    $blockingCodes = @((Get-OperationObjectProperty $Profile 'blocking_codes') | ForEach-Object { [string]$_ })
    $wrapperFirstLine = [string](Get-OperationObjectProperty $Profile 'wrapper_first_line')
    $globalMaxBytes = [int](Get-OperationObjectProperty $Profile 'global_max_bytes')
    $globalMaxLines = [int](Get-OperationObjectProperty $Profile 'global_max_lines')
    $projectMaxBytes = [int](Get-OperationObjectProperty $Profile 'project_max_bytes')
    $projectMaxLines = [int](Get-OperationObjectProperty $Profile 'project_max_lines')
    $results = New-Object System.Collections.Generic.List[object]
    $allFindings = New-Object System.Collections.Generic.List[object]
    $hashIndex = @{}
    foreach ($document in @((Get-OperationObjectProperty $Discovery 'documents'))) {
        $path = [string]$document.path
        $documentScope = [string]$document.scope
        $documentMaxBytes = if ($documentScope -eq 'global' -and $globalMaxBytes -gt 0) { $globalMaxBytes } elseif ($documentScope -ne 'global' -and $projectMaxBytes -gt 0) { $projectMaxBytes } else { $maxBytes }
        $documentMaxLines = if ($documentScope -eq 'global' -and $globalMaxLines -gt 0) { $globalMaxLines } elseif ($documentScope -ne 'global' -and $projectMaxLines -gt 0) { $projectMaxLines } else { $maxLines }
        $findings = New-Object System.Collections.Generic.List[object]
        if (-not [System.IO.File]::Exists($path)) {
            $findings.Add((New-RuleFinding -Kind deterministic -Code file_missing -Severity error -Path $path -Message 'Discovered rule file no longer exists.' -Blocking:($blockingCodes -contains 'file_missing'))) | Out-Null
        }
        else {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $text = [System.IO.File]::ReadAllText($path)
            $lines = @($text -split "`r?`n")
            if ($bytes.Length -gt $documentMaxBytes) { $findings.Add((New-RuleFinding -Kind deterministic -Code byte_budget_exceeded -Severity warning -Path $path -Message ('Rule file uses {0} bytes; profile budget is {1}.' -f $bytes.Length, $documentMaxBytes) -Disposition adapt -Blocking:($blockingCodes -contains 'byte_budget_exceeded'))) | Out-Null }
            if ($lines.Count -gt $documentMaxLines) { $findings.Add((New-RuleFinding -Kind deterministic -Code line_budget_exceeded -Severity warning -Path $path -Message ('Rule file uses {0} lines; profile budget is {1}.' -f $lines.Count, $documentMaxLines) -Disposition adapt -Blocking:($blockingCodes -contains 'line_budget_exceeded'))) | Out-Null }
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $findings.Add((New-RuleFinding -Kind deterministic -Code utf8_bom_present -Severity info -Path $path -Message 'UTF-8 BOM is present.' -Disposition defer -Blocking:($blockingCodes -contains 'utf8_bom_present'))) | Out-Null }
            if (-not [string]::IsNullOrWhiteSpace($wrapperFirstLine) -and $lines.Count -gt 0 -and $lines[0] -ne $wrapperFirstLine) { $findings.Add((New-RuleFinding -Kind deterministic -Code wrapper_first_line_mismatch -Severity error -Path $path -Line 1 -Message ('First physical line must be: {0}' -f $wrapperFirstLine) -Disposition adapt -Blocking:($blockingCodes -contains 'wrapper_first_line_mismatch'))) | Out-Null }
            if ([string]$document.scope -eq 'global' -and $text -match '(?i)[A-Z]:\\(?:CODE|src|repo)\\') { $findings.Add((New-RuleFinding -Kind deterministic -Code global_repo_private_path -Severity warning -Path $path -Message 'Global rule contains a repository-private absolute path.' -Disposition adapt -Blocking:($blockingCodes -contains 'global_repo_private_path'))) | Out-Null }
            if ([string]$document.scope -in @('repo', 'subtree') -and $text -match '(?i)\bCODEX_HOME\b.*(?:loads?|加载)') { $findings.Add((New-RuleFinding -Kind deterministic -Code project_host_loading_tutorial -Severity warning -Path $path -Message 'Project rule contains host-loading tutorial text.' -Disposition adapt -Blocking:($blockingCodes -contains 'project_host_loading_tutorial'))) | Out-Null }
            if ($text -match '(?im)^\s*\[deterministic-enforcement\]' -and $text -notmatch '(?i)(\.github/workflows|hooks?|scripts?/|\.rules\b|config\.)') { $findings.Add((New-RuleFinding -Kind deterministic -Code prose_only_enforcement -Severity error -Path $path -Message 'Deterministic enforcement claim has no hook/config/script/CI reference.' -Disposition adapt -Blocking:($blockingCodes -contains 'prose_only_enforcement'))) | Out-Null }
            $hash = [string]$document.content_hash
            if (-not [string]::IsNullOrWhiteSpace($hash)) {
                if (-not $hashIndex.ContainsKey($hash)) { $hashIndex[$hash] = New-Object System.Collections.Generic.List[string] }
                $hashIndex[$hash].Add($path) | Out-Null
            }
        }
        foreach ($finding in $findings) { $allFindings.Add($finding) | Out-Null }
        $copy = $document.PSObject.Copy(); $copy.findings = @($findings.ToArray() | Sort-Object finding_id); $results.Add($copy) | Out-Null
    }
    foreach ($hash in @($hashIndex.Keys)) {
        $paths = @($hashIndex[$hash])
        if ($paths.Count -gt 1) {
            foreach ($path in $paths) { $finding = New-RuleFinding -Kind deterministic -Code exact_duplicate_document -Severity warning -Path $path -Message ('Exact content is duplicated across: {0}' -f ($paths -join ', ')) -Disposition adapt -Blocking:($blockingCodes -contains 'exact_duplicate_document'); $allFindings.Add($finding) | Out-Null; $target = @($results | Where-Object path -eq $path)[0]; $target.findings = @($target.findings) + @($finding) }
        }
    }
    return [pscustomobject][ordered]@{ schema_version = 1; documents = @($results.ToArray()); findings = @($allFindings.ToArray() | Sort-Object finding_id); blocking_count = @($allFindings | Where-Object blocking).Count; commands_executed = 0; writes = 0; provider_calls = 0; native_mutations = 0 }
}
