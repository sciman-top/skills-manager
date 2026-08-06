[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CurrentOperationJson,
    [Parameter(Mandatory = $true)][string]$PeerOperationsJson,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WatchPeerProperty {
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-WatchPeerOperationShape {
    param([Parameter(Mandatory = $true)][object]$Operation)
    $taskId = [string](Get-WatchPeerProperty $Operation 'task_id')
    $repository = [string](Get-WatchPeerProperty $Operation 'repository_identity')
    $checkout = [string](Get-WatchPeerProperty $Operation 'checkout_identity')
    $state = [string](Get-WatchPeerProperty $Operation 'operation_state')
    $domain = [string](Get-WatchPeerProperty $Operation 'write_domain')
    return $taskId -match '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$' -and
        $repository -match '^[A-Za-z0-9][A-Za-z0-9._:\\/-]{0,511}$' -and
        $checkout -match '^[A-Za-z0-9][A-Za-z0-9._:\\/-]{0,511}$' -and
        $state -in @('read_only','external_wait','write_planning','writing','git_ref_mutation') -and
        $domain -in @('working_tree','git_index','git_refs','generated_runtime','host_config','external_effect')
}

function Test-WatchWriteCapableState {
    param([string]$State)
    return $State -in @('write_planning','writing','git_ref_mutation')
}

function Test-WatchWriteDomainOverlap {
    param([string]$CurrentDomain, [string]$PeerDomain)
    if ($CurrentDomain -ceq $PeerDomain) { return $true }
    $workingTreeFamily = @('working_tree','git_index','generated_runtime')
    return $CurrentDomain -in $workingTreeFamily -and $PeerDomain -in $workingTreeFamily
}

$result = [ordered]@{
    schema_version = 1
    classification = 'unknown'
    peer_busy = $false
    reason_code = 'input_json_invalid'
    blocking_peer_ids = @()
}

try {
    $current = $CurrentOperationJson | ConvertFrom-Json -Depth 10 -ErrorAction Stop
    $peers = @($PeerOperationsJson | ConvertFrom-Json -Depth 10 -ErrorAction Stop)
}
catch {
    $current = $null
    $peers = @()
}

if ($null -ne $current) {
    if (-not (Test-WatchPeerOperationShape $current)) {
        $result.reason_code = 'identity_unproved'
    }
    elseif (@($peers | Where-Object { -not (Test-WatchPeerOperationShape $_) }).Count -gt 0) {
        $result.reason_code = 'peer_schema_unproved'
    }
    else {
        $currentRepo = [string]$current.repository_identity
        $currentCheckout = [string]$current.checkout_identity
        $currentState = [string]$current.operation_state
        $currentDomain = [string]$current.write_domain
        $blockers = [Collections.Generic.List[string]]::new()
        foreach ($peer in $peers) {
            $peerState = [string]$peer.operation_state
            if (-not (Test-WatchWriteCapableState $currentState) -or -not (Test-WatchWriteCapableState $peerState)) { continue }
            $sameRepository = [string]$peer.repository_identity -ceq $currentRepo
            $sameCheckout = [string]$peer.checkout_identity -ceq $currentCheckout
            $sharedGitRefs = $sameRepository -and $currentDomain -ceq 'git_refs' -and [string]$peer.write_domain -ceq 'git_refs'
            $sameCheckoutOverlap = $sameCheckout -and (Test-WatchWriteDomainOverlap $currentDomain ([string]$peer.write_domain))
            if ($sharedGitRefs -or $sameCheckoutOverlap) { $blockers.Add([string]$peer.task_id) | Out-Null }
        }

        $result.classification = if ($blockers.Count -gt 0) { 'peer_busy' } else { 'clear' }
        $result.peer_busy = $blockers.Count -gt 0
        $result.reason_code = if ($blockers.Count -gt 0) { 'overlapping_writer' } else { 'no_overlapping_writer' }
        $result.blocking_peer_ids = @($blockers.ToArray() | Sort-Object -Unique)
    }
}

$output = [pscustomobject]$result
if ($AsJson) { $output | ConvertTo-Json -Depth 6 -Compress } else { $output }
