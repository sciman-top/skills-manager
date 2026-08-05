[CmdletBinding()]
param(
    [ValidateSet('quick', 'full')]
    [string]$Profile = 'quick',
    [switch]$AllowDirtyWorktree
)

$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:GateResults = [Collections.Generic.List[object]]::new()

function Invoke-QualityGate([string]$Name, [scriptblock]$Action) {
    Write-Host ""
    Write-Host ("== {0} ==" -f $Name)
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $passed = $false
    $global:LASTEXITCODE = 0
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) {
            throw ("Quality gate failed: {0} (exit={1})" -f $Name, $LASTEXITCODE)
        }
        $passed = $true
    }
    finally {
        $stopwatch.Stop()
        $script:GateResults.Add([pscustomobject]@{ name = $Name; passed = $passed; elapsed_ms = $stopwatch.ElapsedMilliseconds }) | Out-Null
        Write-Host ("gate_elapsed_ms={0}" -f $stopwatch.ElapsedMilliseconds)
    }
}

Push-Location $root
try {
    Invoke-QualityGate 'build' { & .\build.ps1 }
    if ($Profile -eq 'full') {
        Invoke-QualityGate 'tests' { & .\tests\run.ps1 }
    }
    Invoke-QualityGate 'repo-hygiene' { & .\scripts\quality\check-repo-hygiene.ps1 -ReportUntrackedRuntimeArtifacts }
    if ($AllowDirtyWorktree) {
        Invoke-QualityGate 'generated-sync' { & .\tests\check-generated-sync.ps1 -AllowDirtyWorktree }
    }
    else {
        Invoke-QualityGate 'generated-sync' { & .\tests\check-generated-sync.ps1 -StrictNoGit }
    }
    Invoke-QualityGate 'skill-integrity' { & .\scripts\verify-skill-integrity.ps1 }
    Invoke-QualityGate 'reference-governance' { & .\scripts\verify-reference-governance.ps1 }
    Invoke-QualityGate 'override-activation-corpus' { & .\scripts\verify-override-skill-activation.ps1 }
    Invoke-QualityGate 'skill-routing' { & .\scripts\verify-skill-routing.ps1 -ReportPath .\reports\skill-routing\current.json }
    Invoke-QualityGate 'dependency-baseline' { & python .\scripts\verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline }
    Invoke-QualityGate 'skills-config-contract' { & .\scripts\verify-skills-config.ps1 -Mode enforce }
    Invoke-QualityGate 'host-capability-contract' { & .\scripts\verify-host-capability-matrix.ps1 }
    Invoke-QualityGate 'planning-contract' { & .\scripts\verify-vnext-planning.ps1 }
    Invoke-QualityGate 'powershell-runtime-policy' { & .\scripts\verify-powershell-runtime-policy.ps1 }
    Invoke-QualityGate 'agent-workflow-advisory' { & .\scripts\verify-agent-workflow-advisory.ps1 }
    Invoke-QualityGate 'doctor-json-contract' { & .\scripts\quality\check-doctor-json.ps1 }

    Write-Host ""
    $totalElapsed = [long](($script:GateResults | Measure-Object -Property elapsed_ms -Sum).Sum)
    Write-Host ("Gate summary: {0}; total_elapsed_ms={1}" -f (($script:GateResults | ForEach-Object { '{0}={1}ms' -f $_.name, $_.elapsed_ms }) -join ', '), $totalElapsed)
    Write-Host ("Local quality gates passed ({0})." -f $Profile)
}
finally {
    Pop-Location
}
