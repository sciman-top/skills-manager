$strictSkillDispatchRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) {
    . (Join-Path $strictSkillDispatchRepoRoot 'src\Domain\OperationPlan.ps1')
}
if ($null -eq (Get-Command Evaluate-SkillEligibility -ErrorAction SilentlyContinue)) {
    . (Join-Path $strictSkillDispatchRepoRoot 'src\Application\SkillEligibilityPolicy.ps1')
}
if ($null -eq (Get-Command New-NativeInvocationTrace -ErrorAction SilentlyContinue)) {
    . (Join-Path $strictSkillDispatchRepoRoot 'src\Domain\NativeInvocationTrace.ps1')
}
if ($null -eq (Get-Command New-AppServerSkillInjectionRequest -ErrorAction SilentlyContinue)) {
    . (Join-Path $strictSkillDispatchRepoRoot 'src\Infrastructure\AppServerSkillDispatchAdapter.ps1')
}

function Get-StrictSkillDispatchProperty {
    param(
        $Object,
        [string[]]$Names
    )

    foreach ($name in @($Names)) {
        if (Test-OperationObjectProperty $Object $name) {
            return Get-OperationObjectProperty $Object $name
        }
    }
    return $null
}

function Get-StrictSkillDispatchNames {
    param($Value)

    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        $name = ([string]$item).Trim()
        if (-not [string]::IsNullOrWhiteSpace($name) -and $seen.Add($name)) {
            $names.Add($name) | Out-Null
        }
    }
    return [string[]]@($names.ToArray())
}

function Test-StrictSkillDispatchNameSetEqual {
    param(
        [string[]]$Left,
        [string[]]$Right
    )

    $leftNames = Get-StrictSkillDispatchNames $Left
    $rightNames = Get-StrictSkillDispatchNames $Right
    if ($leftNames.Count -ne $rightNames.Count) { return $false }
    $rightSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $rightNames) { $rightSet.Add($name) | Out-Null }
    foreach ($name in $leftNames) { if (-not $rightSet.Contains($name)) { return $false } }
    return $true
}

function Test-StrictSkillDispatchOptIn {
    param($Request)

    $explicit = Get-StrictSkillDispatchProperty $Request @('strict_dispatch', 'strict')
    if ($explicit -is [bool]) { return [bool]$explicit }
    if ($explicit -is [string]) { return [string]::Equals($explicit.Trim(), 'true', [StringComparison]::OrdinalIgnoreCase) }
    $mode = ([string](Get-StrictSkillDispatchProperty $Request @('dispatch_mode', 'mode', 'fallback'))).Trim().ToLowerInvariant()
    return $mode -in @('strict', 'strict_fallback')
}

