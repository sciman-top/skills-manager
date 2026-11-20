BeforeAll {
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $fixture = Join-Path $repoRoot 'tests/fixtures/ai-coding-workflow'
    $runner = Join-Path $fixture 'Test-Labels.ps1'
    $runnerPath = Join-Path $repoRoot 'tests/run.ps1'
}

Describe 'Reusable AI coding acceptance fixture' {
    It 'keeps the checked-in baseline defective and detects its case comparison failure' {
        $source = Join-Path $fixture 'Labels.ps1'
        $before = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $output = & $pwshPath -NoProfile -File $runner 2>&1
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 1
        ($output -join "`n") | Should -Match 'FAIL case-and-trim:'
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'accepts a conforming implementation supplied from a disposable directory' {
        $source = Join-Path $TestDrive 'Labels.ps1'
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
        [IO.File]::WriteAllText($source, $implementation, [Text.UTF8Encoding]::new($false))
        $output = & $pwshPath -NoProfile -File $runner -SourcePath $source 2>&1
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 0
        ($output -join "`n") | Should -Match 'cases=11 failed=0'
        ($output -join "`n") | Should -Match 'generated_ok=1 cleanup_ok=1 shared_dir=0'
    }

    It 'rejects a hardcoded answer that only satisfies the demonstrated failing example' {
        $source = Join-Path $TestDrive 'Hardcoded.ps1'
        'function Get-NormalizedLabels { param($Labels) @("Alpha", "BETA") }' |
            Set-Content -LiteralPath $source -Encoding utf8
        $output = & $pwshPath -NoProfile -File $runner -SourcePath $source
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 1
        ($output -join "`n") | Should -Match 'FAIL empty:'
        ($output -join "`n") | Should -Match 'FAIL order:'
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
        $reportRoot = Join-Path ([IO.Path]::GetTempPath()) ('ai-coding-batch-' + [guid]::NewGuid().ToString('N'))
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
        $root = Join-Path ([IO.Path]::GetTempPath()) ('ai-coding-cleanup-check-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $probe = Join-Path $root 'caller-owned'
        $source = Join-Path $root 'Labels.ps1'
        New-Item -ItemType Directory -Path $probe -Force | Out-Null
        $callerMarker = Join-Path $probe 'keep.me'
        [IO.File]::WriteAllText($callerMarker, 'caller-owned', [Text.UTF8Encoding]::new($false))
        Copy-Item -LiteralPath (Join-Path $fixture 'old-cleanup/Labels.ps1') -Destination $source
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        try {
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $pwshPath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            foreach ($argument in @('-NoProfile', '-File', $runner, '-SourcePath', $source, '-ProbeDirectory', $probe)) {
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
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}
