BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

}
Describe "Doctor Enhancements" {
    Context "Get-DoctorLegacyAutoUpdateTaskStatus" {
        It "recognizes the current runner as externally scheduled" {
            $runner = Join-Path $Root 'scripts\weekly-skills-update.ps1'
            $task = [pscustomobject]@{ Actions = @([pscustomobject]@{ Arguments = ('-File "{0}"' -f $runner) }) }

            $status = Get-DoctorAutoUpdateTaskClassification -Task $task -ExpectedRunner $runner

            $status.state | Should -Be 'external_current'
            $status.action | Should -Be 'none'
            $status.runner_exists | Should -BeTrue
        }

        It "marks the removed legacy runner as stale" {
            $runner = Join-Path $Root 'scripts\weekly-skills-update.ps1'
            $task = [pscustomobject]@{ Actions = @([pscustomobject]@{ Arguments = ('-File "{0}"' -f (Join-Path $Root 'scripts\weekly-auto-update.ps1')) }) }

            $status = Get-DoctorAutoUpdateTaskClassification -Task $task -ExpectedRunner $runner

            $status.state | Should -Be 'stale_legacy'
            $status.action | Should -Be 'manual_repair_or_cleanup'
        }
    }

    Context "Parse-DoctorArgs" {
        It "Parses json/fix options" {
            $opts = Parse-DoctorArgs @("--json", "--fix")
            $opts.json | Should -Be $true
            $opts.fix | Should -Be $true
        }

        It "Parses strict and dry-run-fix options" {
            $opts = Parse-DoctorArgs @("--strict", "--dry-run-fix")
            $opts.strict | Should -Be $true
            $opts.dry_run_fix | Should -Be $true
        }

        It "Allows offline contract only for non-mutating JSON checks" {
            $opts = Parse-DoctorArgs @("--json", "--offline-contract")
            $opts.offline_contract | Should -Be $true

            { Parse-DoctorArgs @("--offline-contract") | Out-Null } | Should -Throw
            { Parse-DoctorArgs @("--json", "--offline-contract", "--strict") | Out-Null } | Should -Throw
            { Parse-DoctorArgs @("--json", "--offline-contract", "--fix") | Out-Null } | Should -Throw
        }

        It "Rejects unknown option" {
            $thrown = $false
            try {
                Parse-DoctorArgs @("--bad-option") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }
    }

    Context "Apply-DoctorFixes" {
        It "Deduplicates targets and removes mappings with missing vendors" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.claude/skills" }
                )
                mappings = @(
                    [pscustomobject]@{ vendor = "vendor-a"; from = "a"; to = "skill-a" },
                    [pscustomobject]@{ vendor = "vendor-missing"; from = "x"; to = "skill-x" }
                )
            }

            $result = Apply-DoctorFixes $cfg
            $result.changed | Should -Be $true
            $result.applied.Count | Should -Be 2
            @($cfg.targets).Count | Should -Be 2
            @($cfg.mappings).Count | Should -Be 1
            $cfg.mappings[0].vendor | Should -Be "vendor-a"
        }

        It "Returns preview without mutating config when preview mode is enabled" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.codex/skills" }
                )
                mappings = @(
                    [pscustomobject]@{ vendor = "vendor-missing"; from = "x"; to = "skill-x" }
                )
            }

            $result = Apply-DoctorFixes $cfg -Preview
            $result.changed | Should -Be $true
            @($cfg.targets).Count | Should -Be 2
            @($cfg.mappings).Count | Should -Be 1
        }
    }

    Context "Get-DoctorConfigRisks" {
        It "Detects duplicate target paths and mapping.to collisions" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.codex/skills" }
                )
                mappings = @(
                    [pscustomobject]@{ vendor = "vendor-a"; from = "a"; to = "skill-x" },
                    [pscustomobject]@{ vendor = "vendor-a"; from = "b"; to = "skill-x" }
                )
            }

            $risks = Get-DoctorConfigRisks $cfg
            ($risks | Where-Object { $_ -like "*targets.path*" }).Count | Should -Be 1
            ($risks | Where-Object { $_ -like "*mappings.to*" }).Count | Should -Be 1
        }

        It "Detects mapping referencing missing vendor" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @()
                mappings = @(
                    [pscustomobject]@{ vendor = "vendor-missing"; from = "a"; to = "skill-a" }
                )
            }

            $risks = Get-DoctorConfigRisks $cfg
            ($risks | Where-Object { $_ -like "*不存在的 vendor*" }).Count | Should -Be 1
        }

        It 'classifies HTTP MCP endpoints as Streamable HTTP and warns only for remote plaintext' {
            $cfg = [pscustomobject]@{
                vendors = @()
                targets = @()
                mappings = @()
                mcp_servers = @(
                    [pscustomobject]@{ name = 'secure'; transport = 'http'; url = 'https://example.invalid/mcp'; bearer_token_env_var = 'MCP_TOKEN' },
                    [pscustomobject]@{ name = 'local'; transport = 'http'; url = 'http://127.0.0.1:8080/mcp' },
                    [pscustomobject]@{ name = 'remote-plain'; transport = 'http'; url = 'http://192.0.2.10/mcp' }
                )
            }

            $diagnostics = @(Get-McpTransportDiagnostics $cfg)
            $risks = @(Get-DoctorConfigRisks $cfg)

            @($diagnostics | Where-Object protocol -eq 'streamable_http').Count | Should -Be 3
            @($diagnostics | Where-Object security -eq 'encrypted').Count | Should -Be 1
            @($diagnostics | Where-Object security -eq 'loopback_plaintext').Count | Should -Be 1
            @($diagnostics | Where-Object warning_code -eq 'remote_plaintext_http').Count | Should -Be 1
            @($risks | Where-Object { $_ -like '*remote-plain*明文 HTTP*' }).Count | Should -Be 1
        }

        It 'reports the active MCP profile and flags a non-empty default profile' {
            $cfg = [pscustomobject]@{
                vendors = @()
                targets = @()
                mappings = @()
                mcp_servers = @(
                    [pscustomobject]@{ name = 'context7'; transport = 'stdio'; command = 'npx'; args = @('-y', 'context7') }
                )
                mcp_profiles = [pscustomobject]@{
                    active = 'default'
                    profiles = [pscustomobject]@{
                        default = [pscustomobject]@{ enabled = @('context7') }
                        off = [pscustomobject]@{ enabled = @() }
                    }
                }
            }

            $controls = Get-DoctorMcpRiskControls $cfg
            $controls.read_only | Should -BeTrue
            $controls.active_profile | Should -Be 'default'
            $controls.active_server_count | Should -Be 1
            $controls.default_profile_empty | Should -BeFalse
            $controls.default_profile_has_active_servers | Should -BeTrue

            $risks = @(Get-DoctorConfigRisks $cfg)
            @($risks | Where-Object { $_ -like '*默认 profile*常驻工具注入*' }).Count | Should -Be 1
        }

        It 'recognizes an empty off profile as the safest read-only state' {
            $cfg = [pscustomobject]@{
                vendors = @()
                targets = @()
                mappings = @()
                mcp_servers = @(
                    [pscustomobject]@{ name = 'context7'; transport = 'stdio'; command = 'npx'; args = @('-y', 'context7') }
                )
                mcp_profiles = [pscustomobject]@{
                    active = 'off'
                    profiles = [pscustomobject]@{
                        off = [pscustomobject]@{ enabled = @() }
                    }
                }
            }

            $controls = Get-DoctorMcpRiskControls $cfg
            $controls.off_profile_empty | Should -BeTrue
            $controls.active_server_count | Should -Be 0
            @(Get-DoctorConfigRisks $cfg) | Should -BeNullOrEmpty
        }
    }

    Context "Test-DoctorColdSkillForm" {
        It "accepts junction-form skills with reachable targets" {
            $hostRoot = Join-Path $TestDrive 'host-ok\skills'
            New-Item -ItemType Directory -Force -Path $hostRoot | Out-Null
            New-Item -ItemType Junction -Path (Join-Path $hostRoot 'capability-router') -Value (Join-Path $Root 'agent\capability-router') | Out-Null

            $result = Test-DoctorColdSkillForm -HostRoot $hostRoot -ExpectedSkillNames @('capability-router')

            $result.ok | Should -BeTrue
            $result.warnings | Should -BeNullOrEmpty
        }

        It "flags copy-form projected skills that break cold-discovery sibling adjacency" {
            $hostRoot = Join-Path $TestDrive 'host-copy\skills'
            $routerCopy = Join-Path $hostRoot 'capability-router'
            New-Item -ItemType Directory -Force -Path $routerCopy | Out-Null
            Set-Content -LiteralPath (Join-Path $routerCopy 'SKILL.md') -Value '# copied router'

            $result = Test-DoctorColdSkillForm -HostRoot $hostRoot -ExpectedSkillNames @('capability-router')

            $result.ok | Should -BeFalse
            ($result.warnings -join "`n") | Should -Match '拷贝形态'
        }

        It "flags dangling junctions whose link target no longer exists" {
            $base = Join-Path $TestDrive 'host-dangling'
            $target = Join-Path $base 'target-skill'
            $hostRoot = Join-Path $base 'skills'
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            New-Item -ItemType Directory -Force -Path $hostRoot | Out-Null
            New-Item -ItemType Junction -Path (Join-Path $hostRoot 'research') -Value $target | Out-Null
            Rename-Item -LiteralPath $target 'target-skill-moved'

            $result = Test-DoctorColdSkillForm -HostRoot $hostRoot -ExpectedSkillNames @('research')

            $result.ok | Should -BeFalse
            ($result.warnings -join "`n") | Should -Match '不可达'
        }

        It "ignores absent skills because the projection diff already reports them" {
            $hostRoot = Join-Path $TestDrive 'host-absent\skills'
            New-Item -ItemType Directory -Force -Path $hostRoot | Out-Null

            $result = Test-DoctorColdSkillForm -HostRoot $hostRoot -ExpectedSkillNames @('missing-skill')

            $result.ok | Should -BeTrue
        }
    }

    Context "Test-DoctorColdCatalogHealth" {
        BeforeAll {
            # Minimal managed source in fixture form: one skill with real hashes
            # so the healthy case passes; drift cases mutate copies of it.
            $script:fakeManaged = Join-Path $TestDrive 'managed'
            New-Item -ItemType Directory -Force -Path (Join-Path $script:fakeManaged '.skills-manager') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $script:fakeManaged 'capability-router') | Out-Null
            New-Item -ItemType Directory -Force -Path (Join-Path $script:fakeManaged 'skill-a') | Out-Null
            Set-Content -LiteralPath (Join-Path $script:fakeManaged 'skill-a\SKILL.md') -Value '# fixture skill-a' -NoNewline
            $entryHash = (Get-FileHash -LiteralPath (Join-Path $script:fakeManaged 'skill-a\SKILL.md') -Algorithm SHA256).Hash.ToLowerInvariant()
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $packageHash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(('SKILL.md|' + $entryHash)))) | ForEach-Object { $_.ToString('x2') }) -join ''
            }
            finally { $sha.Dispose() }
            $catalog = [ordered]@{
                schema_version = 1
                decision_owner = 'host_ai'
                semantic_routing_performed = $false
                domains = @(@{ name = 'demo'; purpose = 'fixture'; skill_names = @('skill-a') })
                skills = @(
                    [ordered]@{
                        name = 'skill-a'
                        description = 'fixture skill'
                        relative_path = '..\skill-a\SKILL.md'
                        entrypoint_sha256 = $entryHash
                        package_sha256 = $packageHash
                        load_side_effect = 'read_only'
                        side_effect = 'read_only'
                        domains = @('demo')
                    }
                )
                catalog_fingerprint = ('0' * 64)
            }
            $catalogJson = $catalog | ConvertTo-Json -Depth 10
            Set-Content -LiteralPath (Join-Path $script:fakeManaged '.skills-manager\catalog.json') -Value $catalogJson -NoNewline
            Set-Content -LiteralPath (Join-Path $script:fakeManaged 'capability-router\catalog.json') -Value $catalogJson -NoNewline
        }

        It "passes on a consistent managed source with matching mirrors" {
            $result = Test-DoctorColdCatalogHealth -ManagedSourceRoot $script:fakeManaged

            $result.ok | Should -BeTrue
            $result.warnings | Should -BeNullOrEmpty
        }

        It "passes on the current repository managed source" {
            $agentRoot = Join-Path $Root 'agent'
            if (-not (Test-Path -LiteralPath (Join-Path $agentRoot '.skills-manager\catalog.json') -PathType Leaf)) {
                Set-ItResult -Skipped -Because 'agent/ catalog not built in this checkout'
                return
            }

            $result = Test-DoctorColdCatalogHealth -ManagedSourceRoot $agentRoot

            $result.ok | Should -BeTrue
            $result.warnings | Should -BeNullOrEmpty
        }

        It "flags byte-drift between the two catalog mirrors" {
            $driftedMirror = Join-Path $TestDrive 'mirror-drift\catalog.json'
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $driftedMirror) | Out-Null
            $original = Get-Content -LiteralPath (Join-Path $script:fakeManaged 'capability-router\catalog.json') -Raw
            Set-Content -LiteralPath $driftedMirror -Value ($original + ' ') -NoNewline

            $result = Test-DoctorColdCatalogHealth -ManagedSourceRoot $script:fakeManaged -RouterCatalogMirrorPath $driftedMirror

            $result.ok | Should -BeFalse
            ($result.warnings -join "`n") | Should -Match '镜像字节不一致'
        }

        It "flags entrypoint hash drift" {
            $drifted = Join-Path $TestDrive 'entry-drift'
            Copy-Item -LiteralPath $script:fakeManaged -Destination $drifted -Recurse -Force
            Set-Content -LiteralPath (Join-Path $drifted 'skill-a\SKILL.md') -Value '# tampered content' -NoNewline

            $result = Test-DoctorColdCatalogHealth -ManagedSourceRoot $drifted

            $result.ok | Should -BeFalse
            ($result.warnings -join "`n") | Should -Match '入口哈希漂移'
        }

        It "flags package hash drift for sampled skills" {
            $drifted = Join-Path $TestDrive 'package-drift'
            Copy-Item -LiteralPath $script:fakeManaged -Destination $drifted -Recurse -Force
            $catalogPath = Join-Path $drifted '.skills-manager\catalog.json'
            $catalogDoc = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
            $catalogDoc.skills[0].package_sha256 = ('f' * 64)
            Set-Content -LiteralPath $catalogPath -Value ($catalogDoc | ConvertTo-Json -Depth 10) -NoNewline
            Copy-Item -LiteralPath $catalogPath -Destination (Join-Path $drifted 'capability-router\catalog.json') -Force

            $result = Test-DoctorColdCatalogHealth -ManagedSourceRoot $drifted

            $result.ok | Should -BeFalse
            ($result.warnings -join "`n") | Should -Match '包哈希漂移'
        }
    }

}