function New-StrictSkillDispatchTrace {
    param(
        [Parameter(Mandatory = $true)][string]$TraceId,
        [Parameter(Mandatory = $true)]$Request,
        [string[]]$CandidateNames = @(),
        [string[]]$SelectedNames = @(),
        [string[]]$InjectedNames = @(),
        [string]$AbstainedReason = '',
        [Parameter(Mandatory = $true)][string]$CapturedAt
    )

    $events = New-Object System.Collections.Generic.List[object]
    $correlationId = [string](Get-StrictSkillDispatchProperty $Request @('correlation_id', 'request_id', 'thread_id'))
    $index = 0
    foreach ($name in @($CandidateNames)) {
        $events.Add([pscustomobject][ordered]@{
                event_id = ('{0}|listed|{1}|{2}' -f $TraceId, $name, $index)
                kind = 'listed'
                skill_name = $name
                occurred_at = $CapturedAt
                correlation_id = $correlationId
            }) | Out-Null
        $index++
    }
    foreach ($name in @($SelectedNames)) {
        $events.Add([pscustomobject][ordered]@{
                event_id = ('{0}|selected|{1}|{2}' -f $TraceId, $name, $index)
                kind = 'selected'
                skill_name = $name
                occurred_at = $CapturedAt
                correlation_id = $correlationId
            }) | Out-Null
        $index++
    }
    foreach ($name in @($InjectedNames)) {
        $events.Add([pscustomobject][ordered]@{
                event_id = ('{0}|injected|{1}|{2}' -f $TraceId, $name, $index)
                kind = 'injected'
                skill_name = $name
                occurred_at = $CapturedAt
                correlation_id = $correlationId
            }) | Out-Null
        $index++
    }
    if (-not [string]::IsNullOrWhiteSpace($AbstainedReason)) {
        $abstainedNames = if (@($SelectedNames).Count -gt 0) { @($SelectedNames) } elseif (@($CandidateNames).Count -gt 0) { @($CandidateNames) } else { @('strict-dispatch') }
        foreach ($name in $abstainedNames) {
            $events.Add([pscustomobject][ordered]@{
                    event_id = ('{0}|abstained|{1}|{2}' -f $TraceId, $name, $index)
                    kind = 'abstained'
                    skill_name = $name
                    occurred_at = $CapturedAt
                    correlation_id = $correlationId
                    reason = $AbstainedReason
                }) | Out-Null
            $index++
        }
    }
    return New-NativeInvocationTrace -TraceId $TraceId -Surface 'app_server' -Source 'app_server' -Freshness 'fresh' -CapturedAt $CapturedAt -Events $events.ToArray()
}

function New-StrictSkillDispatchResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][bool]$FallbackEntered,
        [bool]$PlatformNa = $false,
        [object[]]$Candidates = @(),
        [string[]]$SelectedNames = @(),
        $Injection = $null,
        [Parameter(Mandatory = $true)]$Trace,
        [object[]]$Findings = @(),
        [string]$ReceiptId = ''
    )

    return [pscustomobject][ordered]@{
        schema_version = 1
        status = $Status
        fallback_entered = $FallbackEntered
        platform_na = $PlatformNa
        candidates = [object[]]@($Candidates)
        candidate_count = @($Candidates).Count
        selected_names = [string[]]@($SelectedNames)
        injection = $Injection
        host_adjudication_receipt_id = if ([string]::IsNullOrWhiteSpace($ReceiptId)) { $null } else { $ReceiptId }
        trace = $Trace
        findings = [object[]]@($Findings)
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function Get-StrictSkillDispatchEligibleEntries {
    param(
        [object[]]$Candidates,
        [object[]]$EligibilityResults
    )

    $eligible = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($Candidates)) {
        if ($null -eq $candidate) { continue }
        $name = ([string](Get-StrictSkillDispatchProperty $candidate @('name', 'skill_name'))).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ((Get-StrictSkillDispatchProperty $candidate @('kind')) -and [string](Get-StrictSkillDispatchProperty $candidate @('kind')) -ne 'skill') { continue }
        if (Test-OperationObjectProperty $candidate 'enabled' -and -not [bool](Get-StrictSkillDispatchProperty $candidate @('enabled'))) { continue }
        $decision = @($EligibilityResults | Where-Object { [string]$_.skill_name -ieq $name } | Select-Object -First 1)
        if ($decision.Count -eq 0) { continue }
        $policyResult = $decision[0]
        $contract = Test-SkillEligibilityResultContract $policyResult
        if (-not [bool]$contract.pass) { continue }
        if ([string]$policyResult.decision -ne 'allow' -or [bool]$policyResult.eligible -ne $true) { continue }
        if ([string]$policyResult.decision_owner -ne 'deterministic_policy') { continue }
        if ([bool]$policyResult.semantic_selection_performed -ne $false -or [bool]$policyResult.profile_filter_applied -ne $false) { continue }
        $eligible.Add($candidate) | Out-Null
    }
    return [object[]]@($eligible.ToArray())
}

