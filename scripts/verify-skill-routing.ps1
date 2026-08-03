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

try {
    . (Join-Path $repoRoot 'skills.ps1')
    Need (Test-Path -LiteralPath $ConfigPath -PathType Leaf) ("skills config does not exist: {0}" -f $ConfigPath)
    $cfg = Get-ContentUtf8 $ConfigPath | ConvertFrom-Json
    Need ($null -ne $cfg.skill_projection) 'skills config has no skill_projection section'
    if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) {
        $cfg.skill_projection | Add-Member -NotePropertyName routing_policy_path -NotePropertyValue $PolicyPath -Force
    }

    $canonical = New-Object System.Collections.Generic.List[object]
    foreach ($fact in @(Get-SkillRoutingLocalInventory $cfg)) { $canonical.Add($fact) | Out-Null }

    $userSkillRootRaw = if ($cfg.skill_projection.PSObject.Properties.Match('user_skill_root').Count -gt 0) { [string]$cfg.skill_projection.user_skill_root } else { '~/.agents/skills' }
    $userSkillRoot = Resolve-SkillProjectionPath $userSkillRootRaw
    foreach ($item in @(Get-SkillProjectionFiles $userSkillRoot | Where-Object is_system)) {
        $meta = Get-SkillMetadataFromFile ([string]$item.file)
        $canonical.Add([pscustomobject]([ordered]@{
                    name = [string]$meta.declared_name
                    description = [string]$meta.description
                    path = [string]$item.file
                    is_system = $true
                })) | Out-Null
    }

    $activeProfile = ([string]$cfg.skill_projection.active_profile).Trim()
    Need (-not [string]::IsNullOrWhiteSpace($activeProfile)) 'skill_projection.active_profile is empty'
    $profileProperty = @($cfg.skill_projection.profiles.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $activeProfile, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    Need ($profileProperty.Count -eq 1) ("skill_projection.active_profile does not exist: {0}" -f $activeProfile)
    $enabledNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($profileProperty[0].Value.enabled_names)) { $enabledNames.Add(([string]$name).Trim()) | Out-Null }
    $active = @($canonical.ToArray() | Where-Object { [bool]$_.is_system -or $enabledNames.Contains([string]$_.name) })
    $externalInventory = Get-CodexExternalSkillInventory $cfg.skill_projection
    $routing = New-SkillRoutingReport $cfg.skill_projection @($canonical.ToArray()) @($active) @($externalInventory.skills)
    $report = [pscustomobject]([ordered]@{
            schema_version = 1
            generated_at = [DateTime]::UtcNow.ToString('o')
            ok = (-not [bool]$routing.blocking)
            active_profile = $activeProfile
            active_skill_count = @($active).Count
            external_skill_count = [int]$externalInventory.skill_count
            external_inventory_warnings = @($externalInventory.warnings)
            routing = $routing
        })
}
catch {
    $report = [pscustomobject]([ordered]@{
            schema_version = 1
            generated_at = [DateTime]::UtcNow.ToString('o')
            ok = $false
            error = $_.Exception.Message
        })
}

$serialized = $report | ConvertTo-Json -Depth 20
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $parent = Split-Path -Parent $ReportPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-ContentUtf8 $ReportPath $serialized
}

if ($Json) {
    Write-Output $serialized
}
elseif ([bool]$report.ok) {
    Write-Host ("skill routing verified: profile={0}, active={1}, external={2}, findings={3}, mode={4}" -f $report.active_profile, $report.active_skill_count, $report.external_skill_count, $report.routing.finding_count, $report.routing.mode)
    foreach ($finding in @($report.routing.findings)) {
        Write-Host ("- [{0}/{1}] {2}: {3}" -f $finding.severity, $finding.code, $finding.subject, $finding.message) -ForegroundColor Yellow
    }
    foreach ($warning in @($report.external_inventory_warnings)) {
        Write-Host ("- [inventory/{0}] {1}: {2}" -f $warning.code, $warning.subject, $warning.message) -ForegroundColor Yellow
    }
}
else {
    Write-Host ("skill routing verification failed: {0}" -f [string]$report.error) -ForegroundColor Red
}

if (-not [bool]$report.ok) { exit 1 }
exit 0
