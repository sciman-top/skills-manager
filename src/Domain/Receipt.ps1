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
function Merge-OperationVerificationState {
    param(
        $Current,
        [Parameter(Mandatory = $true)][ValidateSet("static_validated", "repo_gates_passed", "host_loaded", "live_accepted")][string]$Level,
        [Parameter(Mandatory = $true)][ValidateSet("pass", "fail", "not_run", "not_applicable")][string]$State
    )
    $result = New-OperationVerificationState $Current
    $result.$Level = $State
    return $result
}
function New-OperationReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$StartedAt,
        [Parameter(Mandatory = $true)][string]$CompletedAt,
        [object[]]$Actions = @(),
        [object[]]$Backups = @(),
        $Verification = $null,
        [object[]]$Rollback = @()
    )
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
function Test-OperationReceiptContract($Receipt) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Receipt) { return New-OperationValidationResult @((New-OperationFinding "receipt_missing" "error" "$" "Receipt is required.")) }
    if ((Get-OperationObjectProperty $Receipt "schema_version") -ne 1) { $findings.Add((New-OperationFinding "schema_version_invalid" "error" "$.schema_version" "Only schema version 1 is supported.")) | Out-Null }
    foreach ($field in @("operation_id", "status", "started_at", "completed_at")) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Receipt $field))) { $findings.Add((New-OperationFinding "required_field_missing" "error" ("$.{0}" -f $field) "Required field is missing.")) | Out-Null }
    }
    foreach ($field in @("started_at", "completed_at")) {
        if (-not (Test-OperationRfc3339 (Get-OperationObjectProperty $Receipt $field))) { $findings.Add((New-OperationFinding "timestamp_invalid" "error" ("$.{0}" -f $field) "Receipt time must be RFC3339.")) | Out-Null }
    }
    if ([string](Get-OperationObjectProperty $Receipt "status") -notin @("dry_run", "applied", "partial", "failed", "rolled_back")) { $findings.Add((New-OperationFinding "status_invalid" "error" "$.status" "Receipt status is not supported.")) | Out-Null }
    foreach ($field in @("actions", "backups", "rollback")) {
        if (-not (Test-OperationArray (Get-OperationObjectProperty $Receipt $field))) { $findings.Add((New-OperationFinding "array_type_invalid" "error" ("$.{0}" -f $field) "Receipt field must be an array.")) | Out-Null }
    }
    $verification = Get-OperationObjectProperty $Receipt "verification"
    foreach ($level in $script:OperationVerificationLevels) {
        if ([string](Get-OperationObjectProperty $verification $level) -notin $script:OperationVerificationStates) { $findings.Add((New-OperationFinding "verification_state_invalid" "error" ("$.verification.{0}" -f $level) "Verification state is not supported.")) | Out-Null }
    }
    $serialized = $Receipt | ConvertTo-Json -Depth 30 -Compress
    if (Test-OperationSerializedSensitiveValue $serialized) { $findings.Add((New-OperationFinding "sensitive_value_present" "error" "$" "Receipt contains a sensitive value.")) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
