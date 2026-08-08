[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$PolicyPath,
    [string]$ReportPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $repoRoot 'skills.json' }

function New-RetiredSkillRoutingReport {
    param([object]$Config, [string]$Path)

    Need ($null -ne $Config.skill_projection) 'skills config has no skill_projection section'
    $projection = $Config.skill_projection
    $directFieldNames = @('active_profile', 'profiles')
    $directFields = @($projection.PSObject.Properties.Name | Where-Object { $directFieldNames -contains $_ })
    Need ($directFields.Count -eq 0) ('retired profile fields remain authoritative: {0}' -f ($directFields -join ', '))
    Need ($null -ne $projection.profile_compatibility) 'skill_projection.profile_compatibility is required during staged removal'
    $compatibility = $projection.profile_compatibility
    Need ([string]$compatibility.status -eq 'read_only') 'profile compatibility view must be read_only'
    Need ([string]$compatibility.reachability_authority -eq 'none') 'profile compatibility view cannot own reachability'

    $manifestPath = Join-Path $repoRoot 'reports/skill-projection/current.json'
    $projectedCount = 0
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $manifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
            if ($null -ne $manifest.skills) { $projectedCount = @($manifest.skills).Count }
        }
        catch { $projectedCount = 0 }
    }

    return [pscustomobject][ordered]@{
        schema_version = 2
        verifier_id = 'skill-routing-compatibility'
        generated_at = [DateTime]::UtcNow.ToString('o')
        ok = $true
        blocking = $false
        mode = 'compatibility_only'
        policy_path = if ([string]::IsNullOrWhiteSpace($PolicyPath)) { [string]$projection.routing_policy_path } else { [string]$PolicyPath }
        active_profile = [string]$compatibility.active_profile
        projected_skill_count = $projectedCount
        legacy_router_semantic_authority = $false
        profile_reachability_authority = 'none'
        writes_performed = $false
        provider_calls = 0
        native_mutations = 0
        compatibility_view = $compatibility
        findings = @()
        finding_count = 0
    }
}

try {
    . (Join-Path $repoRoot 'skills.ps1')
    Need (Test-Path -LiteralPath $ConfigPath -PathType Leaf) ("skills config does not exist: {0}" -f $ConfigPath)
    $cfg = Get-ContentUtf8 $ConfigPath | ConvertFrom-Json
    $report = New-RetiredSkillRoutingReport $cfg $ConfigPath
}
catch {
    $report = [pscustomobject][ordered]@{
        schema_version = 2
        verifier_id = 'skill-routing-compatibility'
        generated_at = [DateTime]::UtcNow.ToString('o')
        ok = $false
        blocking = $true
        mode = 'compatibility_only'
        legacy_router_semantic_authority = $false
        profile_reachability_authority = 'none'
        writes_performed = $false
        provider_calls = 0
        native_mutations = 0
        error = $_.Exception.Message
        findings = @()
        finding_count = 1
    }
}

$serialized = $report | ConvertTo-Json -Depth 30
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $parent = Split-Path -Parent $ReportPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-ContentUtf8 $ReportPath $serialized
}

if ($Json) { Write-Output $serialized }
elseif ([bool]$report.ok) { Write-Host ('skill routing compatibility verified: mode={0}, projected={1}, profile_authority={2}' -f $report.mode, $report.projected_skill_count, $report.profile_reachability_authority) }
else { Write-Host ('skill routing compatibility verification failed: {0}' -f [string]$report.error) -ForegroundColor Red }

if (-not [bool]$report.ok) { exit 1 }
exit 0
