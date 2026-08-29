BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

    $script:originalWorkspaceState = @{}
    foreach ($name in @('Root', 'CfgPath', 'LogPath', 'VendorDir', 'AgentDir', 'OverridesDir', 'ManualDir', 'ImportDir', 'DryRun')) {
        $script:originalWorkspaceState[$name] = Get-Variable -Name $name -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    }

    function Set-AuditTestWorkspace([string]$root) {
        $values = @{
            Root = $root
            CfgPath = Join-Path $root "skills.json"
            LogPath = Join-Path $root "build.log"
            VendorDir = Join-Path $root "vendor"
            AgentDir = Join-Path $root "agent"
            OverridesDir = Join-Path $root "overrides"
            ManualDir = Join-Path $root "manual"
            ImportDir = Join-Path $root "imports"
            DryRun = $false
        }
        foreach ($entry in $values.GetEnumerator()) {
            Set-Variable -Name $entry.Key -Scope 1 -Value $entry.Value
            Set-Variable -Name $entry.Key -Scope Script -Value $entry.Value
            Set-Variable -Name $entry.Key -Scope Global -Value $entry.Value
        }
        EnsureDir $VendorDir
        EnsureDir $AgentDir
        EnsureDir $OverridesDir
        EnsureDir $ManualDir
        EnsureDir $ImportDir
    }

    function New-AuditValidatedWorkflowReceiptFixture([string]$RecommendationsPath) {
        $resolved = [IO.Path]::GetFullPath($RecommendationsPath)
        $state = Get-AuditWorkflowInputState $resolved
        $receipt = [pscustomobject][ordered]@{
            schema_version = 1
            workflow = 'recommendations_validate_dry_run'
            generated_at = [datetimeoffset]::UtcNow.ToString('o')
            success = $true
            persisted = $false
            recommendations_path = $resolved
            recommendations_sha256 = Get-FileContentHash $resolved
            stages = [pscustomobject]@{
                recommendations_validation = [pscustomobject]@{ status = 'passed' }
                preflight = [pscustomobject]@{ status = 'passed' }
                dry_run = [pscustomobject]@{ status = 'passed' }
                input_stability = [pscustomobject]@{ status = 'passed' }
            }
            input_stability = [pscustomobject]@{ matched = $true; after_dry_run = $state }
        }
        Write-AuditReceiptSection $resolved "workflow" $receipt | Out-Null
    }

    function New-E2EAuditSnapshot([string]$Path, [string]$RunId) {
        $live = Get-AuditLiveInstalledState
        $targetProfile = [pscustomobject]@{ schema_version=1; derivation="target_scans_only"; summary="test scan profile"; target_names=@("demo"); languages=@("powershell"); package_managers=@(); frameworks=@(); build_commands=@(); test_commands=@(); capabilities=@(); agent_rule_files=@(); notable_files=@() }
        $installedState = [pscustomobject]@{
            snapshot_kind = "audit_input"; captured_at = (Get-Date).ToString("o")
            live_fingerprint = [string]$live.fingerprint
            live_configured_supply_fingerprint = if ($live.PSObject.Properties.Match("configured_supply_fingerprint").Count -gt 0) { [string]$live.configured_supply_fingerprint } else { '' }
            live_external_skill_fingerprint = if ($live.PSObject.Properties.Match("external_skill_fingerprint").Count -gt 0) { [string]$live.external_skill_fingerprint } else { "" }
            live_mcp_fingerprint = if ($live.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0) { [string]$live.mcp_fingerprint } else { "" }
            skills = @(if ($live.PSObject.Properties.Match('profile_selected_skills').Count -gt 0) { @($live.profile_selected_skills) } else { @() })
            configured_supply_skills = @(if ($live.PSObject.Properties.Match('configured_supply_skills').Count -gt 0) { @($live.configured_supply_skills) } else { @() })
            external_skills=@(); mcp_servers=@(); host_projection=$null
        }
        Write-AuditJsonFile $Path ([pscustomobject]@{
            schema_version=2; run_id=$RunId; mode="target-repo"; prompt_contract_version=(Get-AuditPromptContractVersion)
            target_profile=$targetProfile; installed_state=$installedState; target_scans=@([pscustomobject]@{ target=[pscustomobject]@{ name="demo" }; detected=[pscustomobject]@{ languages=@("powershell"); package_managers=@(); frameworks=@(); build_commands=@(); test_commands=@(); capabilities=@(); agent_rule_files=@(); notable_files=@() }; risks=@() }); source_strategy=[pscustomobject]@{ mode="target-repo"; sources=@(); evidence_policy=$null; decision_quality_policy=$null }
            decision_insights=[pscustomobject]@{ derivation="target_scans_only"; keywords=[pscustomobject]@{ target_profile=@("audit"); target_repo=@("repo"); installed_state=@("skills") } }
        })
    }

}
AfterAll {
    foreach ($entry in $script:originalWorkspaceState.GetEnumerator()) {
        Set-Variable -Name $entry.Key -Scope Global -Value $entry.Value
        Set-Variable -Name $entry.Key -Scope Script -Value $entry.Value
    }
}
Describe "Skill Audit E2E" {
    Context "Audit bundle" {
        It "Emits exactly snapshot recommendations and receipt files" {
            $root = Join-Path $TestDrive "ws-skill-audit-bundle"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-AuditTestWorkspace $root

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "placeholder"; repo = "https://example.com/placeholder.git"; ref = "main" })
                targets = @([pscustomobject]@{ path = (Join-Path $root "out\skills") })
                mappings = @()
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
            }
            SaveCfg $cfg
            Initialize-AuditTargetsConfig | Out-Null
            $repo = Join-Path $root "demo-repo"
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            Add-AuditTargetConfigEntry "demo" ".\demo-repo" | Out-Null
            $repoTwo = Join-Path $root "demo-repo-two"
            New-Item -ItemType Directory -Path $repoTwo -Force | Out-Null
            Add-AuditTargetConfigEntry "demo-two" ".\demo-repo-two" | Out-Null
            Mock Get-InstalledSkillFacts { @() }

            $result = Invoke-AuditTargetsScan -Target "demo"
            @((Get-ChildItem -LiteralPath $result.path -File).Name | Sort-Object) -join ',' | Should -Be 'receipt.json,recommendations.json,snapshot.json'
            $snapshot = Get-ContentUtf8 (Join-Path $result.path "snapshot.json") | ConvertFrom-Json
            $recommendations = Get-ContentUtf8 (Join-Path $result.path "recommendations.json") | ConvertFrom-Json
            $receipt = Get-ContentUtf8 (Join-Path $result.path "receipt.json") | ConvertFrom-Json

            $snapshot.run_id | Should -Be $result.run_id
            @($snapshot.target_scans).Count | Should -Be 2
            $recommendations.target | Should -Be "*"
            $snapshot.scan_contract.aggregation | Should -Be "all_enabled_targets"
            $snapshot.target_profile.scope | Should -Be "portfolio"
            $snapshot.target_profile.schema_version | Should -Be 3
            $snapshot.target_profile.prioritized_needs.ranking_method | Should -Be "role_then_source_coverage_v2"
            $snapshot.target_profile.prioritized_needs.policy | Should -Contain "Raw evidence count does not determine priority; source-backed distinct target coverage is capped to avoid large-repository bias."
            $snapshot.native_ai_review.decision_owner | Should -Be "host_ai"
            $snapshot.native_ai_review.schema_version | Should -Be 2
            $snapshot.native_ai_review.mutation_policy | Should -Match "recommendations.json only"
            $recommendations.run_id | Should -Be $result.run_id
            $receipt.scan.success | Should -Be $true
            $receipt.persisted | Should -Be $false
        }
    }

    Context "Recommendation apply" {
        It "Applies a selected add recommendation and keeps add indexes stable" {
            $root = Join-Path $TestDrive "ws-skill-audit-apply"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-AuditTestWorkspace $root

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "placeholder"; repo = "https://example.com/placeholder.git"; ref = "main" })
                targets = @([pscustomobject]@{ path = (Join-Path $root "out\skills") })
                mappings = @()
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
            }
            SaveCfg $cfg

            $installedSkillDir = Join-Path $root "imports\\old-skill"
            New-Item -ItemType Directory -Path $installedSkillDir -Force | Out-Null
            Set-Content -Path (Join-Path $installedSkillDir "SKILL.md") -Value "---`nname: old-skill`ndescription: Old skill.`n---`nUse when old."
            $cfg = LoadCfg
            $cfg.imports += [pscustomobject]@{ name = "old-skill"; repo = "https://example.com/old.git"; ref = "main"; skill = "."; mode = "manual" }
            $cfg.mappings += [pscustomobject]@{ vendor = "manual"; from = "old-skill"; to = "old-skill" }
            SaveCfg $cfg

            $skillRepo = Join-Path $TestDrive "skill-source"
            New-Item -ItemType Directory -Path $skillRepo -Force | Out-Null
            Set-Content -Path (Join-Path $skillRepo "SKILL.md") -Value "---`nname: demo-skill`ndescription: Demo skill.`n---`nUse when testing audit apply."
            $zip = Join-Path $TestDrive "skill-source.zip"
            Compress-Archive -Path (Join-Path $skillRepo "*") -DestinationPath $zip -Force

            $skillRepo2 = Join-Path $TestDrive "skill-source-2"
            New-Item -ItemType Directory -Path $skillRepo2 -Force | Out-Null
            Set-Content -Path (Join-Path $skillRepo2 "SKILL.md") -Value "---`nname: demo-skill-2`ndescription: Demo skill 2.`n---`nUse when testing audit apply."
            $zip2 = Join-Path $TestDrive "skill-source-2.zip"
            Compress-Archive -Path (Join-Path $skillRepo2 "*") -DestinationPath $zip2 -Force

            $recommendationsPath = Join-Path $root "recommendations.json"
            $recommendations = [pscustomobject]@{
                schema_version = 3
                run_id = "r1"
                target = "demo-target"
                decision_basis = [pscustomobject]@{
                    target_profile_used = $true
                    target_scan_used = $true
                    source_strategy_used = $true
                    summary = "ok"
                }
                new_skills = @(
                    [pscustomobject]@{
                        name = "demo-skill"
                        reason_target_profile = "User needs audit automation."
                        install = [pscustomobject]@{
                            repo = $zip
                            skill = "."
                            ref = "main"
                            mode = "manual"
                        }
                        confidence = "high"
                        sources = @("local-fixture")
                    },
                    [pscustomobject]@{
                        name = "demo-skill-2"
                        reason_target_profile = "User needs a second workflow."
                        install = [pscustomobject]@{
                            repo = $zip2
                            skill = "."
                            ref = "main"
                            mode = "manual"
                        }
                        confidence = "high"
                        sources = @("local-fixture")
                    }
                )
                overlap_findings = @()
                removal_candidates = @()
                do_not_install = @()
            }
            Set-ContentUtf8 $recommendationsPath ($recommendations | ConvertTo-Json -Depth 20)
            New-E2EAuditSnapshot (Join-Path $root "snapshot.json") "r1"
            New-AuditValidatedWorkflowReceiptFixture $recommendationsPath

            Mock 构建生效 {}
            Mock Invoke-Doctor { [pscustomobject]@{ pass = $true } }

            $report = Invoke-AuditRecommendationsApply -RecommendationsPath $recommendationsPath -Apply -Yes -AddSelection "2"
            $saved = LoadCfg

            $report.success | Should -Be $true
            (Test-Path (Join-Path $root "receipt.json")) | Should -Be $true
            (Get-ContentUtf8 (Join-Path $root "receipt.json") | ConvertFrom-Json).apply.persisted | Should -Be $true
            $report.persisted | Should -Be $true
            $report.changed_counts.add_installed | Should -Be 1
            $report.changed_counts.remove_removed | Should -Be 0
            @($saved.imports).Count | Should -Be 2
            @($saved.mappings).Count | Should -Be 2
            $saved.mappings[1].to | Should -Be "demo-skill-2"
            Should -Invoke 构建生效 -Times 1 -Exactly
            Should -Invoke Invoke-Doctor -Times 1 -Exactly
        }

        It "Applies a selected MCP add recommendation" {
            $root = Join-Path $TestDrive "ws-skill-audit-apply-mcp"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-AuditTestWorkspace $root

            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "placeholder"; repo = "https://example.com/placeholder.git"; ref = "main" })
                targets = @([pscustomobject]@{ path = (Join-Path $root "out\skills") })
                mappings = @()
                imports = @()
                mcp_servers = @(
                    [pscustomobject]@{
                        name = "legacy-fetch"
                        transport = "stdio"
                        command = "node"
                        args = @("server.js")
                    }
                )
                mcp_profiles = [pscustomobject]@{
                    active = "default"
                    profiles = [pscustomobject]@{
                        default = [pscustomobject]@{
                            enabled = @("legacy-fetch")
                            enabled_tools = [pscustomobject]@{
                                "legacy-fetch" = @("fetch")
                            }
                        }
                    }
                }
                mcp_targets = @()
                update_force = $false
                sync_mode = "sync"
            }
            SaveCfg $cfg

            $recommendationsPath = Join-Path $root "recommendations-mcp.json"
            $recommendations = [pscustomobject]@{
                schema_version = 3
                run_id = "r-mcp"
                target = "demo-target"
                decision_basis = [pscustomobject]@{
                    target_profile_used = $true
                    target_scan_used = $true
                    source_strategy_used = $true
                    summary = "ok"
                }
                new_skills = @()
                overlap_findings = @()
                removal_candidates = @()
                do_not_install = @()
                mcp_new_servers = @(
                    [pscustomobject]@{
                        name = "context7"
                        reason_target_profile = "User needs docs MCP."
                        confidence = "high"
                        sources = @("local-fixture")
                        server = [pscustomobject]@{
                            name = "context7"
                            transport = "stdio"
                            command = "npx"
                            args = @("-y", "@upstash/context7-mcp")
                        }
                    }
                )
                mcp_removal_candidates = @()
            }
            Set-ContentUtf8 $recommendationsPath ($recommendations | ConvertTo-Json -Depth 20)
            New-E2EAuditSnapshot (Join-Path $root "snapshot.json") "r-mcp"
            New-AuditValidatedWorkflowReceiptFixture $recommendationsPath

            Mock 同步MCP {}
            Mock 构建生效 {}
            Mock Invoke-Doctor { [pscustomobject]@{ pass = $true } }

            $report = Invoke-AuditRecommendationsApply -RecommendationsPath $recommendationsPath -Apply -Yes -McpAddSelection "1"
            $saved = LoadCfg

            $report.success | Should -Be $true
            $report.persisted | Should -Be $true
            $report.changed_counts.add_installed | Should -Be 0
            $report.changed_counts.mcp_add_added | Should -Be 1
            $report.changed_counts.mcp_remove_removed | Should -Be 0
            @($saved.mcp_servers).Count | Should -Be 2
            @($saved.mcp_servers | Where-Object name -eq "context7").Count | Should -Be 1
            @($saved.mcp_profiles.profiles.default.enabled) | Should -Contain "legacy-fetch"
            $saved.mcp_profiles.profiles.default.enabled_tools.PSObject.Properties.Match("legacy-fetch").Count | Should -Be 1
            Should -Invoke 同步MCP -Times 1 -Exactly -Scope It
            Should -Invoke 构建生效 -Times 0 -Exactly -Scope It
            Should -Invoke Invoke-Doctor -Times 1 -Exactly -Scope It
        }
    }
}
