Describe 'skills.json versioned schema contract' {
    BeforeAll {
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\verify-skills-config.ps1'
$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\config-schema'
function Invoke-ConfigVerifier([string]$ConfigPath, [string]$Mode = 'enforce', [switch]$External, [switch]$RequireDeclaredSchemaVersion) {
        $versionArgs = if ($RequireDeclaredSchemaVersion) { @{ RequireDeclaredSchemaVersion = $true } } else { @{} }
        $output = if ($External) {
            @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ConfigPath $ConfigPath -Mode $Mode @versionArgs 2>&1)
        }
        else {
            @(& $scriptPath -ConfigPath $ConfigPath -Mode $Mode -NoExit @versionArgs 2>&1)
        }
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; result = (($output -join "`n") | ConvertFrom-Json) }
    }
}

    It 'accepts the current repository config without modifying it' {
        $configPath = Join-Path $repoRoot 'skills.json'
        $before = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
        $run = Invoke-ConfigVerifier $configPath -External
        $after = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash

        $run.exit_code | Should -Be 0
        $run.result.valid | Should -Be $true
        $run.result.finding_count | Should -Be 0
        $run.result.config_version | Should -Be 3
        $run.result.version_source | Should -Be 'declared'
        $before | Should -Be $after
        $run.result.config_sha256_before | Should -Be $run.result.config_sha256_after
    }

    It 'reads explicit schema v1 for migration with a deprecation observation' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'known-good-v1.json')
        $run.exit_code | Should -Be 0
        $run.result.config_version | Should -Be 1
        $run.result.version_source | Should -Be 'declared'
        @($run.result.observations | Where-Object code -eq 'legacy_schema_v1_deprecated').Count | Should -Be 1
    }

    It 'reads a missing version as legacy v1 with an observation' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'legacy-v1.json')
        $run.exit_code | Should -Be 0
        $run.result.valid | Should -Be $true
        $run.result.config_version | Should -Be 1
        $run.result.version_source | Should -Be 'legacy_default'
        @($run.result.observations | Where-Object code -eq 'legacy_schema_version_missing').Count | Should -Be 1
    }

    It 'fails closed when a declared version is required for a legacy config' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'legacy-v1.json') -RequireDeclaredSchemaVersion
        $run.exit_code | Should -Be 1
        $run.result.valid | Should -Be $false
        @($run.result.findings | Where-Object code -eq 'schema_version_required').Count | Should -Be 1
    }

    It 'keeps legacy SSE readable only in schema v1 and rejects it in schema v2' {
        $base = [ordered]@{
            sync_mode = 'link'
            vendors = @()
            targets = @()
            mappings = @()
            imports = @()
            mcp_servers = @([ordered]@{ name = 'legacy'; transport = 'sse'; url = 'https://example.invalid/mcp' })
            mcp_targets = @()
        }
        $v1 = Join-Path $TestDrive 'legacy-sse-v1.json'
        $v2 = Join-Path $TestDrive 'legacy-sse-v2.json'
        $v1Config = [ordered]@{ schema_version = 1 }
        $v2Config = [ordered]@{ schema_version = 2 }
        foreach ($key in $base.Keys) { $v1Config[$key] = $base[$key]; $v2Config[$key] = $base[$key] }
        $v1Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $v1 -Encoding utf8
        $v2Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $v2 -Encoding utf8

        $legacy = Invoke-ConfigVerifier $v1
        $current = Invoke-ConfigVerifier $v2

        $legacy.exit_code | Should -Be 0
        @($legacy.result.observations | Where-Object code -eq 'legacy_sse_transport_deprecated').Count | Should -Be 1
        $current.exit_code | Should -Be 1
        @($current.result.findings | Where-Object code -eq 'enum_invalid').Count | Should -Be 1
    }

    $invalidCases = @(
        @{ file = 'wrong-type.json'; code = 'type_mismatch' },
        @{ file = 'unknown-enum.json'; code = 'enum_invalid' },
        @{ file = 'unsafe-path.json'; code = 'unsafe_relative_path' }
    )
    It 'fails closed for <file>' -ForEach $invalidCases {
            $path = Join-Path $fixtureRoot $file
            $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            $run = Invoke-ConfigVerifier $path
            $after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            $run.exit_code | Should -Be 1
            $run.result.valid | Should -Be $false
            @($run.result.findings | Where-Object code -eq $code).Count | Should -BeGreaterThan 0
            $before | Should -Be $after
    }

    It 'reports invalid input in observe mode without exposing the rejected value' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'unsafe-path.json') 'observe'
        $serialized = $run.result | ConvertTo-Json -Depth 10
        $run.exit_code | Should -Be 0
        $run.result.pass | Should -Be $true
        $run.result.valid | Should -Be $false
        $run.result.would_block | Should -Be $true
        $serialized | Should -Not -Match '\.\./escape'
    }

    It 'fails closed when a discovery domain references a non-canonical skill' {
        $config = Get-Content -LiteralPath (Join-Path $repoRoot 'skills.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $config.skill_projection.discovery_catalog.domain_memberships.engineering += 'missing-canonical-skill'
        $configPath = Join-Path $TestDrive 'dangling-domain-membership.json'
        $config | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $configPath -Encoding UTF8

        $run = Invoke-ConfigVerifier $configPath

        $run.exit_code | Should -Be 1
        $run.result.valid | Should -Be $false
        @($run.result.findings | Where-Object code -eq 'discovery_membership_unknown').Count | Should -Be 1
    }

    It 'keeps the declarative schema parseable and documents compatibility and secret policy' {
        $schema = Get-Content -LiteralPath (Join-Path $repoRoot 'config\skills.schema.json') -Raw | ConvertFrom-Json
        $schema.'$schema' | Should -Be 'https://json-schema.org/draft/2020-12/schema'
        $schema.properties.schema_version.const | Should -Be 3
        $schema.additionalProperties | Should -Be $false
        @($schema.'$defs'.mcpServer.properties.transport.enum) | Should -Not -Contain 'sse'
        $schema.'$defs'.mapping.properties.to.pattern | Should -Be '^[a-z0-9]+(?:-[a-z0-9]+)*$'
        @($schema.'$defs'.target.properties.host.enum) | Should -Be @('codex', 'claude', 'zcode')
        $schema.'$defs'.skillProjection.properties.projection_profiles.'$ref' | Should -Be '#/$defs/projectionProfiles'
        $schema.'$defs'.projectionProfiles.properties.schema_version.const | Should -Be 1
        $schema.'$defs'.skillProjection.properties.native_agent_bridge.'$ref' | Should -Be '#/$defs/nativeAgentBridge'
        $schema.'$defs'.nativeAgentBridge.properties.target_root.const | Should -Be '~/.codex/agents'
        @($schema.'$defs'.nativeAgentBridge.required) | Should -Contain 'definitions'
        @($schema.'$defs'.skillProjection.properties.PSObject.Properties.Name) | Should -Not -Contain 'aliases'
        @($schema.'$defs'.nativeProjection.properties.PSObject.Properties.Name) | Should -Not -Contain 'apply_requires_token'
        $schema.'x-compatibility-policy'.missing_schema_version | Should -Be 'legacy-v1-observation'
        $schema.'x-compatibility-policy'.declared_schema_v1 | Should -Be 'runtime-read-migration-only'
        $schema.'x-compatibility-policy'.declared_schema_v2 | Should -Be 'runtime-read-migration-only'
        $schema.'x-compatibility-policy'.unknown_properties | Should -Be 'v3-fail-closed'
        $schema.'x-secret-policy'.validator_output | Should -Be 'code-path-message-only'
    }

    It 'accepts schema v3 with only allowlisted top-level fields' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'known-good-v3.json')
        $run.exit_code | Should -Be 0
        $run.result.valid | Should -Be $true
        $run.result.finding_count | Should -Be 0
        $run.result.config_version | Should -Be 3
    }

    It 'fails closed for a v3 config with an unknown top-level field' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'v3-unknown-top-level.json')
        $run.result.valid | Should -Be $false
        @($run.result.findings | Where-Object code -eq 'unknown_top_level_field_v3').Count | Should -Be 1
    }

    It 'observes a v2 unknown top-level field without failing' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'v2-unknown-top-level.json')
        $run.exit_code | Should -Be 0
        $run.result.valid | Should -Be $true
        @($run.result.observations | Where-Object code -eq 'unknown_top_level_field_v2_observe').Count | Should -Be 1
    }

    It 'rejects a declared schema version beyond the supported range' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'v4-unsupported.json')
        $run.result.valid | Should -Be $false
        @($run.result.findings | Where-Object code -eq 'schema_version_invalid').Count | Should -Be 1
    }

    It 'enforces the v3 top-level allowlist through the Assert-Cfg CLI entrance' {
        # Mirror the verifier's dot-source chain so Assert-Cfg runs with its
        # real dependencies; the fixture must fail closed on the CLI path too,
        # not only through the report-based verifier.
        $operationPlanSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1') -Raw -Encoding UTF8
        $skillCatalogSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Domain\SkillCatalog.ps1') -Raw -Encoding UTF8
        $coreSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Core.ps1') -Raw -Encoding UTF8
        $configSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Config.ps1') -Raw -Encoding UTF8
        . ([scriptblock]::Create($operationPlanSource))
        . ([scriptblock]::Create($skillCatalogSource))
        . (Join-Path $repoRoot 'src\Application\SkillProjection.ps1')
        . ([scriptblock]::Create($coreSource))
        . ([scriptblock]::Create($configSource))
        $cfg = Get-Content -LiteralPath (Join-Path $fixtureRoot 'v3-unknown-top-level.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        { Assert-Cfg $cfg } | Should -Throw '*顶层字段未被 schema v3 允许*'
    }
}
