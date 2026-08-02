$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'skills.ps1')
$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\phase3-acceptance'

Describe 'Plugin manifest and supply-chain contract' {
    It 'accepts the official-compatible skills-only fixture' {
        $root = Join-Path $fixtureRoot 'valid-plugin'
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $root '.codex-plugin\plugin.json') | ConvertFrom-Json
        $result = Test-PluginManifestContract $manifest $root $true
        $result.pass | Should Be $true
        $result.shape | Should Be 'skills_only'
        $result.provider_calls | Should Be 0
        $result.native_mutations | Should Be 0
    }

    It 'fails closed on missing license and path traversal fixtures' {
        $missingRoot = Join-Path $fixtureRoot 'invalid-missing-license'
        $missing = Get-Content -Raw -LiteralPath (Join-Path $missingRoot '.codex-plugin\plugin.json') | ConvertFrom-Json
        $missingResult = Test-PluginManifestContract $missing $missingRoot $true
        @($missingResult.findings.code) | Should Contain 'plugin_license_invalid'

        $escapeRoot = Join-Path $fixtureRoot 'invalid-path-escape'
        $escape = Get-Content -Raw -LiteralPath (Join-Path $escapeRoot '.codex-plugin\plugin.json') | ConvertFrom-Json
        $escapeResult = Test-PluginManifestContract $escape $escapeRoot $true
        @($escapeResult.findings.code) | Should Contain 'plugin_component_path_invalid'
    }

    It 'rejects invalid SemVer and sensitive properties' {
        $manifest = [pscustomobject]@{ name = 'demo'; version = 'latest'; description = 'demo'; repository = 'https://example.invalid/demo'; license = 'MIT'; skills = './skills/'; access_token = 'fixture' }
        $result = Test-PluginManifestContract $manifest '' $true
        @($result.findings.code) | Should Contain 'plugin_version_invalid'
        @($result.findings.code) | Should Contain 'sensitive_property_forbidden'
    }

    It 'selects the smallest declared plugin shape' {
        (Get-PluginShape ([pscustomobject]@{ skills = './skills/' })) | Should Be 'skills_only'
        (Get-PluginShape ([pscustomobject]@{ mcpServers = './.mcp.json' })) | Should Be 'mcp_only'
        (Get-PluginShape ([pscustomobject]@{ skills = './skills/'; mcpServers = './.mcp.json' })) | Should Be 'skill_mcp'
        (Get-PluginShape ([pscustomobject]@{ mcpServers = './.mcp.json'; apps = './.app.json' })) | Should Be 'mcp_ui'
    }
}
