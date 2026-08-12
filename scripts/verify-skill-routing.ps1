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
    $installedFacts = @(Get-InstalledSkillFacts $cfg)
    foreach ($fact in $installedFacts) {
        $canonical.Add([pscustomobject]([ordered]@{
                    name = [string]$fact.name
                    description = [string]$fact.description
                    path = Join-Path ([string]$fact.local_path) 'SKILL.md'
                    is_system = $false
                })) | Out-Null
    }

    $materializedAgentSkillCount = 0
    if (Test-Path -LiteralPath $AgentDir -PathType Container) {
        $materializedAgentSkillCount = @(Get-ChildItem -LiteralPath $AgentDir -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf }).Count
    }
    $materializationStatus = if ($materializedAgentSkillCount -gt 0) { 'materialized' } else { 'source_only' }
    $sourceDeclaredNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $policyOnlyNames = New-Object System.Collections.Generic.List[string]
    $sourceMetadata = @{}
    foreach ($mapping in @($cfg.mappings)) {
        $declaredName = ([string]$mapping.to).Trim()
        if (-not [string]::IsNullOrWhiteSpace($declaredName)) { $sourceDeclaredNames.Add($declaredName) | Out-Null }
    }
    foreach ($residentName in @($cfg.skill_projection.resident_names)) {
        $declaredName = ([string]$residentName).Trim()
        if (-not [string]::IsNullOrWhiteSpace($declaredName)) { $sourceDeclaredNames.Add($declaredName) | Out-Null }
    }
    foreach ($profile in @($cfg.skill_projection.profiles.PSObject.Properties)) {
        foreach ($enabledName in @($profile.Value.enabled_names)) {
            $declaredName = ([string]$enabledName).Trim()
            if (-not [string]::IsNullOrWhiteSpace($declaredName)) { $sourceDeclaredNames.Add($declaredName) | Out-Null }
        }
    }
    $configRoot = Split-Path -Parent ([IO.Path]::GetFullPath($ConfigPath))
    $overrideRoot = Join-Path $configRoot 'overrides'
    if (Test-Path -LiteralPath $overrideRoot -PathType Container) {
        foreach ($overrideDirectory in (Get-ChildItem -LiteralPath $overrideRoot -Directory)) {
            $skillPath = Join-Path $overrideDirectory.FullName 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { continue }
            $metadata = Get-SkillMetadataFromFile $skillPath
            $declaredName = ([string]$metadata.declared_name).Trim()
            if ([string]::IsNullOrWhiteSpace($declaredName)) { continue }
            $sourceDeclaredNames.Add($declaredName) | Out-Null
            $sourceMetadata[$declaredName] = [pscustomobject]@{ description = [string]$metadata.description; path = $skillPath }
        }
    }
    if ($materializationStatus -eq 'source_only') {
        $routingPolicyPath = [string]$cfg.skill_projection.routing_policy_path
        if (-not [string]::IsNullOrWhiteSpace($routingPolicyPath)) {
            $policy = Get-SkillRoutingPolicy (Resolve-SkillProjectionPath $routingPolicyPath)
            $policyNames = @($policy.groups.members.name) + @($policy.conflicts.members)
            foreach ($policyName in @($policyNames | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
                if ($sourceDeclaredNames.Add($policyName)) { $policyOnlyNames.Add($policyName) | Out-Null }
            }
        }
        $canonicalNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $canonical) { $canonicalNames.Add(([string]$entry.name).Trim()) | Out-Null }
        foreach ($declaredName in $sourceDeclaredNames) {
            if (-not $canonicalNames.Add($declaredName)) { continue }
            $metadata = if ($sourceMetadata.ContainsKey($declaredName)) { $sourceMetadata[$declaredName] } else { $null }
            $canonical.Add([pscustomobject]([ordered]@{
                        name = $declaredName
                        description = if ($null -eq $metadata) { '' } else { [string]$metadata.description }
                        path = if ($null -eq $metadata) { '' } else { [string]$metadata.path }
                        is_system = $false
                    })) | Out-Null
        }
    }

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
    foreach ($name in @($cfg.skill_projection.resident_names)) { $enabledNames.Add(([string]$name).Trim()) | Out-Null }
    $active = @($canonical.ToArray() | Where-Object { [bool]$_.is_system -or $enabledNames.Contains([string]$_.name) })
    $externalInventory = Get-CodexExternalSkillInventory $cfg.skill_projection
    $routing = New-SkillRoutingReport $cfg.skill_projection @($canonical.ToArray()) @($active) @($externalInventory.skills)
    $report = [pscustomobject]([ordered]@{
            schema_version = 1
            generated_at = [DateTime]::UtcNow.ToString('o')
            ok = (-not [bool]$routing.blocking)
            materialization_status = $materializationStatus
            materialized_agent_skill_count = $materializedAgentSkillCount
            source_declared_skill_count = $sourceDeclaredNames.Count
            policy_only_skill_count = $policyOnlyNames.Count
            policy_only_skills = @($policyOnlyNames.ToArray())
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
    Write-Host ("skill routing verified: profile={0}, active={1}, external={2}, findings={3}, mode={4}, materialization={5}" -f $report.active_profile, $report.active_skill_count, $report.external_skill_count, $report.routing.finding_count, $report.routing.mode, $report.materialization_status)
    if ($report.materialization_status -eq 'source_only') {
        Write-Host ("- [inventory/agent_runtime_not_materialized] validated {0} tracked source/policy declarations; generated package metadata was not inspected" -f $report.source_declared_skill_count) -ForegroundColor Yellow
        if ($report.policy_only_skill_count -gt 0) {
            Write-Host ("- [inventory/policy_members_not_materialized] {0} policy members require a materialized agent or live host snapshot: {1}" -f $report.policy_only_skill_count, (@($report.policy_only_skills) -join ', ')) -ForegroundColor Yellow
        }
    }
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
