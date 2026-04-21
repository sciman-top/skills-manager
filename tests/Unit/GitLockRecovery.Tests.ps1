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

        It "Retries git clean after repairing permission denied paths" {
            $repo = Join-Path $TestDrive "repo-clean-retry"
            $gitDir = Join-Path $repo ".git"
            $staleDir = Join-Path $repo "stale"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            New-Item -ItemType Directory -Path $staleDir -Force | Out-Null
            Set-Content -Path (Join-Path $staleDir "tmp.txt") -Value "x"
            $item = Get-Item -LiteralPath $staleDir -Force
            $item.Attributes = ($item.Attributes -bor [System.IO.FileAttributes]::ReadOnly)

            Mock Test-GitProcessRunning { $false }
            $script:cleanCalls = 0
            Mock Invoke-Git {
                param($GitArgs)
                if ($GitArgs[0] -eq "clean") {
                    $script:cleanCalls++
                    if ($script:cleanCalls -eq 1) {
                        throw "git 失败：git clean -fd；详情：warning: failed to remove stale/: Permission denied"
                    }
                }
            }

            Push-Location $repo
            try {
                Git-HardResetClean $true
            }
            finally {
                Pop-Location
            }

            $script:cleanCalls | Should Be 2
            (Test-Path -LiteralPath $staleDir) | Should Be $false
        }
    }

    Context "Repair-GitCleanPermissionDenied" {
        It "Repairs only paths inside the repo" {
            $repo = Join-Path $TestDrive "repo-clean-repair"
            $inside = Join-Path $repo "inside"
            New-Item -ItemType Directory -Path $inside -Force | Out-Null
            Set-Content -Path (Join-Path $inside "tmp.txt") -Value "x"
            $insideItem = Get-Item -LiteralPath $inside -Force
            $insideItem.Attributes = ($insideItem.Attributes -bor [System.IO.FileAttributes]::ReadOnly)

            $outside = Join-Path $TestDrive "outside"
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            Set-Content -Path (Join-Path $outside "keep.txt") -Value "keep"

            $msg = "git 失败：git clean -fd；详情：warning: failed to remove inside/: Permission denied | warning: failed to remove ../outside/: Permission denied"
            $repaired = Repair-GitCleanPermissionDenied $repo $msg

            $repaired | Should Be $true
            (Test-Path -LiteralPath $inside) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $outside "keep.txt")) | Should Be $true
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
