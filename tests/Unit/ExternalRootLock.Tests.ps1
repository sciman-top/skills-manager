BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $script:lockScript = Join-Path $repoRoot 'scripts\lock-external-repos.ps1'
    $script:pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    # 真实外置根的 ACL 动作只属于用户显式授权的维护窗口;本套件一律用 TestDrive 夹具。
    $script:guardedExternalRoot = 'D:\CODE\external'

    function New-LockFixture {
        param([Parameter(Mandatory)][string]$Root)
        $fixture = Join-Path $Root ('external-' + [Guid]::NewGuid().ToString('N'))
        $nested = Join-Path $fixture 'shelf\repo'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $nested 'artifact.txt'), 'reference payload')
        if ($fixture.StartsWith($script:guardedExternalRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "fixture must never be the protected external root: $fixture"
        }
        $fixture
    }

    function Get-ExternalDenyRights {
        [Security.AccessControl.FileSystemRights]::Write -bor
        [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles
    }

    function Add-ExternalDenyAce {
        # 与生产脚本同口径:标识符写 $env:USERNAME,读回时由 OS 解析成 机器\用户。
        param([Parameter(Mandatory)][string]$Path, [switch]$Inherit)
        $inheritance = if ($Inherit) {
            [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [Security.AccessControl.InheritanceFlags]::ObjectInherit
        }
        else { [Security.AccessControl.InheritanceFlags]::None }
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $env:USERNAME, (Get-ExternalDenyRights), $inheritance,
            [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Deny)
        $acl = Get-Acl -LiteralPath $Path
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $acl
    }

    function Test-FixtureRootDenyAce {
        # 复刻 lock-external-repos.ps1 Test-ExternalRootLockAce 的判定口径。
        param([Parameter(Mandatory)][string]$Path)
        @((Get-Acl -LiteralPath $Path).Access | Where-Object {
                $_.AccessControlType -eq 'Deny' -and -not $_.IsInherited -and
                ((([string]$_.IdentityReference.Value) -eq $env:USERNAME) -or
                    (([string]$_.IdentityReference.Value) -like "*\$env:USERNAME"))
            }).Count -gt 0
    }

    function Test-FixtureResidualDenyAce {
        # 复刻 lock-external-repos.ps1 Test-ExternalResidualDenyPath 的判定口径。
        param([Parameter(Mandatory)][string]$Path)
        $account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        @((Get-Acl -LiteralPath $Path).Access | Where-Object {
                $_.AccessControlType -eq 'Deny' -and [string]$_.IdentityReference.Value -eq $account
            }).Count -gt 0
    }

    function Invoke-LockScript {
        # 脚本以 exit/throw 结束,必须在子进程里跑才能同时拿到输出与退出码。
        param([Parameter(Mandatory)][string[]]$Arguments)
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $script:pwshPath
        foreach ($argument in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:lockScript) + $Arguments) {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $process.Dispose()
        [pscustomobject]@{
            exit_code = $exitCode
            stdout    = $stdout
            stderr    = $stderr
            text      = $stdout + "`n" + $stderr
        }
    }

    function Reset-FixtureAcl {
        # 夹具可能带本账号的 deny;TestDrive 删除前必须先还原,否则 Pester 清理失败。
        param([Parameter(Mandatory)][string]$Path)
        $probe = Join-Path $Path ('.acl-cleanup-probe-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
        $null = & icacls $Path /reset /T /C /Q
        try {
            [IO.File]::WriteAllText($probe, 'probe')
            Remove-Item -LiteralPath $probe -Force
            $true
        }
        catch {
            if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
            $false
        }
    }
}

Describe 'External root lock maintenance' -Skip:(-not $IsWindows) {
    BeforeEach {
        $script:fixture = New-LockFixture -Root $TestDrive
    }

    AfterEach {
        if (-not $script:fixture -or -not (Test-Path -LiteralPath $script:fixture)) { return }
        if (-not (Reset-FixtureAcl -Path $script:fixture)) {
            Write-Warning "fixture ACL cleanup probe failed: $($script:fixture)"
        }
    }

    It 'Reports an unlocked fixture root as writable' {
        $status = Invoke-LockScript -Arguments @('-Status', '-ExternalRoot', $script:fixture)

        $status.exit_code | Should -Be 0
        $status.stdout | Should -Match 'locked=False'
        $status.stdout | Should -Match 'topLevelWriteProbes=1'
        $status.stdout | Should -Match 'probeFailures=0'
    }

    It 'Reports a locked fixture root as locked and deep status as self-consistent' {
        Add-ExternalDenyAce -Path $script:fixture -Inherit
        if (-not (Test-FixtureRootDenyAce -Path $script:fixture)) {
            Set-ItResult -Skipped -Because 'deny ACE did not materialize for the current account on this host'
            return
        }

        $status = Invoke-LockScript -Arguments @('-Status', '-ExternalRoot', $script:fixture)
        $deep = Invoke-LockScript -Arguments @('-Status', '-Deep', '-ExternalRoot', $script:fixture)

        $status.exit_code | Should -Be 0
        $status.stdout | Should -Match 'locked=True'
        $deep.exit_code | Should -Be 0
        $deep.stdout | Should -Match 'status self-consistent: locked root'
    }

    It 'Sees residual descendant deny ACEs only in deep status' {
        $nestedFile = Join-Path $script:fixture 'shelf\repo\artifact.txt'
        Add-ExternalDenyAce -Path $nestedFile
        if (-not (Test-FixtureResidualDenyAce -Path $nestedFile)) {
            Set-ItResult -Skipped -Because 'deny ACE did not materialize for the current account on this host'
            return
        }

        $shallow = Invoke-LockScript -Arguments @('-Status', '-ExternalRoot', $script:fixture)
        $deep = Invoke-LockScript -Arguments @('-Status', '-Deep', '-ExternalRoot', $script:fixture)

        $shallow.exit_code | Should -Be 0
        $shallow.stdout | Should -Match 'probeFailures=0'
        $deep.exit_code | Should -Be 1
        $deep.stdout | Should -Match 'residualDenyPaths=1'
        $deep.stdout | Should -Match 'status inconsistent'
    }

    It 'Clears a residual descendant deny ACE during unlock' {
        $nestedFile = Join-Path $script:fixture 'shelf\repo\artifact.txt'
        Add-ExternalDenyAce -Path $nestedFile
        if (-not (Test-FixtureResidualDenyAce -Path $nestedFile)) {
            Set-ItResult -Skipped -Because 'deny ACE did not materialize for the current account on this host'
            return
        }

        $unlock = Invoke-LockScript -Arguments @('-Unlock', '-ExternalRoot', $script:fixture)
        $deep = Invoke-LockScript -Arguments @('-Status', '-Deep', '-ExternalRoot', $script:fixture)

        $unlock.exit_code | Should -Be 0
        $unlock.stdout | Should -Match 'UNLOCKED'
        $unlock.stdout | Should -Match 'residual deny paths=0'
        Test-FixtureResidualDenyAce -Path $nestedFile | Should -BeFalse
        $deep.exit_code | Should -Be 0
        $deep.stdout | Should -Match 'residualDenyPaths=0'
    }

    It 'Rejects conflicting or orphaned switches' {
        $both = Invoke-LockScript -Arguments @('-Unlock', '-Status', '-ExternalRoot', $script:fixture)
        $orphan = Invoke-LockScript -Arguments @('-Deep', '-ExternalRoot', $script:fixture)

        $both.exit_code | Should -Be 1
        $both.text | Should -Match 'Use either -Unlock or -Status, not both'
        $orphan.exit_code | Should -Be 1
        $orphan.text | Should -Match '-Deep only applies to -Status'
    }
}
