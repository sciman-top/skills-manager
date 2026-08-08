$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$verifierPath = Join-Path $repoRoot 'scripts\verify-native-skill-metadata.ps1'
$corpusPath = Join-Path $repoRoot 'config\native-skill-activation-corpus.json'
$metadataPath = Join-Path $repoRoot 'overrides\custom\capability-router\agents\openai.yaml'

function Invoke-NativeSkillMetadataVerifier {
    param(
        [string]$Root = $repoRoot,
        [string]$Corpus = $corpusPath,
        [string]$Metadata = $metadataPath
    )

    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $verifierPath -RepoRoot $Root -CorpusPath $Corpus -MetadataPath $Metadata -Json 2>&1)
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
    It 'verifies concise metadata and all required host evaluation categories' {
        $result = Invoke-NativeSkillMetadataVerifier

        $result.exit_code | Should Be 0
        $result.parsed | Should Not BeNullOrEmpty
        $result.parsed.pass | Should Be $true
        $result.parsed.schema_version | Should Be 1
        $result.parsed.decision_owner | Should Be 'host_ai'
        $result.parsed.semantic_selection_applied | Should Be $false
        $result.parsed.provider_calls | Should Be 0
        $result.parsed.native_mutations | Should Be 0
        $result.parsed.writes | Should Be 0
        $result.parsed.finding_count | Should Be 0
        $result.parsed.corpus.case_count | Should BeGreaterThan 0
        $result.parsed.corpus.categories | Should Contain 'direct'
        $result.parsed.corpus.categories | Should Contain 'indirect'
        $result.parsed.corpus.categories | Should Contain 'negative'
        $result.parsed.corpus.categories | Should Contain 'ambiguous'
        $result.parsed.corpus.categories | Should Contain 'no_skill'
        $result.parsed.corpus.formerly_unreachable_skill_count | Should BeGreaterThan 0
    }

    It 'fails closed when a metadata description exceeds the declared limit' {
        $badMetadata = Join-Path $TestDrive 'openai.yaml'
        $text = Get-Content -LiteralPath $metadataPath -Raw
        $text = $text -replace '(?m)^  short_description:.*$', ('  short_description: "' + ('x' * 400) + '"')
        Set-Content -LiteralPath $badMetadata -Value $text -Encoding UTF8

        $result = Invoke-NativeSkillMetadataVerifier -Metadata $badMetadata

        $result.exit_code | Should Not Be 0
        $result.parsed | Should Not BeNullOrEmpty
        $result.parsed.pass | Should Be $false
        @($result.parsed.findings | Where-Object code -eq 'metadata_description_too_long').Count | Should Be 1
    }
}
