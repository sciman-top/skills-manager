BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $verifierPath = Join-Path $repoRoot 'scripts\quality\verify-cold-skill-routing-receipt.ps1'
    $fixturesRoot = Join-Path $repoRoot 'tests\fixtures\cold-skill-routing\receipts'
    $matrixPath = Join-Path $repoRoot 'tests\fixtures\cold-skill-routing\scenarios.json'

    function Invoke-ReceiptVerifier([string[]]$VerifierArguments) {
        $output = & pwsh -NoProfile -File $verifierPath @VerifierArguments 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (@($output) -join "`n") }
    }
}

Describe 'Cold skill routing receipt v2 verifier' {
    It 'accepts a valid routing-phase receipt capped at candidate_load_validated' {
        $result = Invoke-ReceiptVerifier @('-ReceiptPath', (Join-Path $fixturesRoot 'valid-routing.json'))

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'findings=0'
    }

    It 'accepts a valid live-acceptance receipt only with the full child event chain' {
        $result = Invoke-ReceiptVerifier @('-ReceiptPath', (Join-Path $fixturesRoot 'valid-live.json'))

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'findings=0'
    }

    It 'rejects every overclaim class with its stable finding code' {
        $cases = @(
            @{ Fixture = 'invalid-forbidden-discovery-observed.json'; Code = 'E003_FORBIDDEN_DISCOVERY_OBSERVED' }
            @{ Fixture = 'invalid-router-overclaim.json'; Code = 'E007_SKILL_LOAD_OVERCLAIM' }
            @{ Fixture = 'invalid-zcode-live-claim.json'; Code = 'E009_LIVE_ACCEPTANCE_OVERCLAIM' }
            @{ Fixture = 'invalid-multiturn-runner.json'; Code = 'E010_MULTI_TURN_VIA_RUNNER' }
            @{ Fixture = 'invalid-target-bound.json'; Code = 'E011_TARGET_BOUND_WITHOUT_TARGET' }
            @{ Fixture = 'invalid-controlled-write.json'; Code = 'E012_CONTROLLED_WRITE_INCOMPLETE' }
            @{ Fixture = 'invalid-scenario-unknown.json'; Code = 'E004_SCENARIO_NOT_IN_MATRIX' }
            @{ Fixture = 'invalid-empty-evidence.json'; Code = 'E014_EVIDENCE_INVALID' }
            @{ Fixture = 'invalid-verbatim-mismatch.json'; Code = 'E006_VERBATIM_MISMATCH' }
            @{ Fixture = 'invalid-ceiling-violation.json'; Code = 'E013_CEILING_VIOLATED' }
            @{ Fixture = 'invalid-required-not-observed.json'; Code = 'E015_REQUIRED_EVENT_NOT_OBSERVED' }
        )

        foreach ($case in $cases) {
            $result = Invoke-ReceiptVerifier @('-ReceiptPath', (Join-Path $fixturesRoot $case.Fixture))
            $result.ExitCode | Should -Be 1 -Because ("fixture {0} must fail closed" -f $case.Fixture)
            $result.Output | Should -Match ([regex]::Escape($case.Code)) -Because ("fixture {0} must report {1}" -f $case.Fixture, $case.Code)
        }
    }

    It 'rejects enum drift with the schema finding code' {
        $receipt = Get-Content -LiteralPath (Join-Path $fixturesRoot 'valid-routing.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $receipt.expected.route_class = 'warm_candidate'
        $receiptPath = Join-Path $TestDrive 'enum-drift.json'
        $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

        $result = Invoke-ReceiptVerifier @('-ReceiptPath', $receiptPath)

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'E002_ENUM_INVALID'
    }

    It 'rejects a legacy receipt without the migration flag' {
        $result = Invoke-ReceiptVerifier @('-ReceiptPath', (Join-Path $fixturesRoot 'legacy-receipt.json'))

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'E019_LEGACY_SCHEMA_REQUIRES_MIGRATION'
    }

    It 'migrates a legacy receipt without touching the original, caps every claim, and re-verifies' {
        $legacyCopy = Join-Path $TestDrive 'receipt.json'
        Copy-Item -LiteralPath (Join-Path $fixturesRoot 'legacy-receipt.json') -Destination $legacyCopy
        $beforeHash = ([string](Get-FileHash -LiteralPath $legacyCopy -Algorithm SHA256).Hash).ToLowerInvariant()
        $outputPath = Join-Path $TestDrive 'receipt.v2.json'

        $result = Invoke-ReceiptVerifier @('-ReceiptPath', $legacyCopy, '-AllowLegacyMigration', '-OutputPath', $outputPath)
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'migration written'

        ([string](Get-FileHash -LiteralPath $legacyCopy -Algorithm SHA256).Hash).ToLowerInvariant() | Should -Be $beforeHash
        $migrated = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $migrated.schema_version | Should -Be 2
        $migrated.migrated_from.legacy_receipt_path | Should -Be ([IO.Path]::GetFullPath($legacyCopy))
        $migrated.migrated_from.legacy_receipt_sha256 | Should -Be $beforeHash
        @($migrated.migrated_from.migration_notes).Count | Should -BeGreaterThan 0
        @($migrated.records).Count | Should -Be 3
        foreach ($record in @($migrated.records)) {
            $record.observed.skill_md_loading | Should -Be 'not_observable'
            $record.observed.native_child | Should -Be 'not_supported'
            $record.assertion.achieved_boundary | Should -Not -Be 'host_specific_live_accepted'
        }

        $validatedRecords = @($migrated.records | Where-Object { $_.observed.candidate_load_validation -eq 'observed' })
        @($validatedRecords).Count | Should -Be 2 -Because 'legacy S2/S3 router validation events stay observable'
        foreach ($record in $validatedRecords) {
            $record.assertion.achieved_boundary | Should -Be 'candidate_load_validated'
            $record.observed.cold_discovery | Should -Be 'observed'
        }

        $recheck = Invoke-ReceiptVerifier @('-ReceiptPath', $outputPath)
        $recheck.ExitCode | Should -Be 0
        $recheck.Output | Should -Match 'findings=0'
    }

    It 'preserves a legacy controlled-write record but refuses to invent the missing admission contract' {
        $legacyCopy = Join-Path $TestDrive 'receipt.json'
        Copy-Item -LiteralPath (Join-Path $fixturesRoot 'legacy-unverifiable-controlled-write.json') -Destination $legacyCopy
        $beforeHash = ([string](Get-FileHash -LiteralPath $legacyCopy -Algorithm SHA256).Hash).ToLowerInvariant()
        $outputPath = Join-Path $TestDrive 'receipt.v2.json'

        $result = Invoke-ReceiptVerifier @('-ReceiptPath', $legacyCopy, '-AllowLegacyMigration', '-OutputPath', $outputPath)

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'migration written'
        $result.Output | Should -Match 'E012_CONTROLLED_WRITE_INCOMPLETE'
        ([string](Get-FileHash -LiteralPath $legacyCopy -Algorithm SHA256).Hash).ToLowerInvariant() | Should -Be $beforeHash

        $migrated = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $migrated.migrated_from.legacy_receipt_path | Should -Be ([IO.Path]::GetFullPath($legacyCopy))
        $migrated.migrated_from.legacy_receipt_sha256 | Should -Be $beforeHash
        $migrated.records[0].observed.skill_md_loading | Should -Be 'not_observable'
        $migrated.records[0].observed.native_child | Should -Be 'not_supported'
        $migrated.records[0].assertion.achieved_boundary | Should -Not -Be 'host_specific_live_accepted'

        $recheck = Invoke-ReceiptVerifier @('-ReceiptPath', $outputPath)
        $recheck.ExitCode | Should -Be 1
        $recheck.Output | Should -Match 'E012_CONTROLLED_WRITE_INCOMPLETE'
    }

    It 'refuses to overwrite the legacy original during migration' {
        $legacyCopy = Join-Path $TestDrive 'receipt.json'
        Copy-Item -LiteralPath (Join-Path $fixturesRoot 'legacy-receipt.json') -Destination $legacyCopy
        $beforeHash = ([string](Get-FileHash -LiteralPath $legacyCopy -Algorithm SHA256).Hash).ToLowerInvariant()

        $result = Invoke-ReceiptVerifier @('-ReceiptPath', $legacyCopy, '-AllowLegacyMigration', '-OutputPath', $legacyCopy)

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'E017_MIGRATION_TARGET_CONFLICT'
        ([string](Get-FileHash -LiteralPath $legacyCopy -Algorithm SHA256).Hash).ToLowerInvariant() | Should -Be $beforeHash
    }

    It 'rejects a scenario matrix with duplicate scenario ids' {
        $matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $matrix.scenarios = @($matrix.scenarios) + @($matrix.scenarios[0])
        $matrixCopy = Join-Path $TestDrive 'scenarios.json'
        $matrix | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $matrixCopy -Encoding UTF8

        $result = Invoke-ReceiptVerifier @('-ReceiptPath', (Join-Path $fixturesRoot 'valid-routing.json'), '-ScenarioMatrixPath', $matrixCopy)

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'E005_MATRIX_INVALID'
    }
}