function Test-StrictSkillDispatchHostAdjudicationReceipt {
    param(
        $Receipt,
        [string]$RequestId,
        [string[]]$CandidateNames
    )

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Receipt) {
        $findings.Add((New-OperationFinding 'adjudication_receipt_required' 'error' '$.host_adjudication_receipt' 'Host adjudication receipt is required before skill injection.')) | Out-Null
        return [pscustomobject][ordered]@{ pass = $false; selected_names = @(); receipt_id = ''; findings = $findings.ToArray() }
    }
    if ((Get-StrictSkillDispatchProperty $Receipt @('schema_version')) -ne 1) { $findings.Add((New-OperationFinding 'adjudication_schema_invalid' 'error' '$.schema_version' 'Only host adjudication receipt schema version 1 is supported.')) | Out-Null }
    if ([string](Get-StrictSkillDispatchProperty $Receipt @('status')) -ne 'accepted') { $findings.Add((New-OperationFinding 'adjudication_status_invalid' 'error' '$.status' 'Host adjudication must be explicitly accepted.')) | Out-Null }
    if ([string](Get-StrictSkillDispatchProperty $Receipt @('decision_owner')) -ne 'host_ai') { $findings.Add((New-OperationFinding 'adjudication_owner_invalid' 'error' '$.decision_owner' 'Host AI must own semantic adjudication.')) | Out-Null }
    if ([string](Get-StrictSkillDispatchProperty $Receipt @('freshness')) -ne 'fresh') { $findings.Add((New-OperationFinding 'adjudication_stale' 'error' '$.freshness' 'Stale or unknown adjudication cannot authorize injection.')) | Out-Null }
    if (-not (Test-OperationRfc3339 (Get-StrictSkillDispatchProperty $Receipt @('captured_at')))) { $findings.Add((New-OperationFinding 'adjudication_timestamp_invalid' 'error' '$.captured_at' 'Host adjudication captured_at must be RFC3339.')) | Out-Null }
    $receiptRequestId = [string](Get-StrictSkillDispatchProperty $Receipt @('request_id'))
    if (-not [string]::IsNullOrWhiteSpace($RequestId) -and -not [string]::Equals($receiptRequestId, $RequestId, [StringComparison]::Ordinal)) { $findings.Add((New-OperationFinding 'adjudication_request_mismatch' 'error' '$.request_id' 'Host adjudication receipt does not belong to this request.')) | Out-Null }
    $receiptCandidates = Get-StrictSkillDispatchNames (Get-StrictSkillDispatchProperty $Receipt @('candidate_names', 'candidates'))
    $selectedNames = Get-StrictSkillDispatchNames (Get-StrictSkillDispatchProperty $Receipt @('selected_names', 'selected'))
    if (-not (Test-OperationArray (Get-StrictSkillDispatchProperty $Receipt @('candidate_names', 'candidates')))) { $findings.Add((New-OperationFinding 'adjudication_candidates_invalid' 'error' '$.candidate_names' 'Host adjudication candidate_names must be an array.')) | Out-Null }
    if (-not (Test-OperationArray (Get-StrictSkillDispatchProperty $Receipt @('selected_names', 'selected')))) { $findings.Add((New-OperationFinding 'adjudication_selection_invalid' 'error' '$.selected_names' 'Host adjudication selected_names must be an array.')) | Out-Null }
    if (-not (Test-StrictSkillDispatchNameSetEqual $receiptCandidates $CandidateNames)) { $findings.Add((New-OperationFinding 'adjudication_candidate_mismatch' 'error' '$.candidate_names' 'Host adjudication must cover exactly the bounded eligible candidate set.')) | Out-Null }
    $candidateSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($CandidateNames)) { $candidateSet.Add($name) | Out-Null }
    foreach ($name in @($selectedNames)) { if (-not $candidateSet.Contains($name)) { $findings.Add((New-OperationFinding 'adjudication_selection_outside_candidates' 'error' '$.selected_names' 'Host adjudication selected a non-eligible candidate.')) | Out-Null } }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) {
        if ([long](Get-StrictSkillDispatchProperty $Receipt @($field)) -ne 0) { $findings.Add((New-OperationFinding 'adjudication_side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Host adjudication receipt must be zero-side-effect.')) | Out-Null }
    }
    return [pscustomobject][ordered]@{
        pass = @($findings | Where-Object severity -eq 'error').Count -eq 0
        selected_names = [string[]]@($selectedNames)
        receipt_id = [string](Get-StrictSkillDispatchProperty $Receipt @('receipt_id'))
        findings = [object[]]@($findings.ToArray())
    }
}

