[CmdletBinding()]
param(
    [ValidateSet('quick', 'full')]
    [string]$Profile = 'quick',
    [switch]$AllowDirtyWorktree
)

$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $PSScriptRoot 'QualityGateIntegrity.ps1')
$script:GateResults = [Collections.Generic.List[object]]::new()
$script:QualityGateSourceStart = $null

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
        if ($null -ne $script:QualityGateSourceStart) {
            $checkpoint = Get-QualityGateSourceFingerprint -RepoRoot $root
            $checkpointComparison = Compare-QualityGateSourceFingerprint -Start $script:QualityGateSourceStart -End $checkpoint
            if (-not $checkpointComparison.pass) {
                throw ("Quality gate source drift after {0}: {1}" -f $Name, (($checkpointComparison.changed_fields) -join ', '))
            }
        }
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
    $runId = 'qgr-{0}-{1}' -f ([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $timingReportPath = Join-Path $root ('reports\test-timings\{0}.json' -f $runId)
    $startedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $sourceStart = $null
    $sourceEnd = $null
    $runStatus = 'failed'
    $runExitCode = 1
    $runError = ''
    $sourceStart = Get-QualityGateSourceFingerprint -RepoRoot $root
    $script:QualityGateSourceStart = $sourceStart
        try {
            Invoke-QualityGate 'build' { & .\build.ps1 }
            if ($Profile -eq 'full') {
                $sourceStartJson = $sourceStart | ConvertTo-Json -Depth 10 -Compress
                Invoke-QualityGate 'tests' { & .\tests\run.ps1 -TimingReportPath $timingReportPath -QualityGateRunId $runId -QualityGateSourceFingerprintJson $sourceStartJson }
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
            Invoke-QualityGate 'native-skill-metadata' { & .\scripts\verify-native-skill-metadata.ps1 }
            Invoke-QualityGate 'dependency-baseline' { & python .\scripts\verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline }
            Invoke-QualityGate 'skills-config-contract' { & .\scripts\verify-skills-config.ps1 -Mode enforce }
            Invoke-QualityGate 'host-capability-contract' { & .\scripts\verify-host-capability-matrix.ps1 }
            Invoke-QualityGate 'planning-contract' { & .\scripts\verify-vnext-planning.ps1 }
            Invoke-QualityGate 'host-native-lifecycle-planning' { & .\scripts\verify-host-native-skill-lifecycle-planning.ps1 }
            Invoke-QualityGate 'powershell-runtime-policy' { & .\scripts\verify-powershell-runtime-policy.ps1 }
            Invoke-QualityGate 'agent-workflow-advisory' { & .\scripts\verify-agent-workflow-advisory.ps1 }
            Invoke-QualityGate 'doctor-json-contract' { & .\scripts\quality\check-doctor-json.ps1 }
            $runStatus = 'passed'
            $runExitCode = 0
        }
        catch {
            $runError = $_.Exception.Message
            [Console]::Error.WriteLine(('quality_gate_failed: {0}' -f $runError))
        }
        finally {
            try { $sourceEnd = Get-QualityGateSourceFingerprint -RepoRoot $root }
            catch {
                $runStatus = 'terminal_evidence_unavailable'
                $runExitCode = 1
                $runError = ('Unable to capture end source fingerprint: {0}' -f $_.Exception.Message)
                [Console]::Error.WriteLine(('quality_gate_receipt_unavailable: {0}' -f $runError))
            }
        }

        if ($null -ne $sourceStart -and $null -ne $sourceEnd) {
            $sourceComparison = Compare-QualityGateSourceFingerprint -Start $sourceStart -End $sourceEnd
            if (-not $sourceComparison.pass) {
                $runStatus = 'source_drift'
                $runExitCode = 78
                $runError = ('Source drift detected during quality gate: {0}' -f (($sourceComparison.changed_fields) -join ', '))
                [Console]::Error.WriteLine(('quality_gate_source_drift: {0}' -f (($sourceComparison.changed_fields) -join ', ')))
            }
        }

        Write-Host ""
        $totalElapsed = [long](($script:GateResults | Measure-Object -Property elapsed_ms -Sum).Sum)
        Write-Host ("Gate summary: {0}; total_elapsed_ms={1}" -f (($script:GateResults | ForEach-Object { '{0}={1}ms' -f $_.name, $_.elapsed_ms }) -join ', '), $totalElapsed)
        if ($null -ne $sourceStart -and $null -ne $sourceEnd) {
            try {
                $boundTimingReportPath = if ($Profile -eq 'full' -and (Test-Path -LiteralPath $timingReportPath -PathType Leaf)) { $timingReportPath } else { '' }
                $receipt = Write-QualityGateImmutableReceipt -ReceiptRoot (Join-Path $root 'reports\quality-gates') -RunId $runId -Profile $Profile -Status $runStatus -SourceStart $sourceStart -SourceEnd $sourceEnd -GateResults @($script:GateResults.ToArray()) -StartedAt $startedAt -CompletedAt ([DateTimeOffset]::UtcNow.ToString('o')) -AllowDirtyWorktree ([bool]$AllowDirtyWorktree) -ErrorMessage $runError -TimingReportPath $boundTimingReportPath
                Write-Host ("quality_gate_receipt={0}; quality_gate_pointer={1}" -f $receipt.receipt_path, $receipt.pointer_path)
            }
            catch {
                $runExitCode = 1
                $runStatus = 'terminal_evidence_unavailable'
                $runError = ('Unable to write immutable quality gate receipt: {0}' -f $_.Exception.Message)
                [Console]::Error.WriteLine(('quality_gate_receipt_unavailable: {0}' -f $runError))
            }
        }
        if ($runExitCode -eq 0) {
            Write-Host ("Local quality gates passed ({0})." -f $Profile)
        }
        else {
            Write-Host ("Local quality gates stopped: status={0}." -f $runStatus)
        }
    if ($runExitCode -ne 0) { exit $runExitCode }
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($mutexAcquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
