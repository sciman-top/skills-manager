BeforeAll {
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $fixture = Join-Path $repoRoot 'tests/fixtures/ai-coding-workflow'
    $runner = Join-Path $fixture 'Test-Labels.ps1'
    $runnerPath = Join-Path $repoRoot 'tests/run.ps1'

    function Invoke-LabelProbe([string]$ScriptRoot, [string[]]$Arguments = @()) {
        $output = & $pwshPath -NoProfile -File (Join-Path $ScriptRoot 'Test-Labels.ps1') @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $receiptLine = @($output | ForEach-Object { [string]$_ }) | Where-Object { $_ -like 'receipt=*' } | Select-Object -Last 1
        if (-not $receiptLine) { throw ("Label probe did not report a receipt path: {0}" -f ($output -join "`n")) }
        $receiptPath = $receiptLine.Substring('receipt='.Length).Trim()
        try {
            $receipt = Get-Content -LiteralPath $receiptPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        finally {
            if (Test-Path -LiteralPath $receiptPath -PathType Leaf) { Remove-Item -LiteralPath $receiptPath -Force }
        }
        return [pscustomobject]@{ exit_code = $exitCode; output = @($output); receipt = $receipt }
    }
}

Describe 'Reusable AI coding acceptance fixture' {
    It 'keeps the checked-in baseline defective and detects its case comparison failure' {
        $source = Join-Path $fixture 'Labels.ps1'
        $before = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $fixtureCopy = Join-Path $TestDrive 'baseline-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        $result = Invoke-LabelProbe $fixtureCopy
        $result.exit_code | Should -Be 1
        ($result.output -join "`n") | Should -Match 'FAIL case-and-trim:'
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'accepts a conforming implementation supplied from a disposable directory' {
        $fixtureCopy = Join-Path $TestDrive 'disposable-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        $temporaryValues = @(
            [pscustomobject]@{ Name = 'TEMP'; Value = $env:TEMP }
            [pscustomobject]@{ Name = 'TMP'; Value = $env:TMP }
        )
        try {
            $hostRoot = Join-Path $TestDrive 'host-temp'
            $privateTemp = Join-Path $hostRoot 'private'
            $missingTemp = Join-Path $hostRoot 'missing'
            New-Item -ItemType Directory -Path $privateTemp, $missingTemp -Force | Out-Null
            $env:TEMP = $privateTemp
            $env:TMP = $missingTemp
            $implementation = @'
function Get-NormalizedLabels {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Labels)
    $result = @()
    foreach ($label in $Labels) {
        if ([string]::IsNullOrWhiteSpace($label)) { continue }
        $value = $label.Trim()
        $duplicate = $false
        foreach ($previous in $result) {
            if ([StringComparer]::OrdinalIgnoreCase.Equals($previous, $value)) {
                $duplicate = $true
                break
            }
        }
        if (-not $duplicate) { $result += $value }
    }
    $result
}

function New-LabelFile {
    param([string]$Path, [string[]]$Labels)
    [IO.File]::WriteAllLines($Path, [string[]]@($Labels), [Text.UTF8Encoding]::new($false))
}

function Remove-LabelFile {
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Force
}
'@
            $implementation = $implementation.TrimStart("`r", "`n")
            [IO.File]::WriteAllText((Join-Path $fixtureCopy 'Labels.ps1'), $implementation, [Text.UTF8Encoding]::new($false))
            $result = Invoke-LabelProbe $fixtureCopy
            $output = $result.output
            $result.exit_code | Should -Be 0
            ($output -join "`n") | Should -Match 'cases=11 failed=0'
            ($output -join "`n") | Should -Match 'generated_ok=1 cleanup_ok=1 shared_dir=0'
            @(Get-ChildItem -LiteralPath $fixtureCopy -Directory -Filter 'probe-*').Count | Should -Be 0
            @(Get-ChildItem -LiteralPath $missingTemp -Force).Count | Should -Be 0
            $result.receipt.source_sha256 | Should -Be (Get-FileHash -LiteralPath (Join-Path $fixtureCopy 'Labels.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        finally {
            foreach ($temporaryValue in $temporaryValues) {
                [Environment]::SetEnvironmentVariable($temporaryValue.Name, $temporaryValue.Value, 'Process')
            }
        }
    }

    It 'rejects a hardcoded answer that only satisfies the demonstrated failing example' {
        $fixtureCopy = Join-Path $TestDrive 'hardcoded-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        $source = Join-Path $fixtureCopy 'Labels.ps1'
        'function Get-NormalizedLabels { param($Labels) @("Alpha", "BETA") }' |
            Set-Content -LiteralPath $source -Encoding utf8
        $result = Invoke-LabelProbe $fixtureCopy
        $output = $result.output
        $result.exit_code | Should -Be 1
        ($output -join "`n") | Should -Match 'FAIL empty:'
        ($output -join "`n") | Should -Match 'FAIL order:'
    }

    It 'classifies missing input separately from a candidate execution failure' {
        $fixtureCopy = Join-Path $TestDrive 'missing-input-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        Remove-Item -LiteralPath (Join-Path $fixtureCopy 'Labels.ps1')
        $result = Invoke-LabelProbe $fixtureCopy
        $result.exit_code | Should -Be 1
        $result.receipt.failure_kind | Should -Be 'missing_input'
        $result.receipt.observed_probes[0].status | Should -Be 'failed'
    }

    It 'does not report cleanup when deleting the generated file fails' {
        $fixtureCopy = Join-Path $TestDrive 'cleanup-failure-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        $implementation = @'
function Get-NormalizedLabels {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Labels)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($label in $Labels) {
        if (-not [string]::IsNullOrWhiteSpace($label) -and $seen.Add($label.Trim())) { $label.Trim() }
    }
}
function New-LabelFile { param([string]$Path, [string[]]$Labels) [IO.File]::WriteAllLines($Path, [string[]]$Labels) }
function Remove-LabelFile { param([string]$Path) throw 'simulated cleanup failure' }
'@
        [IO.File]::WriteAllText((Join-Path $fixtureCopy 'Labels.ps1'), $implementation, [Text.UTF8Encoding]::new($false))
        $result = Invoke-LabelProbe $fixtureCopy
        $result.exit_code | Should -Be 1
        ($result.output -join "`n") | Should -Match 'cases=11 failed=1'
        ($result.output -join "`n") | Should -Match 'generated_ok=1 cleanup_ok=0'
        $result.receipt.status | Should -Be 'failed'
        $result.receipt.failed_count | Should -Be 1
    }

    It 'reports a missing implementation as input failure rather than an accepted probe' {
        $fixtureCopy = Join-Path $TestDrive 'probe-missing-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        Remove-Item -LiteralPath (Join-Path $fixtureCopy 'Labels.ps1')
        $result = Invoke-LabelProbe $fixtureCopy
        $result.exit_code | Should -Be 1
        ($result.output -join "`n") | Should -Match 'There is no Labels.ps1'
        $result.receipt.status | Should -Be 'failed'
        $result.receipt.observed_probes.Count | Should -Be 1
        $result.receipt.observed_probes[0].status | Should -Be 'failed'
        $result.receipt.discovered_candidate.callable | Should -BeFalse
    }

    It 'reports an implementation outside the disposable fixture as an evaluator failure' {
        $fixtureCopy = Join-Path $TestDrive 'probe-skip-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        $externalSource = Join-Path $TestDrive 'ExternalLabels.ps1'
        $implementation = @'
function Get-NormalizedLabels {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Labels)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($label in $Labels) {
        if (-not [string]::IsNullOrWhiteSpace($label) -and $seen.Add($label.Trim())) { $label.Trim() }
    }
}
function New-LabelFile { param([string]$Path, [string[]]$Labels) [IO.File]::WriteAllLines($Path, [string[]]$Labels) }
function Remove-LabelFile { param([string]$Path) Remove-Item -LiteralPath $Path -Force }
'@
        [IO.File]::WriteAllText($externalSource, $implementation, [Text.UTF8Encoding]::new($false))
        $result = Invoke-LabelProbe $fixtureCopy @('-SourcePath', $externalSource, '-ProbeDirectory', (Join-Path $TestDrive 'runtime-probe'))
        $result.exit_code | Should -Be 1
        ($result.output -join "`n") | Should -Match 'Acceptance source must be in the disposable fixture root'
        $result.receipt.failure_kind | Should -Be 'evaluator'
        $result.receipt.source_path | Should -Be $externalSource
        $result.receipt.discovered_candidate.callable | Should -BeFalse
        $result.receipt.observed_probes[0].status | Should -Be 'failed'
    }

    It 'records an evaluator failure when a source load interrupts the run' {
        $fixtureCopy = Join-Path $TestDrive 'probe-unreached-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        $result = Invoke-LabelProbe $fixtureCopy @('-SourcePath', (Join-Path $TestDrive 'missing.ps1'))
        $result.exit_code | Should -Be 1
        $result.receipt.status | Should -Be 'failed'
        $result.receipt.observed_probes.Count | Should -Be 1
        $result.receipt.observed_probes[0].status | Should -Be 'failed'
    }

    It 'records fresh failed receipts when source loading fails' {
        $fixtureCopy = Join-Path $TestDrive 'probe-repeat-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        $passingSource = Join-Path $fixtureCopy 'Labels.ps1'
        $implementation = @'
function Get-NormalizedLabels {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Labels)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($label in $Labels) {
        if (-not [string]::IsNullOrWhiteSpace($label) -and $seen.Add($label.Trim())) { $label.Trim() }
    }
}
function New-LabelFile { param([string]$Path, [string[]]$Labels) [IO.File]::WriteAllLines($Path, [string[]]$Labels) }
function Remove-LabelFile { param([string]$Path) Remove-Item -LiteralPath $Path -Force }
'@
        [IO.File]::WriteAllText($passingSource, $implementation.TrimStart("`r", "`n"), [Text.UTF8Encoding]::new($false))
        $firstResult = Invoke-LabelProbe $fixtureCopy @('-SourcePath', $passingSource)
        $firstResult.exit_code | Should -Be 0
        $firstResult.receipt.status | Should -Be 'passed'
        Remove-Item -LiteralPath $passingSource
        $lateResult = Invoke-LabelProbe $fixtureCopy @('-SourcePath', (Join-Path $fixtureCopy 'missing.ps1'))
        $lateResult.exit_code | Should -Be 1
        $lateResult.receipt.source_path | Should -Be (Join-Path $fixtureCopy 'missing.ps1')
        $lateResult.receipt.status | Should -Be 'failed'
        $lateResult.receipt.observed_probes[0].status | Should -Be 'failed'
    }

    It 'does not lose later test paths or report a partial selection as complete' {
        $batchRoot = Join-Path $TestDrive 'batch'
        New-Item -ItemType Directory -Path $batchRoot -Force | Out-Null
        $firstTest = Join-Path $batchRoot 'First.Tests.ps1'
        $secondTest = Join-Path $batchRoot 'Second.Tests.ps1'
        @'
Describe 'First selected test' {
    It 'runs' { $true | Should -BeTrue }
}
'@ | Set-Content -LiteralPath $firstTest -Encoding utf8
        @'
Describe 'Second selected test' {
    It 'runs' { $true | Should -BeTrue }
}
'@ | Set-Content -LiteralPath $secondTest -Encoding utf8
        $reportRoot = Join-Path $TestDrive ('ai-coding-batch-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
        try {
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $pwshPath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            foreach ($argument in @('-NoProfile', '-File', $runnerPath, '-TestPath', $firstTest, '-SplitTestPath', $secondTest, '-InProcess', '-ShardReportRoot', $reportRoot)) {
                $startInfo.ArgumentList.Add($argument)
            }
            $process = [Diagnostics.Process]::Start($startInfo)
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            $output = @($stdout.Result, $stderr.Result) -join "`n"
            $process.Dispose()
            $receipt = @(Get-ChildItem -LiteralPath $reportRoot -Recurse -Filter 'targeted.receipt.json' -File) | ForEach-Object {
                Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            } | Where-Object { $_.status -ne 'error' }
            $exitCode | Should -Be 0
            @($receipt).Count | Should -Be 1
            $receipt.total_count | Should -Be 2
            $output | Should -Match 'Tests: total=2 passed=2 failed=0'
        }
        finally {
            if (Test-Path -LiteralPath $reportRoot) {
                Remove-Item -LiteralPath $reportRoot -Recurse -Force
            }
        }
    }

    It 'reports cleanup only after removing the generated file without deleting a caller directory' {
        $root = Join-Path $TestDrive 'cleanup-check'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $probe = Join-Path $root 'caller-owned'
        $fixtureCopy = Join-Path $root 'disposable-fixture'
        $source = Join-Path $fixtureCopy 'Labels.ps1'
        New-Item -ItemType Directory -Path $probe -Force | Out-Null
        $callerMarker = Join-Path $probe 'keep.me'
        [IO.File]::WriteAllText($callerMarker, 'caller-owned', [Text.UTF8Encoding]::new($false))
        New-Item -ItemType Directory -Path $fixtureCopy -Force | Out-Null
        Copy-Item -Path (Join-Path $fixture '*') -Destination $fixtureCopy -Recurse
        $runner = Join-Path $fixtureCopy 'Test-Labels.ps1'
        Copy-Item -LiteralPath (Join-Path $fixture 'old-cleanup/Labels.ps1') -Destination $source
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        try {
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $pwshPath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            foreach ($argument in @('-NoProfile', '-File', (Join-Path $fixtureCopy 'Test-Labels.ps1'), '-ProbeDirectory', $probe)) {
                $startInfo.ArgumentList.Add($argument)
            }
            $process = [Diagnostics.Process]::Start($startInfo)
            try {
                $stdout = $process.StandardOutput.ReadToEndAsync()
                $stderr = $process.StandardError.ReadToEndAsync()
                $process.WaitForExit()
                $exitCode = $process.ExitCode
                $output = @($stdout.Result, $stderr.Result) -join "`n"
            }
            finally { $process.Dispose() }

            $exitCode | Should -Be 1
            $output | Should -Match 'FAIL case-and-trim:'
            $output | Should -Match 'generated_ok=1 cleanup_ok=1 shared_dir=1'
            Get-Content -LiteralPath $callerMarker -Raw | Should -Be 'caller-owned'
            Test-Path -LiteralPath (Join-Path $probe 'labels.txt') | Should -BeFalse
            (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash | Should -Be $sourceHash
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
