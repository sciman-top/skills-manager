[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ProposalPath = "",
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = "Stop"
$root = [System.IO.Path]::GetFullPath($RepoRoot)
$entry = Join-Path $root "skills.ps1"
$configPath = Join-Path $root "skills.json"

try {
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "skills.ps1 is missing: $entry" }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "skills.json is missing: $configPath" }
    Push-Location $root
    try {
        . $entry
    }
    finally { Pop-Location }
    $cfg = Get-ContentUtf8 $configPath | ConvertFrom-Json
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("skill_projection").Count -eq 0) { throw "skills.json does not define skill_projection." }
    if ($cfg.PSObject.Properties.Match("skill_projection").Count -eq 0 -or $null -eq $cfg.skill_projection) { throw "skills.json does not define skill_projection." }
    $proposal = if ([string]::IsNullOrWhiteSpace($ProposalPath)) { $null } else { Read-SkillProfileReconciliationProposal $ProposalPath }
    $result = New-SkillProfileReconciliationPlan $cfg.skill_projection (Get-FileContentHash $configPath) $proposal
}
catch {
    $result = [pscustomobject]([ordered]@{
            schema_version = 1
            command = "plan-skill-profile-reconciliation"
            decision_owner = "host_ai"
            semantic_routing_performed = $false
            pass = $false
            apply_allowed = $false
            writes_performed = $false
            config_sha256 = if (Test-Path -LiteralPath $configPath -PathType Leaf) { (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { "" }
            proposal_supplied = (-not [string]::IsNullOrWhiteSpace($ProposalPath))
            current = $null
            actions = @()
            proposed = $null
            overlaps = @()
            finding_count = 1
            findings = @([pscustomobject]@{ code = "planner_error"; message = $_.Exception.Message; blocking = $true; skill = ""; profile = "" })
        })
}

if ($Json) { Write-Output ($result | ConvertTo-Json -Depth 20) }
elseif ([bool]$result.pass) {
    Write-Host ("Profile reconciliation plan passed: unrouted={0}, actions={1}, writes=0" -f @($result.current.unrouted_names).Count, @($result.actions).Count) -ForegroundColor Green
}
else {
    foreach ($finding in @($result.findings | Where-Object blocking)) { Write-Host ("[{0}] {1}" -f $finding.code, $finding.message) -ForegroundColor Red }
}

if (-not [bool]$result.pass -and -not $NoExit) { exit 2 }
