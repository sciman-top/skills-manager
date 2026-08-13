[CmdletBinding()]
param(
    [ValidateSet('quick', 'full')]
    [string]$Profile = 'quick',
    [switch]$AllowDirtyWorktree
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Invoke-QualityGate([string]$Name, [scriptblock]$Action) {
    Write-Host ("== {0} ==" -f $Name)
    $global:LASTEXITCODE = 0
    & $Action
    if ($LASTEXITCODE -ne 0) { throw ("Quality gate failed: {0} (exit={1})" -f $Name, $LASTEXITCODE) }
}

Push-Location $root
try {
    Invoke-QualityGate 'build' { & .\build.ps1 }
    if ($Profile -eq 'full') { Invoke-QualityGate 'tests' { & .\tests\run.ps1 } }
    if (-not $AllowDirtyWorktree) {
        Invoke-QualityGate 'generated-bundle-committed' { & git diff --quiet HEAD -- skills.ps1 }
    }
    Invoke-QualityGate 'workspace-lock-parity' { & .\skills.ps1 verify-lock }
    Invoke-QualityGate 'skill-integrity' { & .\scripts\verify-skill-integrity.ps1 }
    Invoke-QualityGate 'skills-config-contract' { & .\scripts\verify-skills-config.ps1 -Mode enforce }
    Write-Host ("Local quality gates passed ({0})." -f $Profile)
}
finally {
    Pop-Location
}
