BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
    $script:Hook = Join-Path $script:RepoRoot 'scripts\guard-stop-verification.ps1'
    $script:PwshPath = (Get-Process -Id $PID).Path
    function Invoke-StopGuard([string]$Json, [string]$TargetRepo = '') {
        $eventPath = Join-Path ([IO.Path]::GetTempPath()) ('stope-' + [guid]::NewGuid().ToString('N') + '.json')
        $outPath = $eventPath + '.out'
        $errPath = $eventPath + '.err'
        try {
            Set-Content -LiteralPath $eventPath -Value $Json -Encoding utf8 -NoNewline
            $argList = [System.Collections.Generic.List[string]]::new()
            $argList.Add('-NoProfile')
            $argList.Add('-File')
            $argList.Add($script:Hook)
            if (-not [string]::IsNullOrWhiteSpace($TargetRepo)) {
                $argList.Add('-RepoRoot')
                $argList.Add($TargetRepo)
            }
            $process = Start-Process -FilePath $script:PwshPath -ArgumentList $argList `
                -RedirectStandardInput $eventPath -RedirectStandardOutput $outPath -RedirectStandardError $errPath -NoNewWindow -PassThru -Wait
            $stdout = if (Test-Path -LiteralPath $outPath) { [IO.File]::ReadAllText($outPath) } else { '' }
            $stderr = if (Test-Path -LiteralPath $errPath) { [IO.File]::ReadAllText($errPath) } else { '' }
            return [pscustomobject]@{
                exit_code = $process.ExitCode
                stdout    = $stdout
                stderr    = $stderr
                output    = (($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
            }
        }
        finally {
            Remove-Item -LiteralPath $eventPath, $outPath, $errPath -ErrorAction SilentlyContinue
        }
    }
    function New-StopEvent([string]$Message, [bool]$Active = $false) {
        return (@{ stop_hook_active = $Active; last_assistant_message = $Message } | ConvertTo-Json -Compress)
    }

    $script:FixtureRepo = Join-Path $TestDrive 'stop-guard-repo'
    New-Item -ItemType Directory -Path $script:FixtureRepo -Force | Out-Null
    & git init --template= $script:FixtureRepo *> $null
    @'
param([switch]$Check)
if ($Check -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'drift.flag'))) {
    Write-Output 'simulated generated drift'
    exit 1
}
exit 0
'@ | Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'build.ps1') -Encoding utf8
    Set-Content -LiteralPath (Join-Path $script:FixtureRepo '.gitignore') -Value "build.ps1`n.gitignore`ndrift.flag`n" -Encoding utf8
}

Describe 'Stop guard is registered for Codex' {
    It 'declares a Stop hook with a cmd-safe argv path to the shared verification guard' {
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.codex\config.toml') -Raw
        $config | Should -Match '(?m)^\[\[hooks\.Stop\]\]'
        $stopBlock = [regex]::Match($config, '(?s)\[\[hooks\.Stop\]\].*$').Value
        $commands = @([regex]::Matches($stopBlock, "(?m)^(?:command|command_windows) = '(?<c>[^']*)'") | ForEach-Object { $_.Groups['c'].Value })
        $commands.Count | Should -Be 2
        foreach ($commandLine in $commands) {
            $commandLine | Should -Match 'scripts/guard-stop-verification\.ps1$'
            $commandLine | Should -Not -Match '\$\(git rev-parse'
        }
        Test-Path -LiteralPath $script:Hook | Should -BeTrue
    }

    It 'requires a bounded timeout so the stop path cannot hang the turn' {
        # 用 `\r?$` 而不是 `$`：仓库按 .gitattributes 在 Windows 检出为 CRLF，
        # 只写 `$` 时行尾的 \r 会让断言在 CI 上失败而本地通过。
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.codex\config.toml') -Raw
        $stopBlock = [regex]::Match($config, '(?s)\[\[hooks\.Stop\]\].*$').Value
        $timeout = [regex]::Match($stopBlock, '(?m)^timeout = (?<t>\d+)\r?$')
        $timeout.Success | Should -BeTrue
        [int]$timeout.Groups['t'].Value | Should -BeLessOrEqual 600
    }
}

Describe 'Stop guard fails open on input it cannot interpret' {
    It 'allows malformed JSON' {
        (Invoke-StopGuard 'not json').exit_code | Should -Be 0
    }

    It 'fails open on empty stdin even when the target worktree is dirty and drifted' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt') -Value 'changed' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'drift.flag') -Value '1' -Encoding utf8
        try {
            (Invoke-StopGuard '' $script:FixtureRepo).exit_code | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt'), (Join-Path $script:FixtureRepo 'drift.flag') -Force -ErrorAction SilentlyContinue
        }
    }

    It 'allows a turn that this hook already continued' {
        # Without this the hook loops: every continuation would re-trigger it.
        (Invoke-StopGuard (New-StopEvent 'anything' $true)).exit_code | Should -Be 0
    }

    It 'returns without waiting for stdin EOF when the host keeps the pipe open' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt') -Value 'changed' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'drift.flag') -Value '1' -Encoding utf8
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $script:PwshPath
        $psi.ArgumentList.Add('-NoProfile')
        $psi.ArgumentList.Add('-File')
        $psi.ArgumentList.Add($script:Hook)
        $psi.ArgumentList.Add('-RepoRoot')
        $psi.ArgumentList.Add($script:FixtureRepo)
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($psi)
        try {
            $process.StandardInput.Write((New-StopEvent '已修改完成'))
            $process.StandardInput.Flush()
            ($process.WaitForExit(30000)) | Should -BeTrue -Because 'the stop guard must not block on an open stdin pipe'
            $process.ExitCode | Should -Be 0
        }
        finally {
            if (-not $process.HasExited) { $process.Kill($true) }
            $process.Dispose()
            Remove-Item -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt'), (Join-Path $script:FixtureRepo 'drift.flag') -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Stop guard evaluates worktree drift and verification evidence' {
    BeforeEach {
        Remove-Item -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt'), (Join-Path $script:FixtureRepo 'drift.flag') -Force -ErrorAction SilentlyContinue
    }

    It 'allows a clean worktree even when the reply carries no verification section' {
        $result = Invoke-StopGuard (New-StopEvent '纯问答回复，无改动。') $script:FixtureRepo
        $result.exit_code | Should -Be 0
    }

    It 'blocks a dirty worktree when build.ps1 -Check reports generated drift' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt') -Value 'changed' -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'drift.flag') -Value '1' -Encoding utf8

        $result = Invoke-StopGuard (New-StopEvent '已完成验证，全部通过。') $script:FixtureRepo

        $result.exit_code | Should -Be 2
        $result.stderr | Should -Match 'build\.ps1 -Check failed'
        $result.stderr | Should -Match 'simulated generated drift'
    }

    It 'blocks a dirty worktree when the final message omits commands and verification markers' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt') -Value 'changed' -Encoding utf8

        $result = Invoke-StopGuard (New-StopEvent '已经改好了，请查收。') $script:FixtureRepo

        $result.exit_code | Should -Be 2
        $result.stderr | Should -Match 'Stop guard:'
    }

    It 'accepts inline Chinese verification wording without requiring spaces around CJK keywords' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt') -Value 'changed' -Encoding utf8

        (Invoke-StopGuard (New-StopEvent '已完成修改，验证结果：全部通过。') $script:FixtureRepo).exit_code | Should -Be 0
        (Invoke-StopGuard (New-StopEvent '已补充证据并确认退出码为 0。') $script:FixtureRepo).exit_code | Should -Be 0
    }

    It 'accepts a fenced command block or English verification marker on a dirty worktree' {
        Set-Content -LiteralPath (Join-Path $script:FixtureRepo 'dirty.txt') -Value 'changed' -Encoding utf8

        $fencedMessage = @'
Result:
```text
exit=0
```
'@
        (Invoke-StopGuard (New-StopEvent $fencedMessage) $script:FixtureRepo).exit_code | Should -Be 0
        (Invoke-StopGuard (New-StopEvent 'Verified with focused tests.') $script:FixtureRepo).exit_code | Should -Be 0
    }
}
