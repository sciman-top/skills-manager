BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\SkillMetadata.ps1')
}

Describe 'Skill metadata' {
    It 'reads quoted scalars and folded block descriptions' {
        $path = Join-Path $TestDrive 'SKILL.md'
        "---`nname: 'demo-skill'`ndescription: >`n  First line`n  second line`ncompatibility: pwsh 7`n---`n" | Set-Content -LiteralPath $path
        $metadata = Read-SkillMetadata $path
        $metadata.valid | Should -BeTrue
        $metadata.name | Should -Be 'demo-skill'
        $metadata.description | Should -Be 'First line second line'
    }

    It 'preserves literal paragraphs and folded paragraph boundaries' {
        $literalPath = Join-Path $TestDrive 'literal.md'
        "---`nname: literal-skill`ndescription: |`n  First line`n`n  Second paragraph`n---`n" | Set-Content -LiteralPath $literalPath
        (Read-SkillMetadata $literalPath).description | Should -Be "First line`n`nSecond paragraph"

        $foldedPath = Join-Path $TestDrive 'folded.md'
        "---`nname: folded-skill`ndescription: >`n  First line`n  continues`n`n  Second paragraph`n---`n" | Set-Content -LiteralPath $foldedPath
        (Read-SkillMetadata $foldedPath).description | Should -Be "First line continues`n`nSecond paragraph"
    }

    It 'enforces Agent Skills identity limits and treats owned unknown fields as errors' {
        $path = Join-Path $TestDrive 'invalid.md'
        "---`nname: Bad--Name`ndescription: fixture`nunknown: value`n---`n" | Set-Content -LiteralPath $path
        $metadata = Read-SkillMetadata $path
        $metadata.valid | Should -BeFalse
        @($metadata.findings.code) | Should -Contain 'name_invalid'
        @($metadata.findings.code) | Should -Contain 'field_unknown'
        @($metadata.findings | Where-Object { $_.code -eq 'field_unknown' -and $_.severity -eq 'error' }).Count | Should -Be 1

        $observed = Read-SkillMetadata $path -Observation
        @($observed.findings | Where-Object { $_.code -eq 'field_unknown' -and $_.severity -eq 'warning' }).Count | Should -Be 1
    }
}
