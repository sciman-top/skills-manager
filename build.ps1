#requires -Version 7.0
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Src = Join-Path $Root "src"
$Dist = Join-Path $Root "skills.ps1"

$Files = @(
    "Version.ps1",
    "Infrastructure/AtomicFile.ps1",
    "Core.ps1",
    "Domain/OperationPlan.ps1",
    "Domain/HostCapabilitySnapshot.ps1",
    "Domain/SkillCatalog.ps1",
    "Domain/Receipt.ps1",
    "Domain/CapabilityDescriptor.ps1",
    "Domain/PluginManifest.ps1",
    "Domain/RuleDocument.ps1",
    "Domain/RuleResponsibility.ps1",
    "Domain/RulePatchPlan.ps1",
    "Application/CapabilityInventory.ps1",
    "Application/SkillEvolution.ps1",
    "Application/HostCapabilityResolution.ps1",
    "Application/SkillCatalogCompiler.ps1",
    "Application/SkillEligibilityPolicy.ps1",
    "Application/NativeMetadataPlanner.ps1",
    "Application/SkillProjection.ps1",
    "Application/NativeSkillProjection.ps1",
    "Application/NativeSkillProjectionCoordinator.ps1",
    "Infrastructure/HostCapabilityAdapters.ps1",
    "Application/PluginDistribution.ps1",
    "Application/RuleDiscovery.ps1",
    "Application/RuleDiagnostics.ps1",
    "Application/RuleAdvisor.ps1",
    "Application/RuleAudit.ps1",
    "Application/RuleEstate.ps1",
    "Application/RuleEstateMutation.ps1",
    "Application/RulePatchGuard.ps1",
    "Application/RulePatchExecutor.ps1",
    "Git.ps1",
    "Config.ps1",
    "Commands/Doctor.ps1",
    "Commands/Install.ps1",
    "Commands/Update.ps1",
    "Commands/Mcp.ps1",
    "Application/McpPlanning.ps1",
    "Commands/Capability.ps1",
    "Commands/Plugin.ps1",
    "Commands/RuleAudit.ps1",
    "Commands/RuleEstate.ps1",
    "Commands/RulePatch.ps1",
    "Commands/AuditTargets.ps1",
    "Commands/AuditTargets.Template.ps1",
    "Commands/AuditTargets.Snapshot.ps1",
    "Commands/AuditTargets.TargetState.ps1",
    "Commands/AuditTargets.Plan.ps1",
    "Commands/AuditTargets.Bundle.ps1",
    "Commands/AuditTargets.Apply.ps1",
    "Commands/AuditTargets.Workflow.ps1",
    "Commands/AuditTargets.Args.ps1",
    "Commands/SkillProjection.ps1",
    "Commands/SkillEvolution.ps1",
    "Commands/Workflow.ps1",
    "Commands/Utils.ps1",
    "Main.ps1"
)

$Content = @()
foreach ($f in $Files) {
    $p = Join-Path $Src $f
    if (-not (Test-Path $p)) { throw "Missing source file: $p" }
    # Read as UTF8 (Force)
    $Content += Get-Content -Path $p -Raw -Encoding UTF8
    $Content += "`r`n"
}

# Keep a deterministic UTF-8 BOM for Windows distribution. This is an encoding
# choice for predictable file detection, not a Windows PowerShell 5.1 contract.
# Use bytes explicitly to avoid host/runtime encoding differences.
$utf8NoBom = [System.Text.Encoding]::UTF8
$bom = (New-Object System.Text.UTF8Encoding($true)).GetPreamble()
$payloadText = ($Content -join "")
$parseTokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($payloadText, [ref]$parseTokens, [ref]$parseErrors) | Out-Null
if (@($parseErrors).Count -gt 0) {
    $details = @($parseErrors | ForEach-Object { '{0} at line {1}, column {2}' -f $_.Message, $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber }) -join '; '
    throw ("bundle_parse_failed: {0}" -f $details)
}
$payload = $utf8NoBom.GetBytes($payloadText)
$bytes = New-Object byte[] ($bom.Length + $payload.Length)
[Array]::Copy($bom, 0, $bytes, 0, $bom.Length)
[Array]::Copy($payload, 0, $bytes, $bom.Length, $payload.Length)
[System.IO.File]::WriteAllBytes($Dist, $bytes)
Write-Host "Build success: $Dist" -ForegroundColor Green
