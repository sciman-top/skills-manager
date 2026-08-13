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
        Write-AuditJsonFile (Get-AuditWorkflowReportPath $resolved) $receipt
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
        It "Emits outer AI prompt file in the audit bundle" {
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
            Set-AuditUserProfileRawText "I maintain repo governance workflows."

            $repo = Join-Path $root "demo-repo"
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            Add-AuditTargetConfigEntry "demo" ".\demo-repo" | Out-Null
            Mock Get-InstalledSkillFacts { @() }

            $result = Invoke-AuditTargetsScan -Target "demo"
            $promptPath = Join-Path $result.path "outer-ai-prompt.md"

            (Test-Path -LiteralPath $promptPath) | Should -Be $true
            $prompt = Get-Content -LiteralPath $promptPath -Raw
            $prompt | Should -Match "Required Execution Sequence"
            $prompt | Should -Match "单目标扫描"
            $prompt | Should -Match "repo-scan.json"
            $prompt | Should -Match "Blocking Conditions"
            $prompt | Should -Match "无新增建议"
        }
    }

    Context "Recommendation apply" {
        It "Applies selected add/remove recommendations and keeps add indexes stable" {
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
                schema_version = 2
                run_id = "r1"
                target = "demo-target"
                decision_basis = [pscustomobject]@{
                    user_profile_used = $true
                    target_scan_used = $true
                    source_strategy_used = $true
                    summary = "ok"
                }
                new_skills = @(
                    [pscustomobject]@{
                        name = "demo-skill"
                        reason_user_profile = "User needs audit automation."
                        reason_target_repo = "Target repo needs this workflow."
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
                        reason_user_profile = "User needs a second workflow."
                        reason_target_repo = "Target repo also needs this second workflow."
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
                removal_candidates = @(
                    [pscustomobject]@{
                        name = "old-skill"
                        reason_user_profile = "User no longer needs it."
                        reason_target_repo = "Target repo no longer matches it."
                        sources = @("local-fixture")
                        installed = [pscustomobject]@{
                            vendor = "manual"
                            from = "old-skill"
                        }
                    }
                )
                do_not_install = @()
            }
            Set-ContentUtf8 $recommendationsPath ($recommendations | ConvertTo-Json -Depth 20)
            New-AuditValidatedWorkflowReceiptFixture $recommendationsPath

            Mock 构建生效 {}
            Mock Invoke-Doctor { [pscustomobject]@{ pass = $true } }

            $report = Invoke-AuditRecommendationsApply -RecommendationsPath $recommendationsPath -Apply -Yes -AddSelection "2" -RemoveSelection "1"
            $saved = LoadCfg

            $report.success | Should -Be $true
            (Test-Path (Join-Path $root "apply-report.json")) | Should -Be $true
            $report.persisted | Should -Be $true
            $report.changed_counts.add_installed | Should -Be 1
            $report.changed_counts.remove_removed | Should -Be 1
            @($saved.imports).Count | Should -Be 1
            @($saved.mappings).Count | Should -Be 1
            $saved.mappings[0].to | Should -Be "demo-skill-2"
            $report.removal_candidates[0].status | Should -Be "removed"
            Should -Invoke 构建生效 -Times 1 -Exactly
            Should -Invoke Invoke-Doctor -Times 1 -Exactly
        }

        It "Applies selected MCP add/remove recommendations" {
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
                schema_version = 2
                run_id = "r-mcp"
                target = "demo-target"
                decision_basis = [pscustomobject]@{
                    user_profile_used = $true
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
                        reason_user_profile = "User needs docs MCP."
                        reason_target_repo = "Repo workflow needs quick docs lookup."
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
                mcp_removal_candidates = @(
                    [pscustomobject]@{
                        name = "legacy-fetch"
                        reason_user_profile = "User no longer needs this MCP."
                        reason_target_repo = "Repo no longer uses this MCP path."
                        sources = @("local-fixture")
                        installed = [pscustomobject]@{
                            name = "legacy-fetch"
                        }
                    }
                )
            }
            Set-ContentUtf8 $recommendationsPath ($recommendations | ConvertTo-Json -Depth 20)
            New-AuditValidatedWorkflowReceiptFixture $recommendationsPath

            Mock 同步MCP {}
            Mock 构建生效 {}
            Mock Invoke-Doctor { [pscustomobject]@{ pass = $true } }

            $report = Invoke-AuditRecommendationsApply -RecommendationsPath $recommendationsPath -Apply -Yes -McpAddSelection "1" -McpRemoveSelection "1"
            $saved = LoadCfg

            $report.success | Should -Be $true
            $report.persisted | Should -Be $true
            $report.changed_counts.add_installed | Should -Be 0
            $report.changed_counts.mcp_add_added | Should -Be 1
            $report.changed_counts.mcp_remove_removed | Should -Be 1
            @($saved.mcp_servers).Count | Should -Be 1
            $saved.mcp_servers[0].name | Should -Be "context7"
            @($saved.mcp_profiles.profiles.default.enabled).Count | Should -Be 0
            $saved.mcp_profiles.profiles.default.enabled_tools.PSObject.Properties.Match("legacy-fetch").Count | Should -Be 0
            Should -Invoke 同步MCP -Times 1 -Exactly -Scope It
            Should -Invoke 构建生效 -Times 0 -Exactly -Scope It
            Should -Invoke Invoke-Doctor -Times 1 -Exactly -Scope It
        }
    }
}