function Invoke-StrictSkillDispatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Request,
        [object[]]$Candidates = @(),
        [object[]]$EligibilityResults = @(),
        $HostAdjudicationReceipt = $null,
        [Parameter(Mandatory = $true)]$Adapter,
        [ValidateRange(1, 32)][int]$MaxCandidates = 3,
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [string]$TraceId = ''
    )

    $requestId = [string](Get-StrictSkillDispatchProperty $Request @('request_id', 'turn_id', 'thread_id'))
    if ([string]::IsNullOrWhiteSpace($TraceId)) { $TraceId = if ([string]::IsNullOrWhiteSpace($requestId)) { 'strict-dispatch' } else { $requestId + '|strict-dispatch' } }
    $rawCandidates = [object[]]@($Candidates | Where-Object { $null -ne $_ })

    if (-not (Test-StrictSkillDispatchOptIn $Request)) {
        $trace = New-StrictSkillDispatchTrace -TraceId $TraceId -Request $Request -AbstainedReason 'strict_opt_in_required' -CapturedAt $CapturedAt
        return New-StrictSkillDispatchResult -Status 'not_requested' -FallbackEntered $false -Trace $trace
    }

    if ($rawCandidates.Count -gt $MaxCandidates) {
        $trace = New-StrictSkillDispatchTrace -TraceId $TraceId -Request $Request -AbstainedReason 'candidate_set_too_large' -CapturedAt $CapturedAt
        $finding = New-OperationFinding 'candidate_set_too_large' 'error' '$.candidates' ('Strict dispatch candidate set exceeds the bound of {0}.' -f $MaxCandidates)
        return New-StrictSkillDispatchResult -Status 'candidate_set_too_large' -FallbackEntered $true -Trace $trace -Findings @($finding)
    }

    $eligible = Get-StrictSkillDispatchEligibleEntries -Candidates $rawCandidates -EligibilityResults $EligibilityResults
    $eligibleNames = [string[]]@($eligible | ForEach-Object { [string]$_.name })
    if ($eligible.Count -eq 0) {
        $trace = New-StrictSkillDispatchTrace -TraceId $TraceId -Request $Request -AbstainedReason 'no_eligible_candidates' -CapturedAt $CapturedAt
        $finding = New-OperationFinding 'no_eligible_candidates' 'error' '$.candidates' 'No candidate passed the shared deterministic eligibility policy.'
        return New-StrictSkillDispatchResult -Status 'no_eligible_candidates' -FallbackEntered $true -Trace $trace -Findings @($finding)
    }

    $adapterContract = Test-AppServerSkillDispatchAdapterContract $Adapter
    if (-not [bool]$adapterContract.pass -or -not [bool]$Adapter.supports_skill_injection) {
        $trace = New-StrictSkillDispatchTrace -TraceId $TraceId -Request $Request -CandidateNames $eligibleNames -AbstainedReason 'app_server_skill_injection_unsupported' -CapturedAt $CapturedAt
        $finding = New-OperationFinding 'app_server_skill_injection_unsupported' 'warning' '$.adapter' 'App Server skill item injection is unavailable; native-only remains primary.'
        return New-StrictSkillDispatchResult -Status 'platform_na' -FallbackEntered $true -PlatformNa $true -Candidates $eligible -Trace $trace -Findings @($finding)
    }

    $adjudication = Test-StrictSkillDispatchHostAdjudicationReceipt -Receipt $HostAdjudicationReceipt -RequestId $requestId -CandidateNames $eligibleNames
    if (-not [bool]$adjudication.pass) {
        $status = if ($null -eq $HostAdjudicationReceipt) { 'adjudication_required' } else { 'adjudication_invalid' }
        $trace = New-StrictSkillDispatchTrace -TraceId $TraceId -Request $Request -CandidateNames $eligibleNames -AbstainedReason $status -CapturedAt $CapturedAt
        return New-StrictSkillDispatchResult -Status $status -FallbackEntered $true -Candidates $eligible -Trace $trace -Findings @($adjudication.findings)
    }

    $selectedNames = [string[]]@($adjudication.selected_names)
    if ($selectedNames.Count -eq 0) {
        $trace = New-StrictSkillDispatchTrace -TraceId $TraceId -Request $Request -CandidateNames $eligibleNames -AbstainedReason 'host_adjudication_abstained' -CapturedAt $CapturedAt
        $finding = New-OperationFinding 'host_adjudication_abstained' 'warning' '$.selected_names' 'Host adjudication selected no skill for injection.'
        return New-StrictSkillDispatchResult -Status 'abstained' -FallbackEntered $true -Candidates $eligible -Trace $trace -Findings @($finding) -ReceiptId $adjudication.receipt_id
    }

    $selectedSkills = @($eligible | Where-Object { $selectedNames -contains [string]$_.name })
    $injection = New-AppServerSkillInjectionRequest -Adapter $Adapter -Skills $selectedSkills
    if ([string]$injection.status -ne 'ready') {
        $trace = New-StrictSkillDispatchTrace -TraceId $TraceId -Request $Request -CandidateNames $eligibleNames -SelectedNames $selectedNames -AbstainedReason 'app_server_skill_injection_unsupported' -CapturedAt $CapturedAt
        return New-StrictSkillDispatchResult -Status 'platform_na' -FallbackEntered $true -PlatformNa $true -Candidates $eligible -SelectedNames $selectedNames -Injection $null -Trace $trace -Findings @($injection.findings) -ReceiptId $adjudication.receipt_id
    }

    $injectedNames = [string[]]@($injection.items | ForEach-Object { [string]$_.name })
    $trace = New-StrictSkillDispatchTrace -TraceId $TraceId -Request $Request -CandidateNames $eligibleNames -SelectedNames $selectedNames -InjectedNames $injectedNames -CapturedAt $CapturedAt
    return New-StrictSkillDispatchResult -Status 'planned' -FallbackEntered $true -Candidates $eligible -SelectedNames $selectedNames -Injection $injection -Trace $trace -ReceiptId $adjudication.receipt_id
}

