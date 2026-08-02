function Parse-RuleAuditOptions([object[]]$Tokens) {
    $result = [ordered]@{ repo = $null; current_directory = $null; user_root = $null; host = 'codex'; json = $false; out_path = $null }
    for ($i = 0; $i -lt @($Tokens).Count; $i++) {
        $token = [string]$Tokens[$i]
        switch ($token.ToLowerInvariant()) {
            '--json' { $result.json = $true }
            { $_ -in @('--repo', '--cwd', '--user-root', '--host', '--out') } {
                if ($i + 1 -ge @($Tokens).Count) { throw ('{0} requires a value.' -f $token) }
                $i++; $value = [string]$Tokens[$i]
                switch ($token.ToLowerInvariant()) { '--repo' { $result.repo = $value }; '--cwd' { $result.current_directory = $value }; '--user-root' { $result.user_root = $value }; '--host' { $result.host = $value }; '--out' { $result.out_path = $value } }
            }
            default { throw ('Unknown rule-audit option: {0}' -f $token) }
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$result.repo)) { throw '--repo is required.' }
    if ([string]$result.host -notin @('codex', 'claude')) { throw '--host supports codex or claude.' }
    if ([string]::IsNullOrWhiteSpace([string]$result.current_directory)) { $result.current_directory = $result.repo }
    return [pscustomobject]$result
}

function Invoke-RuleAuditCommand([object[]]$Tokens = @()) {
    $options = Parse-RuleAuditOptions $Tokens
    $discovery = Get-RuleDiscovery -RepoRoot $options.repo -CurrentDirectory $options.current_directory -HostName $options.host -UserRuleRoot $options.user_root
    $profile = [pscustomobject]@{ max_bytes = $(if ($options.host -eq 'codex') { 10240 } else { 16384 }); max_lines = $(if ($options.host -eq 'codex') { 80 } else { 130 }); blocking_codes = @('file_missing') }
    $diagnostics = Invoke-RuleDiagnostics $discovery $profile
    $constraints = @(Get-RuleAuditResponsibilityConstraints -Documents $diagnostics.documents)
    $advisor = Invoke-RuleAdvisor -Documents $diagnostics.documents -Constraints $constraints
    $repoScan = New-AuditRepoScan 'rule-audit' ([System.IO.Path]::GetFullPath($options.repo)) $options.repo
    $truth = New-RuleRepoTruthIndex -RepoRoot $options.repo -RepoScan $repoScan
    $referenceChecks = Test-RuleRepoReferences -TruthIndex $truth -References @(Get-RuleAuditReferences -Documents $diagnostics.documents)
    $blockingCount = [int]$diagnostics.blocking_count
    $reportRequested = -not [string]::IsNullOrWhiteSpace([string]$options.out_path)
    $envelope = [pscustomobject][ordered]@{
        schema_version = 1; command = 'rule-audit'; pass = ($blockingCount -eq 0); exit_code = $(if ($blockingCount -gt 0) { 2 } else { 0 })
        truth_boundary = 'repo_static_audit'; discovery = $discovery; diagnostics = $diagnostics; advisor = $advisor
        repo_truth = $truth; repo_reference_checks = $referenceChecks; provider_calls = 0; native_mutations = 0; profile_changed = $false; writes = $(if ($reportRequested) { 1 } else { 0 })
    }
    $json = $envelope | ConvertTo-Json -Depth 40 -Compress
    if (-not [string]::IsNullOrWhiteSpace([string]$options.out_path)) {
        $outPath = [System.IO.Path]::GetFullPath([string]$options.out_path)
        if (@($discovery.documents | Where-Object { [string]::Equals([System.IO.Path]::GetFullPath([string]$_.path), $outPath, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { throw '--out cannot overwrite a discovered rule file.' }
        Write-Utf8FileAtomic -Path $outPath -Content $json
    }
    return [pscustomobject]@{ exit_code = [int]$envelope.exit_code; output = $(if ($options.json) { $json } else { 'Rule audit: documents={0}, deterministic={1}, semantic={2}, blockers={3}' -f @($discovery.documents).Count, @($diagnostics.findings).Count, @($advisor.findings).Count, $blockingCount }); json = [bool]$options.json; envelope = $envelope }
}
