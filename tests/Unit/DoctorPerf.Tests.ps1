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
}
