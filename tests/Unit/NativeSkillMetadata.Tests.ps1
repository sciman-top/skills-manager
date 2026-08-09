$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$verifierPath = Join-Path $repoRoot 'scripts\verify-native-skill-metadata.ps1'
$corpusPath = Join-Path $repoRoot 'config\native-skill-activation-corpus.json'

function Invoke-NativeSkillMetadataVerifier {
    param(
        [string]$Root = $repoRoot,
        [string]$Corpus = $corpusPath,
        [string]$HostInventory = '',
        [string]$ProjectionReceipt = ''
    )

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifierPath, '-RepoRoot', $Root, '-CorpusPath', $Corpus, '-Json')
    if (-not [string]::IsNullOrWhiteSpace($HostInventory)) { $arguments += @('-HostInventoryPath', $HostInventory) }
    if (-not [string]::IsNullOrWhiteSpace($ProjectionReceipt)) { $arguments += @('-ProjectionReceiptPath', $ProjectionReceipt) }
    $output = @(& pwsh @arguments 2>&1)
    $text = $output -join "`n"
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch { }
    return [pscustomobject]@{
        exit_code = $LASTEXITCODE
        output = $text
        parsed = $parsed
    }
}

Describe 'Host-native skill metadata and activation corpus' {
    It 'keeps TDD explicit and research bounded by decision relevance and persistence authority' {
        $corpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json
        $tddTarget = @($corpus.metadata_targets | Where-Object name -eq 'test-driven-development')
        $researchTarget = @($corpus.metadata_targets | Where-Object name -eq 'research')
        $strictTdd = @($corpus.cases | Where-Object id -eq 'direct-strict-tdd')
        $routineImplementation = @($corpus.cases | Where-Object id -eq 'negative-routine-implementation')
        $decisionResearch = @($corpus.cases | Where-Object id -eq 'direct-decision-research')
        $suppliedFacts = @($corpus.cases | Where-Object id -eq 'negative-supplied-facts-no-research')

        $tddTarget.Count | Should Be 1
        [string]$tddTarget[0].source | Should Be 'overrides/patches/superpowers-skills-test-driven-development/SKILL.md'
        @($tddTarget[0].trigger_phrases) | Should Contain 'strict TDD'
        $researchTarget.Count | Should Be 1
        [string]$researchTarget[0].source | Should Be 'overrides/patches/research/SKILL.md'
        @($researchTarget[0].trigger_phrases) | Should Contain 'read-only'

        $strictTdd.Count | Should Be 1
        @($strictTdd[0].required_skills) | Should Be @('test-driven-development')
        $routineImplementation.Count | Should Be 1
        @($routineImplementation[0].forbidden_skills) | Should Contain 'test-driven-development'
        $decisionResearch.Count | Should Be 1
        @($decisionResearch[0].required_skills) | Should Be @('research')
        $suppliedFacts.Count | Should Be 1
        @($suppliedFacts[0].forbidden_skills) | Should Contain 'research'
    }

    It 'verifies the repository corpus without pretending host metadata was observed' {
        $result = Invoke-NativeSkillMetadataVerifier

        $result.exit_code | Should Be 0
        $result.parsed | Should Not BeNullOrEmpty
        $result.parsed.pass | Should Be $true
        $result.parsed.schema_version | Should Be 2
        $result.parsed.decision_owner | Should Be 'host_ai'
        $result.parsed.semantic_selection_applied | Should Be $false
        $result.parsed.provider_calls | Should Be 0
        $result.parsed.native_mutations | Should Be 0
        $result.parsed.writes | Should Be 0
        $result.parsed.finding_count | Should Be 0
        $result.parsed.observed_inventory.status | Should Be 'not_provided'
        $result.parsed.observed_inventory.budget.host_budget_status | Should Be 'unknown'
        $result.parsed.observed_inventory.budget.host_budget_pass | Should Be $null
        $result.parsed.corpus.case_count | Should BeGreaterThan 0
        $result.parsed.corpus.categories | Should Contain 'direct'
        $result.parsed.corpus.categories | Should Contain 'indirect'
        $result.parsed.corpus.categories | Should Contain 'negative'
        $result.parsed.corpus.categories | Should Contain 'ambiguous'
        $result.parsed.corpus.categories | Should Contain 'no_skill'
        $result.parsed.corpus.formerly_unreachable_skill_count | Should BeGreaterThan 0
        $result.parsed.corpus.pairwise.target_count | Should Be 15
        $result.parsed.corpus.pairwise.group_count | Should Be 5
        $result.parsed.corpus.pairwise.case_count | Should Be 16
        $result.parsed.corpus.pairwise.dimensions | Should Contain 'artifact_create'
        $result.parsed.corpus.pairwise.dimensions | Should Contain 'artifact_read'
        $result.parsed.corpus.pairwise.dimensions | Should Contain 'signed_in_session'
        $result.parsed.corpus.pairwise.dimensions | Should Contain 'live_control'
        $result.parsed.corpus.pairwise.dimensions | Should Contain 'no_browser'
        $result.parsed.corpus.pairwise.dimensions | Should Contain 'side_effect_boundary'
    }

    It 'reports actual descriptions for every expected projected skill without treating an advisory limit as a host budget' {
        $hostInventory = Join-Path $TestDrive 'host-inventory.json'
        $projectionReceipt = Join-Path $TestDrive 'projection-receipt.json'
        [pscustomobject]@{
            schema_version = 1
            snapshot_id = 'fixture-host-inventory'
            captured_at = '2026-08-09T00:00:00Z'
            capabilities = [pscustomobject]@{
                metadata_budget = [pscustomobject]@{ value = $null; source = 'unknown_fallback'; freshness = 'unknown'; unknown_reason = 'metadata_budget_unknown' }
                skills_inventory = [pscustomobject]@{ freshness = 'fresh'; value = @(
                        [pscustomobject]@{ name = 'alpha'; description = ('a' * 10); enabled = $true }
                        [pscustomobject]@{ name = 'beta'; description = ('b' * 400); enabled = $true }
                        [pscustomobject]@{ name = 'gamma'; description = ('g' * 100); enabled = $true }
                        [pscustomobject]@{ name = 'host-plugin'; description = ('p' * 20); enabled = $true }
                    ) }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $hostInventory -Encoding UTF8
        [pscustomobject]@{ schema_version = 1; after = @(
                [pscustomobject]@{ directory_path = 'C:\fixture\alpha' }
                [pscustomobject]@{ directory_path = 'C:\fixture\beta' }
                [pscustomobject]@{ directory_path = 'C:\fixture\gamma' }
            ) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $projectionReceipt -Encoding UTF8

        $result = Invoke-NativeSkillMetadataVerifier -HostInventory $hostInventory -ProjectionReceipt $projectionReceipt

        $result.exit_code | Should Be 0
        $result.parsed | Should Not BeNullOrEmpty
        $result.parsed.pass | Should Be $true
        $result.parsed.observed_inventory.status | Should Be 'verified'
        $result.parsed.observed_inventory.observed_total | Should Be 4
        $result.parsed.observed_inventory.expected_total | Should Be 3
        $result.parsed.observed_inventory.matched_total | Should Be 3
        $result.parsed.observed_inventory.missing_total | Should Be 0
        $result.parsed.observed_inventory.description_metrics.total_characters | Should Be 510
        $result.parsed.observed_inventory.description_metrics.maximum_characters | Should Be 400
        $result.parsed.observed_inventory.description_metrics.average_characters | Should Be 170
        $result.parsed.observed_inventory.description_metrics.over_advisory_limit_total | Should Be 1
        $result.parsed.observed_inventory.budget.host_budget_status | Should Be 'unknown'
        $result.parsed.observed_inventory.budget.host_budget_pass | Should Be $null
    }

    It 'fails closed when an expected projected skill is absent from observed host inventory' {
        $hostInventory = Join-Path $TestDrive 'missing-host-inventory.json'
        $projectionReceipt = Join-Path $TestDrive 'missing-projection-receipt.json'
        [pscustomobject]@{ schema_version = 1; capabilities = [pscustomobject]@{
                metadata_budget = [pscustomobject]@{ value = $null; source = 'unknown_fallback'; freshness = 'unknown' }
                skills_inventory = [pscustomobject]@{ freshness = 'fresh'; value = @([pscustomobject]@{ name = 'alpha'; description = 'observed alpha'; enabled = $true }) }
            } } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $hostInventory -Encoding UTF8
        [pscustomobject]@{ schema_version = 1; after = @(
                [pscustomobject]@{ directory_path = 'C:\fixture\alpha' }
                [pscustomobject]@{ directory_path = 'C:\fixture\missing' }
            ) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $projectionReceipt -Encoding UTF8

        $result = Invoke-NativeSkillMetadataVerifier -HostInventory $hostInventory -ProjectionReceipt $projectionReceipt

        $result.exit_code | Should Not Be 0
        $result.parsed.pass | Should Be $false
        $result.parsed.observed_inventory.missing_total | Should Be 1
        @($result.parsed.findings | Where-Object code -eq 'host_inventory_expected_skill_missing').Count | Should Be 1
    }

    It 'fails closed when the pairwise corpus drops a declared risk dimension' {
        $badCorpus = Join-Path $TestDrive 'pairwise-dimension-missing.json'
        $corpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json
        $dimensions = if ($corpus.PSObject.Properties.Match('pairwise_dimensions').Count -gt 0) { @($corpus.pairwise_dimensions) } else { @('artifact_create', 'artifact_read', 'signed_in_session', 'live_control', 'no_browser') }
        $corpus | Add-Member -NotePropertyName pairwise_dimensions -NotePropertyValue @($dimensions | Where-Object { $_ -ne 'side_effect_boundary' }) -Force
        $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $badCorpus -Encoding UTF8

        $result = Invoke-NativeSkillMetadataVerifier -Root $TestDrive -Corpus $badCorpus

        $result.exit_code | Should Not Be 0
        $result.parsed.pass | Should Be $false
        @($result.parsed.findings | Where-Object code -eq 'pairwise_dimension_missing').Count | Should Be 1
    }
}
