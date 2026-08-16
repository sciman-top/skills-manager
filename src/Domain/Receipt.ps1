$script:OperationVerificationLevels = @("static_validated", "repo_gates_passed", "host_loaded", "live_accepted")
$script:OperationVerificationStates = @("pass", "fail", "not_run", "not_applicable")
function New-OperationVerificationState($InputState = $null) {
    $result = [ordered]@{}
    foreach ($level in $script:OperationVerificationLevels) {
        $value = [string](Get-OperationObjectProperty $InputState $level)
        if ($value -notin $script:OperationVerificationStates) { $value = "not_run" }
        $result[$level] = $value
    }
    return [pscustomobject]$result
}
function New-OperationReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][ValidateSet("dry_run", "applied", "partial", "failed", "rolled_back")][string]$Status,
        [Parameter(Mandatory = $true)][string]$StartedAt,
        [Parameter(Mandatory = $true)][string]$CompletedAt,
        [object[]]$Actions = @(),
        [object[]]$Backups = @(),
        $Verification = $null,
        [object[]]$Rollback = @()
    )
    if (-not (Test-OperationRfc3339 $StartedAt) -or -not (Test-OperationRfc3339 $CompletedAt)) { throw 'Receipt timestamps must use RFC3339.' }
    return [pscustomobject][ordered]@{
        schema_version = 1
        operation_id = $OperationId
        status = $Status
        started_at = $StartedAt
        completed_at = $CompletedAt
        actions = @(Protect-OperationSensitiveValue @($Actions) "actions")
        backups = @(Protect-OperationSensitiveValue @($Backups) "backups")
        verification = New-OperationVerificationState $Verification
        rollback = @(Protect-OperationSensitiveValue @($Rollback) "rollback")
    }
}
