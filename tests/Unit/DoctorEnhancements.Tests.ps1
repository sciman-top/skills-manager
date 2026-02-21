. $PSScriptRoot\..\..\skills.ps1

Describe "Doctor Enhancements" {
    Context "Parse-DoctorArgs" {
        It "Parses json/fix/threshold options" {
            $opts = Parse-DoctorArgs @("--json", "--fix", "--threshold-ms", "1200")
            $opts.json | Should Be $true
            $opts.fix | Should Be $true
            $opts.threshold_ms | Should Be 1200
        }

        It "Parses strict and dry-run-fix options" {
            $opts = Parse-DoctorArgs @("--strict", "--dry-run-fix")
            $opts.strict | Should Be $true
            $opts.dry_run_fix | Should Be $true
        }

        It "Rejects unknown option" {
            $thrown = $false
            try {
                Parse-DoctorArgs @("--bad-option") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
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
            $result.changed | Should Be $true
            $result.applied.Count | Should Be 2
            @($cfg.targets).Count | Should Be 2
            @($cfg.mappings).Count | Should Be 1
            $cfg.mappings[0].vendor | Should Be "vendor-a"
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
            $result.changed | Should Be $true
            @($cfg.targets).Count | Should Be 2
            @($cfg.mappings).Count | Should Be 1
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
            ($risks | Where-Object { $_ -like "*targets.path*" }).Count | Should Be 1
            ($risks | Where-Object { $_ -like "*mappings.to*" }).Count | Should Be 1
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
            ($risks | Where-Object { $_ -like "*不存在的 vendor*" }).Count | Should Be 1
        }
    }

    Context "Get-PerfAnomalyItems" {
        It "Returns anomaly items when last or avg exceeds threshold" {
            $summary = @(
                [pscustomobject]@{ metric = "build_agent"; last_ms = 1200; avg_ms = 900; samples = 3 },
                [pscustomobject]@{ metric = "sync_mcp"; last_ms = 200; avg_ms = 150; samples = 3 }
            )
            $items = Get-PerfAnomalyItems $summary 1000
            $items.Count | Should Be 1
            $items[0] | Should Match "build_agent"
        }

        It "Ignores high latency when samples are insufficient" {
            $summary = @(
                [pscustomobject]@{ metric = "update_imports"; last_ms = 82000; avg_ms = 82000; samples = 1 }
            )
            $items = Get-PerfAnomalyItems $summary 1000
            $items.Count | Should Be 0
        }
    }
}
