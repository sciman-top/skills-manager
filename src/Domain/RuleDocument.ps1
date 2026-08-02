function New-RuleFinding {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('deterministic', 'semantic')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][ValidateSet('info', 'warning', 'error')][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message,
        [Nullable[int]]$Line,
        [object[]]$Evidence = @(),
        [ValidateRange(0.0, 1.0)][double]$Confidence = 1.0,
        [ValidateSet('adopt', 'adapt', 'reject', 'defer')][string]$Disposition = 'defer',
        [switch]$Blocking
    )
    $identity = '{0}|{1}|{2}|{3}|{4}' -f $Kind, $Code.ToLowerInvariant(), $Path.ToLowerInvariant(), $Line, $Message
    return [pscustomobject][ordered]@{
        finding_id = 'finding-{0}' -f (Get-CapabilityContractHash $identity).Substring(0, 16)
        kind = $Kind; code = $Code; severity = $Severity; path = $Path
        line = if ($null -eq $Line) { $null } else { [int]$Line }
        message = $Message; evidence = @($Evidence); confidence = $Confidence
        disposition = $Disposition; blocking = [bool]$Blocking
    }
}

function New-RuleDocument {
    param(
        [Parameter(Mandatory = $true)][Alias('Host')][string]$HostName,
        [Parameter(Mandatory = $true)][ValidateSet('global', 'repo', 'subtree', 'override')][string]$Scope,
        [Parameter(Mandatory = $true)][ValidateSet('common', 'platform_delta', 'project_action', 'deterministic_enforcement', 'task_local')][string]$Responsibility,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Owner = 'unknown', [string]$ContentHash, [int]$ByteSize = 0, [Nullable[int]]$Precedence,
        [ValidateSet('observed', 'inferred', 'unknown')][string]$DiscoveryState = 'unknown',
        [Parameter(Mandatory = $true)][string]$SourceOfTruth,
        [object[]]$Findings = @(), [object[]]$Evidence = @(),
        [ValidateSet('not_verified', 'static_validated', 'repo_verified', 'host_loaded', 'live_accepted')][string]$VerificationState = 'not_verified'
    )
    $identity = '{0}|{1}|{2}' -f $HostName.ToLowerInvariant(), $Scope, $Path.ToLowerInvariant()
    return [pscustomobject][ordered]@{
        schema_version = 1; id = 'rule-{0}' -f (Get-CapabilityContractHash $identity).Substring(0, 16)
        host = $HostName.ToLowerInvariant(); scope = $Scope; responsibility = $Responsibility; path = $Path; owner = $Owner
        content_hash = if ([string]::IsNullOrWhiteSpace($ContentHash)) { $null } else { $ContentHash.ToLowerInvariant() }
        byte_size = $ByteSize; precedence = if ($null -eq $Precedence) { $null } else { [int]$Precedence }
        discovery_state = $DiscoveryState; source_of_truth = $SourceOfTruth
        findings = @($Findings | Sort-Object finding_id); evidence = @($Evidence | Sort-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
        verification_state = $VerificationState
    }
}

function Test-RuleDocumentContract($Document) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Document) { return New-OperationValidationResult @((New-OperationFinding 'rule_document_missing' 'error' '$' 'Rule document is required.')) }
    if ((Get-OperationObjectProperty $Document 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('id', 'host', 'scope', 'responsibility', 'path', 'owner', 'discovery_state', 'source_of_truth', 'verification_state')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Document $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required field is missing.')) | Out-Null } }
    if ([string](Get-OperationObjectProperty $Document 'scope') -notin @('global', 'repo', 'subtree', 'override')) { $findings.Add((New-OperationFinding 'scope_invalid' 'error' '$.scope' 'Scope is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Document 'responsibility') -notin @('common', 'platform_delta', 'project_action', 'deterministic_enforcement', 'task_local')) { $findings.Add((New-OperationFinding 'responsibility_invalid' 'error' '$.responsibility' 'Responsibility is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Document 'discovery_state') -notin @('observed', 'inferred', 'unknown')) { $findings.Add((New-OperationFinding 'discovery_state_invalid' 'error' '$.discovery_state' 'Discovery state is invalid.')) | Out-Null }
    $hash = Get-OperationObjectProperty $Document 'content_hash'; if ($null -ne $hash -and [string]$hash -notmatch '^[a-fA-F0-9]{64}$') { $findings.Add((New-OperationFinding 'content_hash_invalid' 'error' '$.content_hash' 'Content hash must be SHA-256 or null.')) | Out-Null }
    $documentFindings = Get-OperationObjectProperty $Document 'findings'
    if (-not (Test-OperationArray $documentFindings)) { $findings.Add((New-OperationFinding 'array_type_invalid' 'error' '$.findings' 'Findings must be an array.')) | Out-Null; $documentFindings = @() }
    foreach ($item in @($documentFindings)) {
        if ([string](Get-OperationObjectProperty $item 'kind') -notin @('deterministic', 'semantic')) { $findings.Add((New-OperationFinding 'finding_kind_invalid' 'error' '$.findings' 'Finding kind is invalid.')) | Out-Null }
        if ([bool](Get-OperationObjectProperty $item 'blocking') -and [string](Get-OperationObjectProperty $item 'kind') -ne 'deterministic') { $findings.Add((New-OperationFinding 'semantic_finding_cannot_block' 'error' '$.findings' 'Semantic findings are recommendation-only.')) | Out-Null }
    }
    return New-OperationValidationResult $findings.ToArray()
}
