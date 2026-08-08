[CmdletBinding()]
param(
    [ValidateSet('quick', 'full')]
    [string]$Profile = 'quick',
    [switch]$AllowDirtyWorktree
)

$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:GateResults = [Collections.Generic.List[object]]::new()

function Get-QualityGateMutexName([string]$RepoRoot) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(([System.IO.Path]::GetFullPath($RepoRoot)).ToLowerInvariant())
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    return "Local\skills-manager-quality-gate-$($hash.Substring(0, 24))"
}

function Get-OlderQualityGateProcesses {
    $current = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $PID)
    $currentStarted = if ($current.CreationDate -is [datetime]) { [datetime]$current.CreationDate } else { [Management.ManagementDateTimeConverter]::ToDateTime([string]$current.CreationDate) }
    return @(Get-CimInstance Win32_Process | Where-Object {
        $_.ProcessId -ne $PID -and
        $_.Name -eq 'pwsh.exe' -and
        $_.CommandLine -notmatch '(?i)\s-Command\s' -and
        $_.CommandLine -match '(?i)-File\s+"?[^"\s]*run-local-quality-gates\.ps1' -and
        $(if ($_.CreationDate -is [datetime]) { [datetime]$_.CreationDate } else { [Management.ManagementDateTimeConverter]::ToDateTime([string]$_.CreationDate) }) -lt $currentStarted
    })
}

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

$mutex = [System.Threading.Mutex]::new($false, (Get-QualityGateMutexName $root))
$mutexAcquired = $false
try {
    try { $mutexAcquired = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $mutexAcquired = $true }
    if (-not $mutexAcquired) {
        [Console]::Error.WriteLine('quality_gate_peer_busy: another quality gate owns this repository')
        exit 75
    }
    $olderPeers = @(Get-OlderQualityGateProcesses)
    if ($olderPeers.Count -gt 0) {
        [Console]::Error.WriteLine(("quality_gate_peer_busy: older gate pid={0}" -f (($olderPeers.ProcessId | Sort-Object) -join ',')))
        exit 75
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
    Invoke-QualityGate 'workspace-lock-parity' { & .\skills.ps1 verify-lock }
    Invoke-QualityGate 'skill-integrity' { & .\scripts\verify-skill-integrity.ps1 }
    Invoke-QualityGate 'reference-governance' { & .\scripts\verify-reference-governance.ps1 }
    Invoke-QualityGate 'override-activation-corpus' { & .\scripts\verify-override-skill-activation.ps1 }
    Invoke-QualityGate 'native-skill-metadata' { & .\scripts\verify-native-skill-metadata.ps1 -Json }
    Invoke-QualityGate 'dependency-baseline' { & python .\scripts\verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline }
    Invoke-QualityGate 'skills-config-contract' { & .\scripts\verify-skills-config.ps1 -Mode enforce }
    Invoke-QualityGate 'host-capability-contract' { & .\scripts\verify-host-capability-matrix.ps1 }
    Invoke-QualityGate 'planning-contract' { & .\scripts\verify-vnext-planning.ps1 }
    Invoke-QualityGate 'host-native-lifecycle-planning' { & .\scripts\verify-host-native-skill-lifecycle-planning.ps1 }
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
}
finally {
    if ($mutexAcquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
