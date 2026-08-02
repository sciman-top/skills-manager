$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'skills.ps1')
$fixtureSource = Join-Path $repoRoot 'tests\fixtures\phase3-acceptance'

Describe 'Bounded fixture-only plugin exporter' {
    function New-ExportFixture([string]$Name) {
        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Get-ChildItem -LiteralPath $fixtureSource -Force | Copy-Item -Destination $root -Recurse -Force
        return $root
    }

    It 'exports two reviewed teaching skills with exact round-trip hashes' {
        $root = New-ExportFixture 'success'
        $candidate = Get-Content -Raw (Join-Path $root 'candidate.json') | ConvertFrom-Json
        $out = Join-Path $root 'out\teacher-workflows'
        $result = Export-PluginFixture $candidate $root $out 'EXPORT_PLUGIN_FIXTURE'

        $result.pass | Should Be $true
        $result.status | Should Be 'exported'
        $result.skill_count | Should Be 2
        $result.verification.host_loaded | Should Be 'not_run'
        $result.verification.live_accepted | Should Be 'not_run'
        foreach ($name in @('custom-teacher-courseware-ppt', 'custom-junior-physics-animation')) {
            Get-FileContentHash (Join-Path $out ('skills\{0}\SKILL.md' -f $name)) | Should Be (Get-FileContentHash (Join-Path $root ('sources\{0}\SKILL.md' -f $name)))
        }
    }

    It 'blocks wrong tokens and missing markers with zero durable output' {
        $root = New-ExportFixture 'blocked'
        $candidate = Get-Content -Raw (Join-Path $root 'candidate.json') | ConvertFrom-Json
        $wrongOut = Join-Path $root 'wrong-output'
        $wrong = Export-PluginFixture $candidate $root $wrongOut 'WRONG'
        $wrong.status | Should Be 'blocked'
        $wrong.writes | Should Be 0
        Test-Path -LiteralPath $wrongOut | Should Be $false

        Remove-Item -LiteralPath (Join-Path $root '.skills-manager-fixture') -Force
        $unmarkedOut = Join-Path $root 'unmarked-output'
        $unmarked = Export-PluginFixture $candidate $root $unmarkedOut 'EXPORT_PLUGIN_FIXTURE'
        @($unmarked.findings.code) | Should Contain 'fixture_marker_missing'
        Test-Path -LiteralPath $unmarkedOut | Should Be $false
    }

    It 'blocks outside and existing output paths' {
        $root = New-ExportFixture 'paths'
        $candidate = Get-Content -Raw (Join-Path $root 'candidate.json') | ConvertFrom-Json
        $outside = Join-Path $TestDrive 'outside-plugin'
        @((Export-PluginFixture $candidate $root $outside 'EXPORT_PLUGIN_FIXTURE').findings.code) | Should Contain 'export_output_outside_fixture'
        Test-Path -LiteralPath $outside | Should Be $false

        $existing = Join-Path $root 'existing'; New-Item -ItemType Directory $existing | Out-Null
        @((Export-PluginFixture $candidate $root $existing 'EXPORT_PLUGIN_FIXTURE').findings.code) | Should Contain 'export_output_exists'
    }

    It 'blocks nested reparse points and more than eight source skills' {
        $root = New-ExportFixture 'limits'
        $candidate = Get-Content -Raw (Join-Path $root 'candidate.json') | ConvertFrom-Json
        $source = Join-Path $root 'sources\custom-teacher-courseware-ppt'
        $target = Join-Path $root 'sources\custom-junior-physics-animation'
        New-Item -ItemType Junction -Path (Join-Path $source 'linked') -Target $target | Out-Null
        $reparse = Export-PluginFixture $candidate $root (Join-Path $root 'reparse-output') 'EXPORT_PLUGIN_FIXTURE'
        @($reparse.findings.code) | Should Contain 'candidate_source_tree_reparse_forbidden'

        Remove-Item -LiteralPath (Join-Path $source 'linked') -Force
        $candidate.source_skills = @(1..9 | ForEach-Object { './sources/custom-teacher-courseware-ppt' })
        $limit = Export-PluginFixture $candidate $root (Join-Path $root 'limit-output') 'EXPORT_PLUGIN_FIXTURE'
        @($limit.findings.code) | Should Contain 'candidate_skill_limit_exceeded'
    }

    It 'blocks an output path whose existing ancestor is a Junction' {
        $root = New-ExportFixture 'output-junction'
        $candidate = Get-Content -Raw (Join-Path $root 'candidate.json') | ConvertFrom-Json
        $outside = Join-Path $TestDrive 'junction-target'; New-Item -ItemType Directory -Path $outside | Out-Null
        $junction = Join-Path $root 'redirect'; New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        $result = Export-PluginFixture $candidate $root (Join-Path $junction 'plugin') 'EXPORT_PLUGIN_FIXTURE'
        @($result.findings.code) | Should Contain 'export_path_reparse_forbidden'
        Test-Path -LiteralPath (Join-Path $outside 'plugin') | Should Be $false
    }
}
