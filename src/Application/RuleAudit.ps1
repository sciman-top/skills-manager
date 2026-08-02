function New-RuleRepoTruthIndex {
    param([Parameter(Mandatory = $true)][string]$RepoRoot, $RepoScan = $null)
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $commands = @()
    if ($null -ne $RepoScan) {
        $detected = Get-OperationObjectProperty $RepoScan 'detected'
        $commands = @((Get-OperationObjectProperty $detected 'build_commands')) + @((Get-OperationObjectProperty $detected 'test_commands'))
    }
    return [pscustomobject][ordered]@{ schema_version = 1; repo_root = $root; commands = @($commands | ForEach-Object { [string]$_ } | Sort-Object -Unique); source = $(if ($null -eq $RepoScan) { 'filesystem_only' } else { 'target_audit_repo_scan' }); scanned_at = Get-OperationObjectProperty $RepoScan 'scanned_at' }
}

function Test-RuleRepoReferences {
    param([Parameter(Mandatory = $true)]$TruthIndex, [object[]]$References = @())
    $root = [string]$TruthIndex.repo_root
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($reference in @($References)) {
        $kind = [string](Get-OperationObjectProperty $reference 'kind'); $value = [string](Get-OperationObjectProperty $reference 'value'); $sourceType = [string](Get-OperationObjectProperty $reference 'source_type')
        $state = 'unknown'; $evidence = @()
        if ($sourceType -eq 'recommendation') { $state = 'not_checked'; $evidence = @([pscustomobject]@{ reason = 'recommendation_not_evidence' }) }
        elseif ($kind -eq 'path') {
            $candidate = if ([System.IO.Path]::IsPathRooted($value)) { [System.IO.Path]::GetFullPath($value) } else { [System.IO.Path]::GetFullPath((Join-Path $root $value)) }
            if (-not (Test-RuleDiscoveryPathWithin $candidate $root)) { $state = 'out_of_root' }
            elseif ([System.IO.File]::Exists($candidate) -or [System.IO.Directory]::Exists($candidate)) { $state = 'verified'; $evidence = @([pscustomobject]@{ type = 'filesystem'; path = $candidate }) }
            else { $state = 'absent'; $evidence = @([pscustomobject]@{ type = 'filesystem'; path = $candidate }) }
        }
        elseif ($kind -eq 'command') {
            if (@($TruthIndex.commands | Where-Object { [string]::Equals($_.Trim(), $value.Trim(), [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { $state = 'verified'; $evidence = @([pscustomobject]@{ type = $TruthIndex.source; command = $value }) }
            else { $state = 'not_observed'; $evidence = @([pscustomobject]@{ type = $TruthIndex.source; command = $value }) }
        }
        $results.Add([pscustomobject][ordered]@{ kind = $kind; value = $value; state = $state; evidence = $evidence; executed = $false }) | Out-Null
    }
    return [pscustomobject][ordered]@{ schema_version = 1; references = @($results.ToArray()); commands_executed = 0; writes = 0; recommendations_used_as_evidence = 0 }
}
