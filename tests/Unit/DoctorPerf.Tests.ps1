. $PSScriptRoot\..\..\skills.ps1

Describe "Doctor Performance Summary" {
    Context "Get-PerfSummaryFromLogLines" {
        It "Ignores invalid lines and non-metric records" {
            $lines = @(
                "not-json"
                '{"ts":"2026-02-20 10:00:00","level":"INFO","msg":"x"}'
                '{"ts":"2026-02-20 10:00:01","level":"INFO","msg":"x","data":{"metric":"","duration_ms":10}}'
                '{"ts":"2026-02-20 10:00:02","level":"INFO","msg":"x","data":{"metric":"build_agent","duration_ms":-1}}'
                '{"ts":"2026-02-20 10:00:03","level":"INFO","msg":"x","data":{"metric":"build_agent","duration_ms":120}}'
            )

            $summary = Get-PerfSummaryFromLogLines $lines 3
            $summary.Count | Should Be 1
            $summary[0].metric | Should Be "build_agent"
            $summary[0].samples | Should Be 1
            $summary[0].last_ms | Should Be 120
            $summary[0].avg_ms | Should Be 120
        }

        It "Aggregates recent N samples per metric" {
            $lines = @(
                '{"ts":"2026-02-20 10:00:00","level":"INFO","msg":"x","data":{"metric":"build_agent","duration_ms":100}}'
                '{"ts":"2026-02-20 10:00:01","level":"INFO","msg":"x","data":{"metric":"apply_targets","duration_ms":80}}'
                '{"ts":"2026-02-20 10:00:02","level":"INFO","msg":"x","data":{"metric":"build_agent","duration_ms":200}}'
                '{"ts":"2026-02-20 10:00:03","level":"INFO","msg":"x","data":{"metric":"build_agent","duration_ms":300}}'
                '{"ts":"2026-02-20 10:00:04","level":"INFO","msg":"x","data":{"metric":"apply_targets","duration_ms":120}}'
            )

            $summary = Get-PerfSummaryFromLogLines $lines 2
            $build = $summary | Where-Object { $_.metric -eq "build_agent" } | Select-Object -First 1
            $apply = $summary | Where-Object { $_.metric -eq "apply_targets" } | Select-Object -First 1

            $build.samples | Should Be 2
            $build.last_ms | Should Be 300
            $build.avg_ms | Should Be 250

            $apply.samples | Should Be 2
            $apply.last_ms | Should Be 120
            $apply.avg_ms | Should Be 100
        }
    }

    Context "Add-PerfThresholdMetadata" {
        It "Annotates summary items with effective thresholds and anomaly flags" {
            $summary = @(
                [pscustomobject]@{ metric = "build_agent"; samples = 3; avg_ms = 5200; last_ms = 5400; last_ts = "2026-02-20 10:00:03" },
                [pscustomobject]@{ metric = "update_total"; samples = 3; avg_ms = 300000; last_ms = 400000; last_ts = "2026-02-20 10:00:04" },
                [pscustomobject]@{ metric = "workflow_run"; samples = 3; avg_ms = 12000; last_ms = 24000; last_ts = "2026-02-20 10:00:05" },
                [pscustomobject]@{ metric = "custom_metric"; samples = 3; avg_ms = 1200; last_ms = 1400; last_ts = "2026-02-20 10:00:05" }
            )

            $annotated = Add-PerfThresholdMetadata $summary 5000
            $build = $annotated | Where-Object { $_.metric -eq "build_agent" } | Select-Object -First 1
            $update = $annotated | Where-Object { $_.metric -eq "update_total" } | Select-Object -First 1
            $workflow = $annotated | Where-Object { $_.metric -eq "workflow_run" } | Select-Object -First 1
            $custom = $annotated | Where-Object { $_.metric -eq "custom_metric" } | Select-Object -First 1

            $build.anomaly_check_enabled | Should Be $true
            $build.effective_threshold_ms | Should Be 8000

            $update.anomaly_check_enabled | Should Be $true
            $update.effective_threshold_ms | Should Be 240000

            $workflow.anomaly_check_enabled | Should Be $true
            $workflow.effective_threshold_ms | Should Be 30000

            $custom.anomaly_check_enabled | Should Be $true
            $custom.effective_threshold_ms | Should Be 5000
        }
    }
}
