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

function Assert-HostSchedulerOwnershipContract {
    $gatePath = [IO.Path]::GetFullPath($PSCommandPath)
    $patterns = @(
        [regex]::new('\b(?:Register|Set|Unregister)-ScheduledTask\b', [Text.RegularExpressions.RegexOptions]::IgnoreCase),
        [regex]::new('\bschtasks(?:\.exe)?\b[^\r\n]*(?:/Create|/Change|/Delete)\b', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    )
    $findings = [Collections.Generic.List[string]]::new()

    foreach ($scanRoot in @((Join-Path $root 'src'), (Join-Path $root 'scripts'))) {
        foreach ($file in @(Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Filter '*.ps1')) {
            if ([IO.Path]::GetFullPath($file.FullName) -eq $gatePath) { continue }
            $lines = [IO.File]::ReadAllLines($file.FullName)
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if (@($patterns | Where-Object { $_.IsMatch($lines[$index]) }).Count -gt 0) {
                    $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
                    $findings.Add(('{0}:{1}' -f $relative, ($index + 1))) | Out-Null
                }
            }
        }
    }

    if ($findings.Count -gt 0) {
        throw ('Host scheduler lifecycle belongs to host/operator; mutating production entrypoints found: {0}' -f ($findings -join ', '))
    }
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
    Invoke-QualityGate 'host-scheduler-ownership' { Assert-HostSchedulerOwnershipContract }
    Write-Host ("Local quality gates passed ({0})." -f $Profile)
}
finally {
    Pop-Location
}