function Test-StrictSkillDispatchResultContract {
    param($Result)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Result) { return New-OperationValidationResult @((New-OperationFinding 'dispatch_result_missing' 'error' '$' 'Strict dispatch result is required.')) }
    if ((Get-StrictSkillDispatchProperty $Result @('schema_version')) -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only strict dispatch result schema version 1 is supported.')) | Out-Null }
    if ([string]::IsNullOrWhiteSpace([string](Get-StrictSkillDispatchProperty $Result @('status')))) { $findings.Add((New-OperationFinding 'status_missing' 'error' '$.status' 'Strict dispatch status is required.')) | Out-Null }
    if ((Get-StrictSkillDispatchProperty $Result @('fallback_entered')) -isnot [bool]) { $findings.Add((New-OperationFinding 'fallback_boundary_invalid' 'error' '$.fallback_entered' 'Fallback entry must be explicitly boolean.')) | Out-Null }
    $trace = Get-StrictSkillDispatchProperty $Result @('trace')
    $traceContract = Test-NativeInvocationTraceContract $trace
    foreach ($finding in @($traceContract.findings)) { $findings.Add($finding) | Out-Null }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) {
        if ([long](Get-StrictSkillDispatchProperty $Result @($field)) -ne 0) { $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Strict dispatch must remain zero-side-effect.')) | Out-Null }
    }
    return New-OperationValidationResult $findings.ToArray()
}
