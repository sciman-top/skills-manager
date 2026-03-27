. $PSScriptRoot\..\..\skills.ps1

Describe "Git lock recovery" {
    Context "Get-GitLockPathFromOutputLine" {
        It "Extracts index.lock path from git stderr line" {
            $line = "fatal: Unable to create 'E:/repo/.git/index.lock': File exists."
            Get-GitLockPathFromOutputLine $line | Should Be "E:/repo/.git/index.lock"
        }

        It "Extracts index.lock path from unlink stderr line" {
            $line = "warning: unable to unlink 'E:/repo/.git/index.lock': Invalid argument"
            Get-GitLockPathFromOutputLine $line | Should Be "E:/repo/.git/index.lock"
        }
    }

    Context "Repair-StaleGitLockFromOutput" {
        It "Removes stale index.lock when no git process is running" {
            $repo = Join-Path $TestDrive "repo"
            $gitDir = Join-Path $repo ".git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            $lockPath = Join-Path $gitDir "index.lock"
            Set-Content -Path $lockPath -Value "stale"

            Mock Test-GitProcessRunning { $false }

            $repaired = Repair-StaleGitLockFromOutput @("fatal: Unable to create '$lockPath': File exists.")

            $repaired | Should Be $true
            (Test-Path $lockPath) | Should Be $false
        }

        It "Still removes lock when git process exists but file is removable" {
            $repo = Join-Path $TestDrive "repo2"
            $gitDir = Join-Path $repo ".git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            $lockPath = Join-Path $gitDir "index.lock"
            Set-Content -Path $lockPath -Value "active"

            Mock Test-GitProcessRunning { $true }

            $repaired = Repair-StaleGitLockFromOutput @("fatal: Unable to create '$lockPath': File exists.")

            $repaired | Should Be $true
            (Test-Path $lockPath) | Should Be $false
        }

        It "Throws only when lock cannot be removed and git process is still running" {
            $repo = Join-Path $TestDrive "repo2-busy"
            $gitDir = Join-Path $repo ".git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            $lockPath = Join-Path $gitDir "index.lock"
            Set-Content -Path $lockPath -Value "active"

            Mock Test-GitProcessRunning { $true }
            Mock Remove-GitLockFile { $false }

            $thrown = $false
            try {
                Repair-StaleGitLockFromOutput @("fatal: Unable to create '$lockPath': File exists.") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "git 进程"
            }
            $thrown | Should Be $true
            (Test-Path $lockPath) | Should Be $true
        }
    }

    Context "Git-HardResetClean" {
        It "Removes stale repo index.lock before git reset and clean" {
            $repo = Join-Path $TestDrive "repo3"
            $gitDir = Join-Path $repo ".git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            $lockPath = Join-Path $gitDir "index.lock"
            Set-Content -Path $lockPath -Value "stale"

            Mock Test-GitProcessRunning { $false }
            Mock Invoke-Git {}

            Push-Location $repo
            try {
                Git-HardResetClean $true
            }
            finally {
                Pop-Location
            }

            (Test-Path $lockPath) | Should Be $false
            Assert-MockCalled Invoke-Git -Times 1 -ParameterFilter { $GitArgs[0] -eq "reset" -and $GitArgs[1] -eq "--hard" }
            Assert-MockCalled Invoke-Git -Times 1 -ParameterFilter { $GitArgs[0] -eq "clean" -and $GitArgs[1] -eq "-fd" }
        }
    }

    Context "Repair-StaleGitLockAfterFailure" {
        It "Removes repo index.lock for write-new-index failures" {
            $repo = Join-Path $TestDrive "repo4"
            $gitDir = Join-Path $repo ".git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            $lockPath = Join-Path $gitDir "index.lock"
            Set-Content -Path $lockPath -Value "stale"

            Mock Test-GitProcessRunning { $false }

            $repaired = Repair-StaleGitLockAfterFailure $repo @(
                "warning: unable to unlink '$lockPath': Invalid argument"
                "fatal: Could not write new index file."
            )

            $repaired | Should Be $true
            (Test-Path $lockPath) | Should Be $false
        }
    }
}
