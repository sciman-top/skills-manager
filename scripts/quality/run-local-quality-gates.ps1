[CmdletBinding()]
param(
    [ValidateSet('quick', 'full')]
    [string]$Profile = 'quick',
    [switch]$AllowDirtyWorktree
)

$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Invoke-QualityGate([string]$Name, [scriptblock]$Action) {
    Write-Host ""
    Write-Host ("== {0} ==" -f $Name)
    $global:LASTEXITCODE = 0
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw ("Quality gate failed: {0} (exit={1})" -f $Name, $LASTEXITCODE)
    }
}

Push-Location $root
try {
    Invoke-QualityGate 'build' { & .\build.ps1 }
    Invoke-QualityGate 'repo-hygiene' { & .\scripts\quality\check-repo-hygiene.ps1 -ReportUntrackedRuntimeArtifacts }
    if ($AllowDirtyWorktree) {
        Invoke-QualityGate 'generated-sync' { & .\tests\check-generated-sync.ps1 -AllowDirtyWorktree }
    }
    else {
        Invoke-QualityGate 'generated-sync' { & .\tests\check-generated-sync.ps1 -StrictNoGit }
    }
    Invoke-QualityGate 'dependency-baseline' { & python .\scripts\verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline }
    Invoke-QualityGate 'doctor-json-contract' { & .\scripts\quality\check-doctor-json.ps1 }

    if ($Profile -eq 'full') {
        Invoke-QualityGate 'tests' { & .\tests\run.ps1 }
    }

    Write-Host ""
    Write-Host ("Local quality gates passed ({0})." -f $Profile)
}
finally {
    Pop-Location
}
