function Parse-RuleEstateAuditOptions([object[]]$Tokens) {
    $userHome = [Environment]::GetFolderPath('UserProfile')
    $result = [ordered]@{
        workspace_root = $null; exclude_names = @('external', '文档'); registry_path = $null
        codex_user_root = (Join-Path $userHome '.codex'); claude_user_root = (Join-Path $userHome '.claude')
        max_targets = 64; out_path = $null; json = $false
    }
    for ($i = 0; $i -lt @($Tokens).Count; $i++) {
        $token = [string]$Tokens[$i]
        if ($token -eq '--json') { $result.json = $true; continue }
        if ($token -notin @('--workspace-root', '--exclude', '--registry', '--codex-user-root', '--claude-user-root', '--max-targets', '--out')) { throw ('Unknown rule-estate-audit option: {0}' -f $token) }
        if ($i + 1 -ge @($Tokens).Count) { throw ('{0} requires a value.' -f $token) }
        $i++; $value = [string]$Tokens[$i]
        switch ($token) {
            '--workspace-root' { $result.workspace_root = $value }
            '--exclude' { $result.exclude_names += $value }
            '--registry' { $result.registry_path = $value }
            '--codex-user-root' { $result.codex_user_root = $value }
            '--claude-user-root' { $result.claude_user_root = $value }
            '--max-targets' { $result.max_targets = [int]$value }
            '--out' { $result.out_path = $value }
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$result.workspace_root)) { throw '--workspace-root is required.' }
    return [pscustomobject]$result
}

function Invoke-RuleEstateAuditCommand([object[]]$Tokens = @()) {
    $options = Parse-RuleEstateAuditOptions $Tokens
    $registryTargets = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$options.registry_path)) {
        $registryPath = [System.IO.Path]::GetFullPath([string]$options.registry_path)
        if (-not [System.IO.File]::Exists($registryPath)) { throw ('Registry file does not exist: {0}' -f $registryPath) }
        $registry = [System.IO.File]::ReadAllText($registryPath) | ConvertFrom-Json
        $registryTargets = @($registry.targets)
    }
    $report = Invoke-RuleEstateAudit -WorkspaceRoot $options.workspace_root -ExcludeNames $options.exclude_names -RegistryTargets $registryTargets -CodexUserRoot $options.codex_user_root -ClaudeUserRoot $options.claude_user_root -MaxTargets $options.max_targets
    $reportRequested = -not [string]::IsNullOrWhiteSpace([string]$options.out_path)
    $envelope = [pscustomobject][ordered]@{
        schema_version = 1; command = 'rule-estate-audit'; pass = $true; exit_code = 0; truth_boundary = $report.truth_boundary
        report = $report; writes = $(if ($reportRequested) { 1 } else { 0 }); provider_calls = 0; native_mutations = 0
    }
    $json = $envelope | ConvertTo-Json -Depth 60 -Compress
    if ($reportRequested) {
        $outPath = [System.IO.Path]::GetFullPath([string]$options.out_path)
        foreach ($target in @($report.inventory.targets)) {
            if ($outPath.Equals([System.IO.Path]::GetFullPath([string]$target.agents_path), [System.StringComparison]::OrdinalIgnoreCase) -or $outPath.Equals([System.IO.Path]::GetFullPath([string]$target.claude_path), [System.StringComparison]::OrdinalIgnoreCase)) { throw '--out cannot overwrite a target rule file.' }
        }
        Write-Utf8FileAtomic -Path $outPath -Content $json
    }
    $output = if ($options.json) { $json } else { 'Rule estate audit: targets={0}, findings={1}, gaps={2}, patch_candidates={3}' -f $report.summary.target_count, $report.summary.finding_count, $report.summary.gap_count, $report.summary.patch_candidate_count }
    return [pscustomobject]@{ exit_code = 0; output = $output; json = [bool]$options.json; envelope = $envelope }
}
