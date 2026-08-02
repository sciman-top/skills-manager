function Get-CapabilityContractHash([string]$Value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function New-CapabilityDescriptor {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('skill', 'plugin', 'mcp')][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('runtime', 'reference', 'official', 'host_installed', 'candidate')][string]$TruthOrigin,
        [Parameter(Mandatory = $true)]$Source,
        [ValidateSet('active', 'deprecated', 'historical', 'unknown')][string]$Lifecycle = 'unknown',
        [string[]]$HostCompatibility = @(), [object[]]$Components = @(), [object[]]$Evidence = @(),
        [ValidateSet('not_verified', 'static_validated', 'repo_verified', 'host_loaded', 'live_accepted')][string]$VerificationState = 'not_verified'
    )
    $sourceType = [string](Get-OperationObjectProperty $Source 'type')
    $sourceLocation = [string](Get-OperationObjectProperty $Source 'path_or_url')
    $revision = [string](Get-OperationObjectProperty $Source 'revision')
    $identity = '{0}|{1}|{2}|{3}|{4}|{5}' -f $Kind.ToLowerInvariant(), $Name.Trim().ToLowerInvariant(), $TruthOrigin, $sourceType.ToLowerInvariant(), $sourceLocation.ToLowerInvariant(), $revision.ToLowerInvariant()
    return [pscustomobject][ordered]@{
        schema_version = 1
        id = 'cap-{0}' -f (Get-CapabilityContractHash $identity).Substring(0, 16)
        kind = $Kind
        name = $Name.Trim()
        truth_origin = $TruthOrigin
        source = [pscustomobject][ordered]@{
            type = $sourceType
            path_or_url = $sourceLocation
            revision = if ([string]::IsNullOrWhiteSpace($revision)) { $null } else { $revision }
            checksum = Get-OperationObjectProperty $Source 'checksum'
            license = Get-OperationObjectProperty $Source 'license'
            trust_tier = Get-OperationObjectProperty $Source 'trust_tier'
        }
        lifecycle = $Lifecycle
        host_compatibility = @($HostCompatibility | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        components = @($Components | Sort-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
        evidence = @($Evidence | Sort-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
        verification_state = $VerificationState
    }
}

function Test-CapabilityDescriptorContract($Descriptor) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Descriptor) { return New-OperationValidationResult @((New-OperationFinding 'descriptor_missing' 'error' '$' 'Capability descriptor is required.')) }
    if ((Get-OperationObjectProperty $Descriptor 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('id', 'kind', 'name', 'truth_origin', 'lifecycle', 'verification_state')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Descriptor $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required field is missing.')) | Out-Null }
    }
    if ([string](Get-OperationObjectProperty $Descriptor 'id') -notmatch '^cap-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'id_invalid' 'error' '$.id' 'Capability ID is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Descriptor 'kind') -notin @('skill', 'plugin', 'mcp')) { $findings.Add((New-OperationFinding 'kind_invalid' 'error' '$.kind' 'Capability kind is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Descriptor 'truth_origin') -notin @('runtime', 'reference', 'official', 'host_installed', 'candidate')) { $findings.Add((New-OperationFinding 'truth_origin_invalid' 'error' '$.truth_origin' 'Truth origin is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Descriptor 'lifecycle') -notin @('active', 'deprecated', 'historical', 'unknown')) { $findings.Add((New-OperationFinding 'lifecycle_invalid' 'error' '$.lifecycle' 'Lifecycle is invalid.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Descriptor 'verification_state') -notin @('not_verified', 'static_validated', 'repo_verified', 'host_loaded', 'live_accepted')) { $findings.Add((New-OperationFinding 'verification_state_invalid' 'error' '$.verification_state' 'Verification state is invalid.')) | Out-Null }
    $source = Get-OperationObjectProperty $Descriptor 'source'
    foreach ($field in @('type', 'path_or_url')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $source $field))) { $findings.Add((New-OperationFinding 'source_field_missing' 'error' ('$.source.{0}' -f $field) 'Source field is required.')) | Out-Null } }
    foreach ($field in @('host_compatibility', 'components', 'evidence')) { if (-not (Test-OperationArray (Get-OperationObjectProperty $Descriptor $field))) { $findings.Add((New-OperationFinding 'array_type_invalid' 'error' ('$.{0}' -f $field) 'Field must be an array.')) | Out-Null } }
    return New-OperationValidationResult $findings.ToArray()
}
