$skillEligibilityPolicyRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) { . (Join-Path $skillEligibilityPolicyRepoRoot 'src\Domain\OperationPlan.ps1') }
if ($null -eq (Get-Command Get-SkillCatalogStringArray -ErrorAction SilentlyContinue)) { . (Join-Path $skillEligibilityPolicyRepoRoot 'src\Domain\SkillCatalog.ps1') }

function Add-SkillEligibilityFinding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$Code,
        [string]$Severity,
        [string]$Path,
        [string]$Message
    )
    $Findings.Add((New-OperationFinding $Code $Severity $Path $Message)) | Out-Null
}

function Test-SkillEligibilityContained {
    param([string]$Path, [string[]]$AllowedRoots)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (@($AllowedRoots).Count -eq 0) { return $true }
    foreach ($root in @($AllowedRoots)) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-OperationPathWithinRoot $Path $root)) { return $true }
    }
    return $false
}

function Evaluate-SkillEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Skill,
        [string]$Surface = '',
        [string[]]$AllowedRoots = @(),
        [bool]$ApprovalGranted = $false,
        [string[]]$AvailableDependencies = @()
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $name = ([string](Get-OperationObjectProperty $Skill 'name')).Trim()
    $path = [string](Get-OperationObjectProperty $Skill 'path')
    if ([string]::IsNullOrWhiteSpace($name)) { Add-SkillEligibilityFinding $findings 'skill_name_missing' 'error' '$.name' 'Skill name is required.' }
    if ([string]::IsNullOrWhiteSpace($path)) { Add-SkillEligibilityFinding $findings 'path_missing' 'error' '$.path' 'Skill path is required for deterministic containment.' }
    elseif (-not (Test-SkillEligibilityContained $path $AllowedRoots)) { Add-SkillEligibilityFinding $findings 'path_outside_allowed_root' 'error' '$.path' 'Skill path is outside the allowed roots.' }

    $freshness = ([string](Get-OperationObjectProperty $Skill 'freshness')).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($freshness)) { $freshness = 'unknown' }
    if ($freshness -ne 'fresh') { Add-SkillEligibilityFinding $findings 'freshness_not_current' 'error' '$.freshness' 'Stale or unknown skill metadata cannot be eligible.' }

    $availability = ([string](Get-OperationObjectProperty $Skill 'availability')).Trim().ToLowerInvariant()
    if ($availability -eq 'cold_load' -or $availability -eq 'needs_activation') {
        Add-SkillEligibilityFinding $findings 'availability_activation_required' 'warning' '$.availability' 'Skill requires explicit host activation before use.'
    }
    elseif ($availability -ne 'available') {
        Add-SkillEligibilityFinding $findings 'availability_not_eligible' 'error' '$.availability' 'Skill availability is not eligible for the requested surface.'
    }

    $surfaces = @(Get-SkillCatalogStringArray (Get-OperationObjectProperty $Skill 'surfaces'))
    if (-not [string]::IsNullOrWhiteSpace($Surface) -and $surfaces.Count -gt 0 -and $surfaces -notcontains $Surface) {
        Add-SkillEligibilityFinding $findings 'surface_incompatible' 'error' '$.surfaces' 'Skill is not compatible with the requested surface.'
    }

    $available = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dependency in @($AvailableDependencies)) { if (-not [string]::IsNullOrWhiteSpace([string]$dependency)) { $available.Add(([string]$dependency).Trim()) | Out-Null } }
    foreach ($dependency in @(Get-SkillCatalogStringArray (Get-OperationObjectProperty $Skill 'dependencies'))) {
        if (-not $available.Contains($dependency)) { Add-SkillEligibilityFinding $findings 'dependency_missing' 'error' '$.dependencies' ('Required dependency is unavailable: {0}' -f $dependency) }
    }

    $sideEffect = ([string](Get-OperationObjectProperty $Skill 'side_effect')).Trim().ToLowerInvariant()
    if ($sideEffect -notin @('read_only', 'external_read', 'controlled_write')) {
        Add-SkillEligibilityFinding $findings 'side_effect_unknown' 'error' '$.side_effect' 'Unknown side effect must fail closed.'
    }
    $requiresApproval = [bool](Get-OperationObjectProperty $Skill 'requires_approval') -or $sideEffect -eq 'controlled_write'
    if ($requiresApproval -and -not $ApprovalGranted) { Add-SkillEligibilityFinding $findings 'approval_required' 'warning' '$.requires_approval' 'Explicit approval is required before activation.' }

    $hasDeny = @($findings | Where-Object { [string]$_.severity -eq 'error' }).Count -gt 0
    $needsActivation = @($findings | Where-Object { $_.code -in @('availability_activation_required', 'approval_required') }).Count -gt 0
    $decision = if ($hasDeny) { 'deny' } elseif ($needsActivation) { 'needs_activation' } else { 'allow' }
    return [pscustomobject][ordered]@{
        schema_version = 1
        skill_name = $name
        decision = $decision
        eligible = ($decision -eq 'allow')
        activation_required = ($decision -eq 'needs_activation')
        findings = [object[]]@($findings.ToArray())
        decision_owner = 'deterministic_policy'
        semantic_selection_performed = $false
        profile_filter_applied = $false
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function Test-SkillEligibilityResultContract {
    param($Result)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Result) { return New-OperationValidationResult @((New-OperationFinding 'eligibility_result_missing' 'error' '$' 'Eligibility result is required.')) }
    if ((Get-OperationObjectProperty $Result 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only eligibility schema version 1 is supported.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Result 'decision') -notin @('allow', 'deny', 'needs_activation')) { $findings.Add((New-OperationFinding 'decision_invalid' 'error' '$.decision' 'Eligibility decision is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Result 'decision_owner') -ne 'deterministic_policy') { $findings.Add((New-OperationFinding 'decision_owner_invalid' 'error' '$.decision_owner' 'Eligibility decision owner is invalid.')) | Out-Null }
    if ((Get-OperationObjectProperty $Result 'semantic_selection_performed') -ne $false -or (Get-OperationObjectProperty $Result 'profile_filter_applied') -ne $false) { $findings.Add((New-OperationFinding 'semantic_boundary_breached' 'error' '$' 'Eligibility policy cannot perform semantic selection or profile filtering.')) | Out-Null }
    $expectedEligible = ([string](Get-OperationObjectProperty $Result 'decision') -eq 'allow')
    if ((Get-OperationObjectProperty $Result 'eligible') -ne $expectedEligible) { $findings.Add((New-OperationFinding 'eligible_flag_invalid' 'error' '$.eligible' 'Eligible flag must match the deterministic decision.')) | Out-Null }
    if (-not (Test-OperationArray (Get-OperationObjectProperty $Result 'findings'))) { $findings.Add((New-OperationFinding 'findings_type_invalid' 'error' '$.findings' 'Eligibility findings must be an array.')) | Out-Null }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) {
        if ([long](Get-OperationObjectProperty $Result $field) -ne 0) { $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Eligibility policy must be zero-side-effect.')) | Out-Null }
    }
    return New-OperationValidationResult $findings.ToArray()
}
