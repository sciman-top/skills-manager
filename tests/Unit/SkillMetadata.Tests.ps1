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

    It 'preserves standard metadata maps and allowed-tools strings' {
        $path = Join-Path $TestDrive 'standard-fields.md'
        @'
---
name: standard-fields
description: fixture
license: Apache-2.0
compatibility: Requires pwsh 7 and git
metadata:
  author: example-org
  version: "1.0"
allowed-tools: Bash(git:*) Read
---
'@ | Set-Content -LiteralPath $path

        $metadata = Read-SkillMetadata $path

        $metadata.valid | Should -BeTrue
        $metadata.fields.metadata.author | Should -Be 'example-org'
        $metadata.fields.metadata.version | Should -Be '1.0'
        $metadata.fields.'allowed-tools' | Should -Be 'Bash(git:*) Read'
        @($metadata.findings).Count | Should -Be 0
    }

    It 'validates optional field shape and nested non-standard metadata' {
        $path = Join-Path $TestDrive 'invalid-standard-fields.md'
        @'
---
name: invalid-standard-fields
description: fixture
compatibility:
allowed-tools:
metadata:
  openclaw:
    emoji: wrench
---
'@ | Set-Content -LiteralPath $path

        $owned = Read-SkillMetadata $path
        $owned.valid | Should -BeFalse
        @($owned.findings.code) | Should -Contain 'compatibility_invalid'
        @($owned.findings.code) | Should -Contain 'allowed_tools_invalid'
        @($owned.findings.code) | Should -Contain 'metadata_value_invalid'

        $observed = Read-SkillMetadata $path -Observation
        $observed.valid | Should -BeTrue
        @($observed.findings | Where-Object code -eq 'metadata_value_invalid').Count | Should -BeGreaterThan 0
    }

    It 'rejects non-string YAML scalars for Agent Skills string fields' {
        foreach ($case in @(
                [pscustomobject]@{ field = 'name'; value = 'true'; code = 'name_type_invalid'; name = 'true' },
                [pscustomobject]@{ field = 'description'; value = 'true'; code = 'description_type_invalid'; name = 'typed-fields' },
                [pscustomobject]@{ field = 'license'; value = '123'; code = 'license_invalid'; name = 'typed-fields' },
                [pscustomobject]@{ field = 'compatibility'; value = 'false'; code = 'compatibility_invalid'; name = 'typed-fields' },
                [pscustomobject]@{ field = 'allowed-tools'; value = '[]'; code = 'allowed_tools_invalid'; name = 'typed-fields' }
            )) {
            $path = Join-Path $TestDrive ("{0}.md" -f $case.field)
            $description = if ($case.field -eq 'description') { $case.value } else { 'fixture' }
            $extra = if ($case.field -in @('name', 'description')) { '' } else { "`n$($case.field): $($case.value)" }
            "---`nname: $($case.name)`ndescription: $description$extra`n---`n" | Set-Content -LiteralPath $path

            $metadata = Read-SkillMetadata $path
            $metadata.valid | Should -BeFalse
            @($metadata.findings.code) | Should -Contain $case.code

            if ($case.field -in @('name', 'description')) {
                $observed = Read-SkillMetadata $path -Observation
                @($observed.findings | Where-Object { $_.code -eq $case.code -and $_.severity -eq 'error' }).Count | Should -Be 1
            }
        }

        $quotedPath = Join-Path $TestDrive 'quoted-scalars.md'
        "---`nname: quoted-scalars`ndescription: 'true'`nlicense: '123'`nallowed-tools: '[]'`n---`n" | Set-Content -LiteralPath $quotedPath
        (Read-SkillMetadata $quotedPath).valid | Should -BeTrue
    }

    It 'classifies known host and vendor extensions separately from unknown fields' {
        $path = Join-Path $TestDrive 'extensions.md'
        @'
---
name: extensions
description: fixture
version: 2.0.0
user-invocable: true
context: fork
future-field: value
---
'@ | Set-Content -LiteralPath $path

        $metadata = Read-SkillMetadata $path -Observation

        @($metadata.findings | Where-Object code -eq 'field_vendor_extension').Count | Should -Be 1
        @($metadata.findings | Where-Object code -eq 'field_host_extension').Count | Should -Be 2
        @($metadata.findings | Where-Object code -eq 'field_unknown').Count | Should -Be 1
    }
}
