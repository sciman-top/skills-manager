function New-RuleResponsibility {
    param(
        [Parameter(Mandatory = $true)][string]$ConstraintId,
        [Parameter(Mandatory = $true)][string]$CommonIntent,
        [object[]]$PlatformDeltas = @(), [object[]]$ProjectActions = @(), [object[]]$EnforcementRefs = @(),
        [Parameter(Mandatory = $true)][ValidateSet('covered', 'gap', 'conflict', 'duplicated', 'not_applicable')][string]$Coverage,
        [object[]]$Evidence = @(), [ValidateRange(0.0, 1.0)][double]$Confidence = 1.0, [string]$RecoveryCondition
    )
    return [pscustomobject][ordered]@{
        schema_version = 1; constraint_id = $ConstraintId; common_intent = $CommonIntent
        platform_deltas = @($PlatformDeltas); project_actions = @($ProjectActions); enforcement_refs = @($EnforcementRefs)
        coverage = $Coverage; evidence = @($Evidence); confidence = $Confidence
        recovery_condition = if ([string]::IsNullOrWhiteSpace($RecoveryCondition)) { $null } else { $RecoveryCondition }
    }
}

function Test-RuleResponsibilityContract($Responsibility) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Responsibility) { return New-OperationValidationResult @((New-OperationFinding 'rule_responsibility_missing' 'error' '$' 'Rule responsibility is required.')) }
    if ((Get-OperationObjectProperty $Responsibility 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('constraint_id', 'common_intent', 'coverage')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Responsibility $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required field is missing.')) | Out-Null } }
    foreach ($field in @('platform_deltas', 'project_actions', 'enforcement_refs', 'evidence')) { if (-not (Test-OperationArray (Get-OperationObjectProperty $Responsibility $field))) { $findings.Add((New-OperationFinding 'array_type_invalid' 'error' ('$.{0}' -f $field) 'Field must be an array.')) | Out-Null } }
    $coverage = [string](Get-OperationObjectProperty $Responsibility 'coverage')
    if ($coverage -notin @('covered', 'gap', 'conflict', 'duplicated', 'not_applicable')) { $findings.Add((New-OperationFinding 'coverage_invalid' 'error' '$.coverage' 'Coverage is invalid.')) | Out-Null }
    if ($coverage -eq 'not_applicable' -and [string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Responsibility 'recovery_condition'))) { $findings.Add((New-OperationFinding 'recovery_condition_required' 'error' '$.recovery_condition' 'not_applicable requires a recovery condition.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
