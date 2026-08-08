$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\compare-native-and-legacy-skill-selection.ps1'

function New-ShadowInputFixture {
    $corpusPath = Join-Path $TestDrive 'shadow-corpus.json'
    $nativePath = Join-Path $TestDrive 'native-results.json'
    $legacyPath = Join-Path $TestDrive 'legacy-results.json'

    $corpus = [ordered]@{
        schema_version = 1
        evaluation_id = 'shadow-fixture-v1'
        cases = @(
            [ordered]@{ id = 'direct-a'; required_skills = @('skill-a'); forbidden_skills = @() },
            [ordered]@{ id = 'missing-trace'; required_skills = @('skill-a'); forbidden_skills = @() }
        )
    }
    $native = [ordered]@{
        schema_version = 1
        evaluator = 'native_only'
        cases = @(
            [ordered]@{
                id = 'direct-a'
                selected_skills = @('skill-a')
                trace = [ordered]@{ truth_level = 'host_evaluation_partial'; selection_observable = $true }
                ttfv_ms = 120
                tool_rounds = 2
            },
            [ordered]@{
                id = 'missing-trace'
                selected_skills = @()
                ttfv_ms = 160
                tool_rounds = 3
            }
        )
    }
    $legacy = [ordered]@{
        schema_version = 1
        evaluator = 'legacy_router_profile'
        cases = @(
            [ordered]@{ id = 'direct-a'; selected_skills = @('skill-b'); truth_level = 'host_evaluation_partial'; ttfv_ms = 200; tool_rounds = 4 },
            [ordered]@{ id = 'missing-trace'; selected_skills = @('skill-a'); truth_level = 'host_evaluation_partial'; ttfv_ms = 220; tool_rounds = 5 }
        )
    }
    $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $corpusPath -Encoding UTF8
    $native | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $nativePath -Encoding UTF8
    $legacy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $legacyPath -Encoding UTF8
    return [pscustomobject]@{ corpus = $corpusPath; native = $nativePath; legacy = $legacyPath }
}

function Invoke-ShadowComparison($Fixture) {
    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -CorpusPath $Fixture.corpus -NativeResultsPath $Fixture.native -LegacyResultsPath $Fixture.legacy -Json 2>&1)
    $text = $output -join "`n"
    $data = $null
    try { $data = $text | ConvertFrom-Json } catch { }
    return [pscustomobject]@{ exit_code = $LASTEXITCODE; output = $text; data = $data }
}

Describe 'Native versus legacy skill selection shadow' {
    It 'keeps shadow zero-write and does not let legacy results override native authority' {
        $fixture = New-ShadowInputFixture
        $result = Invoke-ShadowComparison $fixture

        $result.exit_code | Should Be 0
        $result.data.pass | Should Be $true
        $result.data.runtime_affected | Should Be $false
        $result.data.runtime.native_authoritative | Should Be $true
        $result.data.runtime.legacy_override_applied | Should Be $false
        $result.data.provider_calls | Should Be 0
        $result.data.native_mutations | Should Be 0
        $result.data.writes | Should Be 0
        $result.data.paired_case_count | Should Be 2
        $result.data.disagreement_count | Should BeGreaterThan 0
        $result.data.regression.native_false_positive_count | Should Be 0
        $result.data.regression.native_false_negative_count | Should Be 0
        $result.data.regression.partial_cases_excluded | Should Be $true
        $result.data.regression.pass | Should Be $true
        $result.data.retirement.decision | Should Be 'retire_legacy_semantic_authority_keep_compatibility_shadow'
        $result.data.retirement.runtime_mode | Should Be 'shadow_only'
        $result.data.retirement.full_removal_gate | Should Be 'P6-010_and_P6-012'
    }

    It 'keeps a missing native trace partial and avoids inventing a false negative' {
        $fixture = New-ShadowInputFixture
        $result = Invoke-ShadowComparison $fixture
        $case = @($result.data.cases | Where-Object id -eq 'missing-trace')[0]

        $case.native.truth_level | Should Be 'host_evaluation_partial'
        $case.native.selection_observable | Should Be $false
        $case.native.evaluated | Should Be $false
        $case.metrics.native_false_negative | Should Be $null
        @($result.data.findings | Where-Object code -eq 'native_trace_missing').Count | Should Be 1
    }
}
