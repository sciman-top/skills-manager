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
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-WatchArmingSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$findings = [System.Collections.Generic.List[string]]::new()
try {
    $generation = $GenerationJson | ConvertFrom-Json -Depth 10 -ErrorAction Stop
    $guard = $GuardStatusJson | ConvertFrom-Json -Depth 10 -ErrorAction Stop
    $live = $LiveProbeJson | ConvertFrom-Json -Depth 10 -ErrorAction Stop
}
catch {
    $generation = $guard = $live = $null
    $findings.Add('preflight_json_invalid') | Out-Null
}

if ($null -ne $generation) {
    $generationId = [string](Get-WatchArmingProperty $generation 'watch_runtime_generation_id')
    if ($generationId -notmatch '^watch-runtime-generation:[0-9a-f]{64}$') { $findings.Add('generation_invalid') | Out-Null }
    foreach ($field in @('target_prompt_sha256', 'shutdown_target_prompt_sha256', 'fleet_prompt_sha256', 'fleet_shutdown_prompt_sha256', 'hook_source_sha256')) {
        if ([string](Get-WatchArmingProperty $generation $field) -notmatch '^[0-9a-f]{64}$') { $findings.Add("generation_$field`_invalid") | Out-Null }
    }
    $installedHookHash = [string](Get-WatchArmingProperty $generation 'installed_hook_sha256')
    if ($installedHookHash -notmatch '^[0-9a-f]{64}$' -or $installedHookHash -cne [string](Get-WatchArmingProperty $generation 'hook_source_sha256')) {
        $findings.Add('generation_installed_hook_unbound') | Out-Null
    }
    $bindingFields = [ordered]@{
        watch_runtime_generation_id = $generationId
        source_commit = [string](Get-WatchArmingProperty $generation 'source_commit')
        target_prompt_sha256 = [string](Get-WatchArmingProperty $generation 'target_prompt_sha256')
        shutdown_target_prompt_sha256 = [string](Get-WatchArmingProperty $generation 'shutdown_target_prompt_sha256')
        fleet_prompt_sha256 = [string](Get-WatchArmingProperty $generation 'fleet_prompt_sha256')
        fleet_shutdown_prompt_sha256 = [string](Get-WatchArmingProperty $generation 'fleet_shutdown_prompt_sha256')
        hook_source_sha256 = [string](Get-WatchArmingProperty $generation 'hook_source_sha256')
        installed_hook_sha256 = $installedHookHash
    }
    $bindingText = @($bindingFields.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join "`n"
    if ([string](Get-WatchArmingProperty $generation 'generation_binding_sha256') -cne (Get-WatchArmingSha256 -Text $bindingText)) {
        $findings.Add('generation_binding_mismatch') | Out-Null
    }

    if (-not [bool](Get-WatchArmingProperty $guard 'configuration_ready')) { $findings.Add('guard_not_ready') | Out-Null }
    if ([string](Get-WatchArmingProperty $guard 'trust_status') -cne 'trusted') { $findings.Add('hook_untrusted') | Out-Null }
    if ([string](Get-WatchArmingProperty $guard 'live_path_status') -cne 'verified') { $findings.Add('guard_live_path_unverified') | Out-Null }
    if ([string](Get-WatchArmingProperty $guard 'watch_runtime_generation_id') -cne $generationId) { $findings.Add('generation_mismatch') | Out-Null }
    foreach ($mapping in @(
        @{ Guard='source_sha256'; Generation='hook_source_sha256' },
        @{ Guard='host_sha256'; Generation='hook_source_sha256' },
        @{ Guard='target_prompt_sha256'; Generation='target_prompt_sha256' },
        @{ Guard='shutdown_target_prompt_sha256'; Generation='shutdown_target_prompt_sha256' },
        @{ Guard='fleet_prompt_sha256'; Generation='fleet_prompt_sha256' },
        @{ Guard='fleet_shutdown_prompt_sha256'; Generation='fleet_shutdown_prompt_sha256' }
    )) {
        if ([string](Get-WatchArmingProperty $guard $mapping.Guard) -cne [string](Get-WatchArmingProperty $generation $mapping.Generation)) {
            $findings.Add("$($mapping.Guard)_mismatch") | Out-Null
        }
    }

    foreach ($field in @('fresh_session', 'target_self_pause_allowed', 'target_self_delete_blocked', 'cross_target_pause_blocked', 'supervisor_cleanup_delete_allowed', 'supervisor_final_self_delete_allowed', 'native_receipt_verified')) {
        if (-not [bool](Get-WatchArmingProperty $live $field)) { $findings.Add("live_$field`_unproved") | Out-Null }
    }
}

if (-not $NativeAutomationCapabilityReady) { $findings.Add('native_automation_capability_unavailable') | Out-Null }
$ready = $findings.Count -eq 0
$result = [pscustomobject][ordered]@{
    schema_version = 1
    arming_ready = $ready
    status = if ($ready) { 'shutdown_armed' } else { 'not_armed' }
    rollback_required = -not $ready
    watch_runtime_generation_id = if ($null -eq $generation) { '' } else { [string](Get-WatchArmingProperty $generation 'watch_runtime_generation_id') }
    findings = @($findings.ToArray())
}

if ($AsJson) { $result | ConvertTo-Json -Depth 5 -Compress } else { $result }
