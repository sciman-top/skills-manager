BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

}
Describe "Git lock recovery" {
    Context "Get-GitLockPathFromOutputLine" {
        It "Extracts index.lock path from git stderr line" {
            $line = "fatal: Unable to create 'E:/repo/.git/index.lock': File exists."
            Get-GitLockPathFromOutputLine $line | Should -Be "E:/repo/.git/index.lock"
        }

        It "Extracts index.lock path from unlink stderr line" {
            $line = "warning: unable to unlink 'E:/repo/.git/index.lock': Invalid argument"
            Get-GitLockPathFromOutputLine $line | Should -Be "E:/repo/.git/index.lock"
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

            $repaired = Repair-StaleGitLockFromOutput $repo @("fatal: Unable to create '$lockPath': File exists.")

            $repaired | Should -Be $true
            (Test-Path $lockPath) | Should -Be $false
        }

        It "Does not remove lock when a Git process exists" {
            $repo = Join-Path $TestDrive "repo2"
            $gitDir = Join-Path $repo ".git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            $lockPath = Join-Path $gitDir "index.lock"
            Set-Content -Path $lockPath -Value "active"

            Mock Test-GitProcessRunning { $true }

            $repaired = Repair-StaleGitLockFromOutput $repo @("fatal: Unable to create '$lockPath': File exists.")

            $repaired | Should -Be $false
            (Test-Path $lockPath) | Should -Be $true
        }

        It "Rejects stderr lock paths outside the current repository Git admin directory" {
            $repo = Join-Path $TestDrive "repo-outside-guard"
            $gitDir = Join-Path $repo ".git"
            $outsideDir = Join-Path $TestDrive "outside-git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            New-Item -ItemType Directory -Path $outsideDir -Force | Out-Null
            $outsideLock = Join-Path $outsideDir "index.lock"
            Set-Content -Path $outsideLock -Value "keep"

            Mock Test-GitProcessRunning { $false }

            Push-Location $repo
            try {
                $repaired = Repair-StaleGitLockFromOutput $repo @("fatal: Unable to create '$outsideLock': File exists.")
            }
            finally {
                Pop-Location
            }

            $repaired | Should -Be $false
            (Test-Path -LiteralPath $outsideLock -PathType Leaf) | Should -Be $true
        }

        It "Does not attempt removal when a Git process is still running" {
            $repo = Join-Path $TestDrive "repo2-busy"
            $gitDir = Join-Path $repo ".git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            $lockPath = Join-Path $gitDir "index.lock"
            Set-Content -Path $lockPath -Value "active"

            Mock Test-GitProcessRunning { $true }
            Mock Remove-GitLockFile { $false }

            $repaired = Repair-StaleGitLockFromOutput $repo @("fatal: Unable to create '$lockPath': File exists.")

            $repaired | Should -Be $false
            Should -Invoke Remove-GitLockFile -Times 0
            (Test-Path $lockPath) | Should -Be $true
        }
    }

    Context "Git-HardResetClean" {
        It "Aborts in-progress merge before reset and clean" {
            $repo = Join-Path $TestDrive "repo-merge-abort"
            $gitDir = Join-Path $repo ".git"
            New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
            Set-Content -Path (Join-Path $gitDir "MERGE_HEAD") -Value "merge"

            Mock Test-GitProcessRunning { $false }
            $script:calls = New-Object System.Collections.Generic.List[string]
            Mock Invoke-Git {
                param($GitArgs)
                $script:calls.Add((@($GitArgs) -join " ")) | Out-Null
            }

            Push-Location $repo
            try {
                Git-HardResetClean $true
            }
            finally {
                Pop-Location
            }

            $script:calls[0] | Should -Be "merge --abort"
            $script:calls[1] | Should -Be "reset --hard"
            $script:calls[2] | Should -Be "clean -ffdx"
        }

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

            (Test-Path $lockPath) | Should -Be $false
            Should -Invoke Invoke-Git -Times 1 -ParameterFilter { $GitArgs[0] -eq "reset" -and $GitArgs[1] -eq "--hard" }
            Should -Invoke Invoke-Git -Times 1 -ParameterFilter { $GitArgs[0] -eq "clean" -and $GitArgs[1] -eq "-ffdx" }
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
                        throw "git 失败：git clean -ffdx；详情：warning: failed to remove stale/: Permission denied"
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

            $script:cleanCalls | Should -Be 2
            (Test-Path -LiteralPath $staleDir) | Should -Be $false
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

            $msg = "git 失败：git clean -ffdx；详情：warning: failed to remove inside/: Permission denied | warning: failed to remove ../outside/: Permission denied"
            $repaired = Repair-GitCleanPermissionDenied $repo $msg

            $repaired | Should -Be $true
            (Test-Path -LiteralPath $inside) | Should -Be $false
            (Test-Path -LiteralPath (Join-Path $outside "keep.txt")) | Should -Be $true
        }

        It "Summarizes all permission denied paths instead of only the last two lines" {
            $summary = Get-GitOutputSummary @(
                "warning: failed to remove path-a/: Permission denied"
                "warning: failed to remove path-b/: Permission denied"
                "warning: failed to remove path-c/: Permission denied"
                "fatal: some clean paths could not be removed"
            )

            $summary | Should -Be "warning: failed to remove path-a/: Permission denied | warning: failed to remove path-b/: Permission denied | warning: failed to remove path-c/: Permission denied"
        }
    }

    Context "Sparse checkout residual cleanup" {
        It "Prunes tracked paths outside the next sparse set without removing kept ancestors" {
            $candidates = Get-GitSparsePruneCandidates @(
                "skills/keep/SKILL.md"
                "skills/old/scripts/helper.js"
                "skills/parent/keep/SKILL.md"
                "skills/parent/old/SKILL.md"
                "src/tool.ps1"
            ) @(
                "skills/keep"
                "skills/parent/keep"
            )

            $candidates | Should -Contain "skills/old"
            $candidates | Should -Contain "skills/parent/old"
            $candidates | Should -Contain "src"
            $candidates | Should -Not -Contain "skills"
            $candidates | Should -Not -Contain "skills/parent"
        }

        It "Removes read-only directory shells outside the next sparse set" {
            $repo = Join-Path $TestDrive "repo-sparse-residue"
            $keepDir = Join-Path $repo "skills\keep"
            $oldDir = Join-Path $repo "skills\old\scripts"
            New-Item -ItemType Directory -Path $keepDir -Force | Out-Null
            New-Item -ItemType Directory -Path $oldDir -Force | Out-Null
            Set-Content -Path (Join-Path $keepDir "SKILL.md") -Value "keep"
            $oldRoot = Join-Path $repo "skills\old"
            $oldItem = Get-Item -LiteralPath $oldRoot -Force
            $oldItem.Attributes = ($oldItem.Attributes -bor [System.IO.FileAttributes]::ReadOnly)

            Mock Invoke-GitCaptureLines {
                @(
                    "skills/keep/SKILL.md"
                    "skills/old/scripts/helper.js"
                )
            } -ParameterFilter { $GitArgs[0] -eq "ls-files" }

            Push-Location $repo
            try {
                Remove-GitSparseCheckoutResiduals @("skills/keep")
            }
            finally {
                Pop-Location
            }

            (Test-Path -LiteralPath $oldRoot) | Should -Be $false
            (Test-Path -LiteralPath $keepDir) | Should -Be $true
        }

        It "Repairs sparse-checkout remove warnings returned with exit code zero" {
            $repo = Join-Path $TestDrive "repo-sparse-warning"
            $staleDir = Join-Path $repo "skills\old"
            New-Item -ItemType Directory -Path $staleDir -Force | Out-Null
            $staleItem = Get-Item -LiteralPath $staleDir -Force
            $staleItem.Attributes = ($staleItem.Attributes -bor [System.IO.FileAttributes]::ReadOnly)

            $repaired = Repair-GitSparseCheckoutRemoveWarnings $repo @(
                "warning: failed to remove directory 'skills/old/'"
            )

            $repaired | Should -Be $true
            (Test-Path -LiteralPath $staleDir) | Should -Be $false
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

            $repaired | Should -Be $true
            (Test-Path $lockPath) | Should -Be $false
        }
    }
}
