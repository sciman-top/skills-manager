[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GenerationJson,
    [Parameter(Mandatory = $true)][string]$GuardStatusJson,
    [Parameter(Mandatory = $true)][string]$LiveProbeJson,
    [switch]$NativeAutomationCapabilityReady,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WatchArmingProperty {
    param([AllowNull()][object]$InputObject,[Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [Collections.IDictionary] -and $InputObject.Contains($Name)) { return $InputObject[$Name] }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

$findings = [Collections.Generic.List[string]]::new()
try {
    $generation = $GenerationJson | ConvertFrom-Json -Depth 30 -ErrorAction Stop
    $guard = $GuardStatusJson | ConvertFrom-Json -Depth 30 -ErrorAction Stop
    $live = $LiveProbeJson | ConvertFrom-Json -Depth 30 -ErrorAction Stop
}
catch {
    $generation = $guard = $live = $null
    $findings.Add('preflight_json_invalid') | Out-Null
}

if ($null -ne $generation) {
    $generationId = [string](Get-WatchArmingProperty $generation 'watch_runtime_generation_id')
    if ($generationId -notmatch '^watch-runtime-generation:[0-9a-f]{64}$') { $findings.Add('generation_invalid') | Out-Null }
    if (-not [bool](Get-WatchArmingProperty $generation 'repo_clean')) { $findings.Add('generation_repo_dirty') | Out-Null }
    if (-not [bool](Get-WatchArmingProperty $generation 'source_blobs_verified')) { $findings.Add('generation_source_blobs_unverified') | Out-Null }
    foreach ($field in @('target_prompt_sha256','shutdown_target_prompt_sha256','fleet_prompt_sha256','fleet_shutdown_prompt_sha256','hook_source_sha256','hook_policy_source_sha256','generation_binding_sha256')) {
        if ([string](Get-WatchArmingProperty $generation $field) -notmatch '^[0-9a-f]{64}$') { $findings.Add("generation_$field`_invalid") | Out-Null }
    }
    foreach ($pair in @(
        @('installed_hook_sha256','hook_source_sha256'),
        @('installed_policy_sha256','hook_policy_source_sha256')
    )) {
        $installed = [string](Get-WatchArmingProperty $generation $pair[0])
        $source = [string](Get-WatchArmingProperty $generation $pair[1])
        if ($installed -notmatch '^[0-9a-f]{64}$' -or $installed -cne $source) { $findings.Add("generation_$($pair[0])_unbound") | Out-Null }
    }

    if (-not [bool](Get-WatchArmingProperty $guard 'configuration_ready')) { $findings.Add('guard_not_ready') | Out-Null }
    if ([string](Get-WatchArmingProperty $guard 'trust_status') -cne 'trusted') { $findings.Add('hook_untrusted') | Out-Null }
    if ([string](Get-WatchArmingProperty $guard 'live_path_status') -cne 'verified') { $findings.Add('guard_live_path_unverified') | Out-Null }
    if ([string](Get-WatchArmingProperty $guard 'watch_runtime_generation_id') -cne $generationId) { $findings.Add('generation_mismatch') | Out-Null }
    foreach ($mapping in @(
        @('source_sha256','hook_source_sha256'),
        @('host_sha256','hook_source_sha256'),
        @('policy_source_sha256','hook_policy_source_sha256'),
        @('policy_host_sha256','hook_policy_source_sha256'),
        @('target_prompt_sha256','target_prompt_sha256'),
        @('shutdown_target_prompt_sha256','shutdown_target_prompt_sha256'),
        @('fleet_prompt_sha256','fleet_prompt_sha256'),
        @('fleet_shutdown_prompt_sha256','fleet_shutdown_prompt_sha256')
    )) {
        if ([string](Get-WatchArmingProperty $guard $mapping[0]) -cne [string](Get-WatchArmingProperty $generation $mapping[1])) {
            $findings.Add("$($mapping[0])_mismatch") | Out-Null
        }
    }

    foreach ($field in @('fresh_session','host_automation_id_supported','full_heartbeat_update_supported','target_self_pause_allowed','target_self_delete_blocked','cross_target_pause_blocked','paused_target_cleanup_delete_allowed','supervisor_final_self_delete_allowed','exact_shutdown_guard_allowed','native_receipt_verified')) {
        if (-not [bool](Get-WatchArmingProperty $live $field)) { $findings.Add("live_$field`_unproved") | Out-Null }
    }
}

if (-not $NativeAutomationCapabilityReady) { $findings.Add('native_automation_capability_unavailable') | Out-Null }
$ready = $findings.Count -eq 0
$result = [pscustomobject][ordered]@{
    schema_version = 2
    arming_ready = $ready
    status = if ($ready) { 'shutdown_armed' } else { 'not_armed' }
    rollback_required = -not $ready
    watch_runtime_generation_id = if ($null -eq $generation) { '' } else { [string](Get-WatchArmingProperty $generation 'watch_runtime_generation_id') }
    findings = @($findings.ToArray())
}

if ($AsJson) { $result | ConvertTo-Json -Depth 8 -Compress } else { $result }
