function Set-RouterTestSkill([string]$Root, [string]$Folder, [string]$Name, [string]$Description) {
    $dir = Join-Path $Root $Folder
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'SKILL.md'
    Set-Content -LiteralPath $path -Encoding UTF8 -Value "---`nname: $Name`ndescription: $Description`n---`n`n# $Name"
    return [pscustomobject]@{ name = $Name; description = $Description; path = $path; source_root = $Root; is_system = $false }
}

Describe 'Capability router meta-skill' {
    BeforeEach {
        $scriptPath = Join-Path $PSScriptRoot '..\..\overrides\capability-router\scripts\route-capability.ps1'
        $skillRoot = Join-Path $TestDrive 'skills'
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        $debug = Set-RouterTestSkill $skillRoot 'debug-dotnet' 'debug:dotnet' 'Debug .NET, ASP.NET Core, and WPF runtime failures.'
        $physics = Set-RouterTestSkill $skillRoot 'physics' 'custom-junior-physics-animation' 'Build junior middle school physics animations and simulations.'
        $grill = Set-RouterTestSkill $skillRoot 'grill' 'grill-with-docs' 'Grill a design through an interview about assumptions and tradeoffs.'
        $draft = Set-RouterTestSkill $skillRoot 'draft' 'draft-spec' 'Draft a review-only PRD or specification; do not use for implementation or refactoring.'
        $playwrightSkill = Set-RouterTestSkill $skillRoot 'playwright-skill' 'playwright' 'Use Playwright CLI for browser automation.'
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        [ordered]@{
            schema_version = 2
            active_profile = 'default'
            active = @($physics)
            canonical = @($debug, $physics, $grill, $draft, $playwrightSkill)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $policyPath = Join-Path $TestDrive 'routing-policy.json'
        [ordered]@{
            schema_version = 2
            mode = 'observe'
            groups = @(
                [ordered]@{
                    id = 'engineering-design-and-delivery'
                    purpose = 'Separate implementation from review-only drafts and design interviews.'
                    selection_policy = 'Draft and grill workflows require explicit matching intent.'
                    members = @(
                        [ordered]@{ name = 'grill-with-docs'; role = 'workflow'; activation = 'focused design interview explicitly requested'; negative_activation = 'ordinary implementation, refactoring, or autonomous execution' },
                        [ordered]@{ name = 'draft-spec'; role = 'workflow'; activation = 'review-only PRD or specification draft'; negative_activation = 'implementation, refactoring, repository writes, or autonomous execution' }
                    )
                }
            )
            capabilities = @(
                [ordered]@{ kind = 'mcp'; name = 'openaiDeveloperDocs'; description = 'Search and fetch current official OpenAI developer documentation.'; activation = 'current OpenAI or Codex documentation is required'; negative_activation = ''; side_effect = 'read_only' },
                [ordered]@{ kind = 'mcp'; name = 'playwright'; description = 'Automate and inspect a browser for web testing.'; activation = 'browser automation or live web testing is required'; negative_activation = ''; side_effect = 'external_read' }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $policyPath -Encoding UTF8

        $configPath = Join-Path $TestDrive 'skills.json'
        [ordered]@{
            mcp_servers = @(
                [ordered]@{ name = 'openaiDeveloperDocs'; transport = 'http'; url = 'https://developers.openai.com/mcp' },
                [ordered]@{ name = 'playwright'; transport = 'stdio'; command = 'npx'; args = @('@playwright/mcp') }
            )
            mcp_profiles = [ordered]@{
                active = 'default'
                profiles = [ordered]@{ default = [ordered]@{ enabled = @('openaiDeveloperDocs') } }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
    }

    It 'Routes an explicit cold skill without changing profile state' {
        $before = (Get-FileHash -LiteralPath $manifestPath).Hash
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '请用 grill-with-docs 质询这个设计方案' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath | ConvertFrom-Json

        $result.abstained | Should Be $false
        $result.selected[0].name | Should Be 'grill-with-docs'
        $result.selection_mode | Should Be 'cold_load'
        $result.current_profile | Should Be 'default'
        $result.writes_performed | Should Be $false
        (Get-FileHash -LiteralPath $manifestPath).Hash | Should Be $before
    }

    It 'Rejects review-only and interview skills for an implementation request' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '更新 PRD 和 spec，然后彻底重构并自动自主连续实现' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath | ConvertFrom-Json

        @($result.selected.name) | Should Not Contain 'grill-with-docs'
        @($result.selected.name) | Should Not Contain 'draft-spec'
        @($result.excluded | Where-Object { $_.name -in @('grill-with-docs', 'draft-spec') -and $_.reason -eq 'negative_intent' }).Count | Should Be 2
    }

    It 'Selects an available MCP and emits an automatic read-only activation plan' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '查询 OpenAI 官方开发文档中关于 Codex skills 的说明' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath | ConvertFrom-Json

        $selected = @($result.selected | Where-Object { $_.kind -eq 'mcp' -and $_.name -eq 'openaiDeveloperDocs' })
        $selected.Count | Should Be 1
        $selected[0].availability | Should Be 'available'
        $plan = @($result.activation_plan | Where-Object { $_.kind -eq 'mcp' -and $_.name -eq 'openaiDeveloperDocs' })[0]
        $plan.action | Should Be 'use_available_mcp'
        $plan.auto_allowed | Should Be $true
    }

    It 'Discovers repository policy and MCP config without a generated manifest' {
        $repoRoot = Join-Path $TestDrive 'source-only-repo'
        $routerDir = Join-Path $repoRoot 'overrides\capability-router\scripts'
        $configDir = Join-Path $repoRoot 'config'
        New-Item -ItemType Directory -Path $routerDir, $configDir -Force | Out-Null
        $isolatedRouter = Join-Path $routerDir 'route-capability.ps1'
        Copy-Item -LiteralPath $scriptPath -Destination $isolatedRouter
        Copy-Item -LiteralPath $policyPath -Destination (Join-Path $configDir 'skill-routing-policy.json')
        Copy-Item -LiteralPath $configPath -Destination (Join-Path $repoRoot 'skills.json')

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $isolatedRouter -Query '查询 OpenAI 官方开发文档中关于 Codex skills 的说明' | ConvertFrom-Json

        $result.manifest_path | Should BeNullOrEmpty
        $result.policy_path | Should Be (Join-Path $configDir 'skill-routing-policy.json')
        $result.config_path | Should Be (Join-Path $repoRoot 'skills.json')
        $result.current_mcp_profile | Should Be 'default'
        @($result.activation_plan | Where-Object { $_.kind -eq 'mcp' -and $_.name -eq 'openaiDeveloperDocs' })[0].action | Should Be 'use_available_mcp'
    }

    It 'Plans but does not silently activate a disabled MCP' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '用 Playwright 自动化浏览器测试这个网页' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath | ConvertFrom-Json

        $selected = @($result.selected | Where-Object { $_.kind -eq 'mcp' -and $_.name -eq 'playwright' })
        $selected.Count | Should Be 1
        @($result.selected | Where-Object { $_.kind -eq 'skill' -and $_.name -eq 'playwright' }).Count | Should Be 0
        $selected[0].availability | Should Be 'needs_activation'
        $plan = @($result.activation_plan | Where-Object { $_.kind -eq 'mcp' -and $_.name -eq 'playwright' })[0]
        $plan.action | Should Be 'request_mcp_activation'
        $plan.auto_allowed | Should Be $false
        $result.writes_performed | Should Be $false
    }

    It 'Routes Chinese domain language and prefers the domain router' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '制作一个初中物理动画仿真' -ManifestPath $manifestPath | ConvertFrom-Json

        $result.abstained | Should Be $false
        @($result.selected.name) | Should Contain 'custom-junior-physics-animation'
    }

    It 'Routes a cold dotnet debugging skill' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '诊断 WPF .NET 启动失败' -ManifestPath $manifestPath | ConvertFrom-Json

        $result.abstained | Should Be $false
        $result.selected[0].name | Should Be 'debug:dotnet'
        $result.selection_mode | Should Be 'cold_load'
    }

    It 'Abstains when metadata has no meaningful match' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '你好，请继续' -ManifestPath $manifestPath | ConvertFrom-Json

        $result.abstained | Should Be $true
        @($result.selected).Count | Should Be 0
    }

    It 'Rejects manifest paths outside their declared source root' {
        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        $escaped = Set-RouterTestSkill $outside 'escaped' 'escaped-skill' 'Escaped unique capability.'
        $malicious = Join-Path $TestDrive 'malicious.json'
        [ordered]@{ schema_version = 2; active_profile = 'default'; active = @(); canonical = @([ordered]@{ name = $escaped.name; path = $escaped.path; source_root = $skillRoot }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $malicious -Encoding UTF8

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query 'escaped unique capability' -ManifestPath $malicious | ConvertFrom-Json

        $result.abstained | Should Be $true
        $result.candidate_count | Should Be 0
    }

    It 'Understands capability architecture assessment without selecting unrelated builders' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '评估当前统一 capability selector、skills、MCP、plugin、app、connector、native tools 自动无感切换架构是否存在更优工程终态' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath | ConvertFrom-Json

        $result.schema_version | Should Be 3
        $result.task_model.task_type | Should Be 'architecture_assessment'
        $result.task_model.domain | Should Be 'capability_orchestration'
        $result.task_model.goal | Should Be 'evaluate_global_optimum'
        @($result.task_model.operations) | Should Contain 'inspect'
        @($result.task_model.operations) | Should Contain 'compare'
        @($result.selected.name) | Should Not Contain 'custom-windows-wpf-teacher-app'
        @($result.selected.name) | Should Not Contain 'mcp-builder'
        @($result.selected.name) | Should Not Contain 'mcp-cli'
        $result.writes_performed | Should Be $false
    }

    It 'Builds a minimal capability DAG for implementation work' {
        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '调研现有实现，修复路由缺陷并运行测试验证' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath | ConvertFrom-Json

        @($result.capability_graph.stages.id) | Should Contain 'inspect'
        @($result.capability_graph.stages.id) | Should Contain 'implement'
        @($result.capability_graph.stages.id) | Should Contain 'verify'
        @($result.capability_graph.edges | Where-Object { $_.from -eq 'inspect' -and $_.to -eq 'implement' }).Count | Should Be 1
        @($result.capability_graph.edges | Where-Object { $_.from -eq 'implement' -and $_.to -eq 'verify' }).Count | Should Be 1
    }

    It 'Reuses matching session capabilities and emits recommendation-only preheat' {
        $sessionPath = Join-Path $TestDrive 'session.json'
        [ordered]@{
            schema_version = 1
            task_domain = 'software_engineering'
            loaded = @([ordered]@{ kind = 'skill'; name = 'debug:dotnet' })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sessionPath -Encoding UTF8

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '继续诊断 WPF .NET 启动失败' -ManifestPath $manifestPath -SessionSnapshotPath $sessionPath | ConvertFrom-Json

        @($result.session_plan.reuse.name) | Should Contain 'debug:dotnet'
        $result.preheat_recommendation.apply | Should Be $false
        $result.preheat_recommendation.profile | Should Be 'dotnet'
    }

    It 'Fails closed on a stale host snapshot' {
        $snapshotPath = Join-Path $TestDrive 'stale-snapshot.json'
        [ordered]@{
            schema_version = 2
            captured_at = '2020-01-01T00:00:00Z'
            source = 'codex-app-server'
            capabilities = @([ordered]@{ kind = 'app'; name = 'gmail'; description = 'Read Gmail'; availability = 'available'; side_effect = 'external_read' })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8

        $result = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '用 gmail 总结未读邮件' -ManifestPath $manifestPath -HostSnapshotPath $snapshotPath -MaxSnapshotAgeMinutes 30 | ConvertFrom-Json

        $result.host_snapshot.status | Should Be 'stale'
        @($result.selected.name) | Should Not Contain 'gmail'
        @($result.excluded | Where-Object { $_.name -eq 'gmail' -and $_.reason -eq 'stale_snapshot' }).Count | Should Be 1
    }

    It 'Merges current host skill and MCP truth over static discovery fields' {
        $snapshotPath = Join-Path $TestDrive 'host-skill-mcp.json'
        [ordered]@{
            schema_version = 3
            captured_at = [DateTimeOffset]::UtcNow.ToString('o')
            source = 'codex-app-server'
            capabilities = @(
                [ordered]@{ kind = 'skill'; name = 'debug:dotnet'; display_name = 'debug:dotnet'; availability = 'available'; callable = $true; authenticated = $true; side_effect = 'read_only'; evidence = @{ source = 'skills/list' } },
                [ordered]@{ kind = 'mcp'; name = 'openaiDeveloperDocs'; display_name = 'OpenAI Developer Docs'; availability = 'needs_auth'; callable = $false; authenticated = $false; side_effect = 'read_only'; evidence = @{ source = 'mcpServerStatus/list' } }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8

        $skillResult = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '诊断 WPF .NET 启动失败' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath -HostSnapshotPath $snapshotPath | ConvertFrom-Json
        $mcpResult = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '查询 OpenAI 官方开发文档' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath -HostSnapshotPath $snapshotPath | ConvertFrom-Json

        @($skillResult.selected | Where-Object name -eq 'debug:dotnet')[0].availability | Should Be 'available'
        $mcp = @($mcpResult.selected | Where-Object name -eq 'openaiDeveloperDocs')[0]
        $mcp.availability | Should Be 'needs_auth'
        $mcp.callable | Should Be $false
        $mcp.authenticated | Should Be $false
        @($mcpResult.activation_plan | Where-Object name -eq 'openaiDeveloperDocs')[0].auto_allowed | Should Be $false
    }

    It 'Finds opaque apps by runtime display names and aliases' {
        $snapshotPath = Join-Path $TestDrive 'opaque-apps.json'
        [ordered]@{
            schema_version = 3
            captured_at = [DateTimeOffset]::UtcNow.ToString('o')
            source = 'codex-app-server'
            capabilities = @(
                [ordered]@{
                    kind = 'app'; name = 'connector_01JOPAQUE'; runtime_name = 'gmail'; display_name = 'Gmail'; aliases = @('Google Mail')
                    description = 'Connected mailbox.'; availability = 'available'; callable = $true; authenticated = $true; side_effect = 'unknown'
                    tools = @([ordered]@{ name = 'search_messages'; title = 'Search Gmail'; description = 'Read and summarize email messages.'; side_effect = 'external_read'; authenticated = $true; approval = 'none' })
                },
                [ordered]@{
                    kind = 'app'; name = 'connector_02JOPAQUE'; runtime_name = 'github'; display_name = 'GitHub'; aliases = @('Git Hub')
                    description = 'Connected source control.'; availability = 'available'; callable = $true; authenticated = $true; side_effect = 'unknown'
                    tools = @([ordered]@{ name = 'search_repositories'; title = 'Search GitHub'; description = 'Read repository metadata.'; side_effect = 'external_read'; authenticated = $true; approval = 'none' })
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8

        $gmail = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '用 Gmail 总结未读邮件' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath -HostSnapshotPath $snapshotPath | ConvertFrom-Json
        $github = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '用 GitHub 查询仓库元数据' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath -HostSnapshotPath $snapshotPath | ConvertFrom-Json

        @($gmail.selected | Where-Object display_name -eq 'Gmail').Count | Should Be 1
        @($gmail.activation_plan | Where-Object display_name -eq 'Gmail')[0].auto_allowed | Should Be $true
        @($github.selected | Where-Object display_name -eq 'GitHub').Count | Should Be 1
        @($github.activation_plan | Where-Object display_name -eq 'GitHub')[0].auto_allowed | Should Be $true
    }

    It 'Uses matched tool policy and fails closed for write or unknown side effects' {
        $snapshotPath = Join-Path $TestDrive 'tool-policy.json'
        [ordered]@{
            schema_version = 3
            captured_at = [DateTimeOffset]::UtcNow.ToString('o')
            source = 'codex-app-server'
            capabilities = @([ordered]@{
                kind = 'app'; name = 'connector_mail'; runtime_name = 'gmail'; display_name = 'Gmail'; aliases = @()
                description = 'Connected mailbox.'; availability = 'available'; callable = $true; authenticated = $true; side_effect = 'unknown'
                tools = @(
                    [ordered]@{ name = 'search_messages'; title = 'Search Gmail'; description = 'Read and summarize messages.'; side_effect = 'external_read'; authenticated = $true; approval = 'none' },
                    [ordered]@{ name = 'send_message'; title = 'Send Gmail'; description = 'Send an email message.'; side_effect = 'controlled_write'; authenticated = $true; approval = 'required' },
                    [ordered]@{ name = 'mystery'; title = 'Mystery action'; description = 'Do an unspecified action.'; side_effect = 'unknown'; authenticated = $true; approval = 'unknown' }
                )
            })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8

        $read = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '用 Gmail 搜索并总结邮件' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath -HostSnapshotPath $snapshotPath | ConvertFrom-Json
        $write = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '用 Gmail 发送邮件' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath -HostSnapshotPath $snapshotPath | ConvertFrom-Json
        $mixed = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '用 Gmail 搜索邮件，然后发送摘要' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath -HostSnapshotPath $snapshotPath | ConvertFrom-Json
        $unknown = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Query '用 Gmail 执行 mystery action' -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath -HostSnapshotPath $snapshotPath | ConvertFrom-Json

        @($read.activation_plan | Where-Object display_name -eq 'Gmail')[0].auto_allowed | Should Be $true
        @($read.activation_plan | Where-Object display_name -eq 'Gmail')[0].selected_tools | Should Contain 'search_messages'
        @(@($read.activation_plan | Where-Object display_name -eq 'Gmail')[0].selected_tools).Count | Should Be 1
        @($write.activation_plan | Where-Object display_name -eq 'Gmail')[0].policy_decision | Should Be 'approval_required'
        @($write.activation_plan | Where-Object display_name -eq 'Gmail')[0].auto_allowed | Should Be $false
        @($mixed.activation_plan | Where-Object display_name -eq 'Gmail')[0].auto_allowed | Should Be $false
        @($mixed.activation_plan | Where-Object display_name -eq 'Gmail')[0].selected_tools | Should Contain 'search_messages'
        @($mixed.activation_plan | Where-Object display_name -eq 'Gmail')[0].selected_tools | Should Contain 'send_message'
        @($unknown.activation_plan | Where-Object display_name -eq 'Gmail')[0].auto_allowed | Should Be $false
    }
}
