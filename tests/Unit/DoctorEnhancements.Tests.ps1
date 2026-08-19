BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

}
Describe "Doctor Enhancements" {
    Context "Get-DoctorLegacyAutoUpdateTaskStatus" {
        It "recognizes the managed current weekly runner" {
            $runner = Join-Path $Root 'scripts\weekly-skills-update.ps1'
            $task = [pscustomobject]@{ Actions = @([pscustomobject]@{ Arguments = ('-File "{0}"' -f $runner) }) }

            $status = Get-DoctorAutoUpdateTaskClassification -Task $task -ExpectedRunner $runner

            $status.state | Should -Be 'managed_current'
            $status.action | Should -Be 'none'
            $status.runner_exists | Should -BeTrue
        }

        It "marks the removed legacy runner as stale" {
            $runner = Join-Path $Root 'scripts\weekly-skills-update.ps1'
            $task = [pscustomobject]@{ Actions = @([pscustomobject]@{ Arguments = ('-File "{0}"' -f (Join-Path $Root 'scripts\weekly-auto-update.ps1')) }) }

            $status = Get-DoctorAutoUpdateTaskClassification -Task $task -ExpectedRunner $runner

            $status.state | Should -Be 'stale_legacy'
            $status.action | Should -Be 'manual_repair_or_cleanup'
        }
    }

    Context "Parse-DoctorArgs" {
        It "Parses json/fix options" {
            $opts = Parse-DoctorArgs @("--json", "--fix")
            $opts.json | Should -Be $true
            $opts.fix | Should -Be $true
        }

        It "Parses strict and dry-run-fix options" {
            $opts = Parse-DoctorArgs @("--strict", "--dry-run-fix")
            $opts.strict | Should -Be $true
            $opts.dry_run_fix | Should -Be $true
        }

        It "Allows offline contract only for non-mutating JSON checks" {
            $opts = Parse-DoctorArgs @("--json", "--offline-contract")
            $opts.offline_contract | Should -Be $true

            { Parse-DoctorArgs @("--offline-contract") | Out-Null } | Should -Throw
            { Parse-DoctorArgs @("--json", "--offline-contract", "--strict") | Out-Null } | Should -Throw
            { Parse-DoctorArgs @("--json", "--offline-contract", "--fix") | Out-Null } | Should -Throw
        }

        It "Rejects unknown option" {
            $thrown = $false
            try {
                Parse-DoctorArgs @("--bad-option") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }
    }

    Context "Apply-DoctorFixes" {
        It "Deduplicates targets and removes mappings with missing vendors" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.claude/skills" }
                )
                mappings = @(
                    [pscustomobject]@{ vendor = "vendor-a"; from = "a"; to = "skill-a" },
                    [pscustomobject]@{ vendor = "vendor-missing"; from = "x"; to = "skill-x" }
                )
            }

            $result = Apply-DoctorFixes $cfg
            $result.changed | Should -Be $true
            $result.applied.Count | Should -Be 2
            @($cfg.targets).Count | Should -Be 2
            @($cfg.mappings).Count | Should -Be 1
            $cfg.mappings[0].vendor | Should -Be "vendor-a"
        }

        It "Returns preview without mutating config when preview mode is enabled" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.codex/skills" }
                )
                mappings = @(
                    [pscustomobject]@{ vendor = "vendor-missing"; from = "x"; to = "skill-x" }
                )
            }

            $result = Apply-DoctorFixes $cfg -Preview
            $result.changed | Should -Be $true
            @($cfg.targets).Count | Should -Be 2
            @($cfg.mappings).Count | Should -Be 1
        }
    }

    Context "Get-DoctorConfigRisks" {
        It "Detects duplicate target paths and mapping.to collisions" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.codex/skills" }
                )
                mappings = @(
                    [pscustomobject]@{ vendor = "vendor-a"; from = "a"; to = "skill-x" },
                    [pscustomobject]@{ vendor = "vendor-a"; from = "b"; to = "skill-x" }
                )
            }

            $risks = Get-DoctorConfigRisks $cfg
            ($risks | Where-Object { $_ -like "*targets.path*" }).Count | Should -Be 1
            ($risks | Where-Object { $_ -like "*mappings.to*" }).Count | Should -Be 1
        }

        It "Detects mapping referencing missing vendor" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @()
                mappings = @(
                    [pscustomobject]@{ vendor = "vendor-missing"; from = "a"; to = "skill-a" }
                )
            }

            $risks = Get-DoctorConfigRisks $cfg
            ($risks | Where-Object { $_ -like "*不存在的 vendor*" }).Count | Should -Be 1
        }
    }

}
