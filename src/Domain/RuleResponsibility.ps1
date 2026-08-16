function New-RuleResponsibility {
    param(
        [Parameter(Mandatory = $true)][string]$ConstraintId,
        [Parameter(Mandatory = $true)][string]$CommonIntent,
        [object[]]$PlatformDeltas = @(), [object[]]$ProjectActions = @(), [object[]]$EnforcementRefs = @(),
        [Parameter(Mandatory = $true)][ValidateSet('covered', 'gap', 'conflict', 'duplicated', 'not_applicable')][string]$Coverage,
        [object[]]$Evidence = @(), [ValidateRange(0.0, 1.0)][double]$Confidence = 1.0, [string]$RecoveryCondition
    )
    if ($Coverage -eq 'not_applicable' -and [string]::IsNullOrWhiteSpace($RecoveryCondition)) { throw 'not_applicable requires a recovery condition.' }
    return [pscustomobject][ordered]@{
        schema_version = 1; constraint_id = $ConstraintId; common_intent = $CommonIntent
        platform_deltas = @($PlatformDeltas); project_actions = @($ProjectActions); enforcement_refs = @($EnforcementRefs)
        coverage = $Coverage; evidence = @($Evidence); confidence = $Confidence
        recovery_condition = if ([string]::IsNullOrWhiteSpace($RecoveryCondition)) { $null } else { $RecoveryCondition }
    }
}
