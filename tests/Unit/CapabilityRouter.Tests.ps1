function Set-RouterTestSkill([string]$Root, [string]$Folder, [string]$Name, [string]$Description) {
    $dir = Join-Path $Root $Folder
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'SKILL.md'
    Set-Content -LiteralPath $path -Encoding UTF8 -Value "---`nname: $Name`ndescription: $Description`n---`n`n# $Name"
    return [pscustomobject]@{ name = $Name; description = $Description; path = $path; source_root = $Root; is_system = $false }
}

Describe 'Native-first capability discovery and policy' {
    BeforeEach {
        $scriptPath = Join-Path $PSScriptRoot '..\..\overrides\capability-router\scripts\route-capability.ps1'
        $skillRoot = Join-Path $TestDrive 'skills'
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        $debug = Set-RouterTestSkill $skillRoot 'debug-dotnet' 'debug:dotnet' 'Debug .NET, ASP.NET Core, and WPF runtime failures.'
        $systematic = Set-RouterTestSkill $skillRoot 'systematic' 'systematic-debugging' 'Use for bugs, test failures, and unexpected behavior before proposing fixes.'
        $architecture = Set-RouterTestSkill $skillRoot 'architecture' 'codebase-design' 'Design deep module boundaries and stable interfaces.'
        $physics = Set-RouterTestSkill $skillRoot 'physics' 'custom-junior-physics-animation' 'Build junior middle school physics animations and simulations.'
        $grill = Set-RouterTestSkill $skillRoot 'grill' 'grill-with-docs' 'Grill a design through an interview about assumptions and tradeoffs.'
        $tdd = Set-RouterTestSkill $skillRoot 'tdd' 'test-driven-development' 'Use test-first implementation for behavior changes.'
        $publisher = Set-RouterTestSkill $skillRoot 'publisher' 'to-spec' 'Publish an approved specification to a tracker.'

        $manifestPath = Join-Path $TestDrive 'manifest.json'
        [ordered]@{
            schema_version = 2
            active_profile = 'default'
            resident_names = @('capability-router')
            active = @($systematic)
            canonical = @($debug, $systematic, $architecture, $physics, $grill, $tdd, $publisher)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $policyPath = Join-Path $TestDrive 'routing-policy.json'
        [ordered]@{
            schema_version = 2
            mode = 'observe'
            groups = @(
                [ordered]@{
                    id = 'engineering-design-and-delivery'
                    purpose = 'Expose engineering workflows for host semantic adjudication.'
                    selection_policy = 'The host model selects; deterministic policy only validates the selected capability.'
                    members = @(
                        [ordered]@{ name = 'grill-with-docs'; role = 'workflow'; activation = 'focused design interview explicitly requested'; negative_activation = 'ordinary implementation' },
                        [ordered]@{ name = 'codebase-design'; role = 'reference'; activation = 'module boundary or architecture design'; negative_activation = '' },
                        [ordered]@{ name = 'to-spec'; role = 'operator'; activation = 'publish an approved specification'; negative_activation = 'drafting or review only' }
                    )
                }
            )
            capabilities = @(
                [ordered]@{ kind = 'mcp'; name = 'openaiDeveloperDocs'; description = 'Search and fetch current official OpenAI developer documentation.'; activation = 'current OpenAI or Codex documentation is required'; negative_activation = ''; side_effect = 'external_read' },
                [ordered]@{ kind = 'mcp'; name = 'playwright'; description = 'Automate and inspect a browser for web testing.'; activation = 'browser automation or live web testing is required'; negative_activation = ''; side_effect = 'external_read' }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $policyPath -Encoding UTF8

        $configPath = Join-Path $TestDrive 'skills.json'
        [ordered]@{
            skill_projection = [ordered]@{
                active_profile = 'default'
                profiles = [ordered]@{
                    default = [ordered]@{ purpose = 'General debugging and completion verification.'; enabled_names = @('systematic-debugging') }
                    engineering = [ordered]@{ purpose = 'Architecture, product specification, and delivery planning.'; enabled_names = @('codebase-design', 'grill-with-docs', 'to-spec') }
                    dotnet = [ordered]@{ purpose = '.NET implementation and diagnosis.'; enabled_names = @('debug:dotnet', 'systematic-debugging') }
                    python = [ordered]@{ purpose = 'Python implementation and diagnosis.'; enabled_names = @('systematic-debugging') }
                    physics = [ordered]@{ purpose = 'Interactive physics teaching experiences.'; enabled_names = @('custom-junior-physics-animation') }
                    strict = [ordered]@{ purpose = 'Strict engineering workflows.'; enabled_names = @('test-driven-development', 'systematic-debugging') }
                }
            }
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

    function Invoke-TestRouter([string]$Query, [hashtable]$Extra = @{}) {
        $args = @{ Query = $Query; ManifestPath = $manifestPath; PolicyPath = $policyPath; ConfigPath = $configPath }
        foreach ($key in $Extra.Keys) { $args[$key] = $Extra[$key] }
        return & $scriptPath @args | ConvertFrom-Json
    }

    It 'Makes the host AI the only semantic decision owner' {
        $result = Invoke-TestRouter '分析当前仓库架构是否模块化，但不要修改文件' @{ ProfileHint = @('engineering') }

        $result.schema_version | Should Be 3
        $result.decision_owner | Should Be 'host_ai'
        $result.semantic_routing_performed | Should Be $false
        $result.task_model.task_type | Should Be 'host_adjudicated'
        $result.task_model.confidence | Should Be $null
        $result.retrieval.strategy | Should Be 'hierarchical_domain_discovery'
        @($result.discovery_domains | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.purpose) }).Count | Should Be 0
        @($result.selected).Count | Should Be 0
        $result.requires_host_adjudication | Should Be $true
        @($result.retrieval.candidates.name) | Should Contain 'codebase-design'
    }

    It 'Returns the same profile candidate pool for equivalent Chinese and English requests' {
        $zh = Invoke-TestRouter '设计清晰的模块边界和稳定接口' @{ ProfileHint = @('engineering') }
        $en = Invoke-TestRouter 'Design clear module boundaries and stable interfaces' @{ ProfileHint = @('engineering') }

        @($zh.retrieval.candidates.name | Sort-Object) | Should Be @($en.retrieval.candidates.name | Sort-Object)
        @($zh.selected).Count | Should Be 0
        @($en.selected).Count | Should Be 0
    }

    It 'Reuses in-process metadata reads and invalidates changed skill files' {
        $cache = @{}
        $first = Invoke-TestRouter '诊断 WPF 启动失败' @{ Candidate = @('skill|debug:dotnet'); MetadataCache = $cache }
        $first.selected[0].description | Should Be 'Debug .NET, ASP.NET Core, and WPF runtime failures.'
        $cache.Count | Should BeGreaterThan 0

        Set-Content -LiteralPath $debug.path -Encoding UTF8 -Value "---`nname: debug:dotnet`ndescription: Changed debug metadata with a different length.`n---`n`n# debug:dotnet"
        $second = Invoke-TestRouter '再次诊断 WPF 启动失败' @{ Candidate = @('skill|debug:dotnet'); MetadataCache = $cache }

        $second.selected[0].description | Should Be 'Changed debug metadata with a different length.'
        $cache.Count | Should BeGreaterThan 1
    }

    It 'Normalizes comma-separated profile hints from an external PowerShell process' {
        $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
            -Query '设计软件工程终态和交互界面' `
            -ManifestPath $manifestPath -PolicyPath $policyPath -ConfigPath $configPath `
            -ProfileHint 'engineering,physics'

        $LASTEXITCODE | Should Be 0
        $result = ($raw -join "`n") | ConvertFrom-Json
        @($result.retrieval.profile_hints) | Should Be @('engineering', 'physics')
        @($result.retrieval.candidates.name) | Should Contain 'codebase-design'
        @($result.retrieval.candidates.name) | Should Contain 'custom-junior-physics-animation'
        @($result.excluded | Where-Object { $_.kind -eq 'profile' -and $_.reason -eq 'unknown_profile' }).Count | Should Be 0
    }

    It 'Uses host-selected discovery domains without requiring an active profile switch' {
        $result = Invoke-TestRouter '设计物理教学软件的模块接口' @{ DomainHint = @('engineering,physics') }

        @($result.retrieval.domain_hints) | Should Be @('engineering', 'physics')
        @($result.retrieval.candidates.name) | Should Contain 'codebase-design'
        @($result.retrieval.candidates.name) | Should Contain 'custom-junior-physics-animation'
        @($result.retrieval.candidates | Where-Object name -eq 'codebase-design')[0].domains | Should Contain 'engineering'
        $result.current_profile | Should Be 'default'
        $result.writes_performed | Should Be $false
    }

    It 'Applies deterministic policy only after the host supplies a capability' {
        $result = Invoke-TestRouter '设计清晰的模块边界和稳定接口' @{ ProfileHint = @('engineering'); Candidate = @('skill|codebase-design') }

        @($result.selected.name) | Should Be @('codebase-design')
        $result.selection_mode | Should Be 'host_selected'
        $result.activation_plan[0].action | Should Be 'load_skill'
        $result.activation_plan[0].auto_allowed | Should Be $true
    }

    It 'Preserves official explicit invocation without lexical semantic ranking' {
        $result = Invoke-TestRouter '请用 $grill-with-docs 质询这个设计方案'

        @($result.selected.name) | Should Be @('grill-with-docs')
        $result.selection_mode | Should Be 'explicit'
        $result.activation_plan[0].action | Should Be 'load_skill'
    }

    It 'Does not treat an unsigiled capability name inside a negation as an explicit selection' {
        $result = Invoke-TestRouter '这个 Python CLI 崩溃了，请定位根因；不要使用 debug:dotnet' @{ ProfileHint = @('python') }

        @($result.selected).Count | Should Be 0
        @($result.retrieval.candidates.name) | Should Not Contain 'debug:dotnet'
        $result.requires_host_adjudication | Should Be $true
    }

    It 'Does not infer dotnet from a generic debugging request' {
        $result = Invoke-TestRouter '这个项目启动不了，请查明根因并修好' @{ ProfileHint = @('default') }

        @($result.retrieval.candidates.name) | Should Contain 'systematic-debugging'
        @($result.retrieval.candidates.name) | Should Not Contain 'debug:dotnet'
        @($result.selected).Count | Should Be 0
    }

    It 'Filters host-declared negative constraints before policy selection' {
        $result = Invoke-TestRouter '不要用 test-driven-development，只解释失败原因' @{
            ProfileHint = @('strict')
            Candidate = @('skill|test-driven-development', 'skill|systematic-debugging')
            ExcludeCapability = @('skill|test-driven-development')
        }

        @($result.selected.name) | Should Be @('systematic-debugging')
        @($result.retrieval.candidates.name) | Should Not Contain 'test-driven-development'
        @($result.excluded | Where-Object { $_.name -eq 'test-driven-development' -and $_.reason -eq 'host_excluded' }).Count | Should BeGreaterThan 0
    }

    It 'Keeps operator skills behind approval' {
        $result = Invoke-TestRouter '把批准的 spec 发布到 tracker' @{ ProfileHint = @('engineering'); Candidate = @('skill|to-spec') }

        $result.activation_plan[0].action | Should Be 'load_skill'
        $result.activation_plan[0].load_allowed | Should Be $true
        $result.activation_plan[0].load_side_effect | Should Be 'read_only'
        $result.activation_plan[0].workflow_side_effect | Should Be 'controlled_write'
        $result.activation_plan[0].execution_policy | Should Be 'approval_required'
    }

    It 'Keeps MCP availability and activation deterministic' {
        $available = Invoke-TestRouter '查 OpenAI 官方文档' @{ Candidate = @('mcp|openaiDeveloperDocs') }
        $disabled = Invoke-TestRouter '用 Playwright 检查网页' @{ Candidate = @('mcp|playwright') }

        $available.activation_plan[0].action | Should Be 'use_available_mcp'
        $available.activation_plan[0].auto_allowed | Should Be $true
        $disabled.activation_plan[0].action | Should Be 'request_mcp_activation'
        $disabled.activation_plan[0].auto_allowed | Should Be $false
    }

    It 'Rejects manifest paths outside their declared source root' {
        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        $escaped = Set-RouterTestSkill $outside 'escaped' 'escaped-skill' 'Escaped unique capability.'
        $malicious = Join-Path $TestDrive 'malicious.json'
        [ordered]@{ schema_version = 2; active_profile = 'default'; active = @(); canonical = @([ordered]@{ name = $escaped.name; path = $escaped.path; source_root = $skillRoot }) } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $malicious -Encoding UTF8

        $result = & $scriptPath -Query 'escaped unique capability' -ManifestPath $malicious -Candidate @('skill|escaped-skill') | ConvertFrom-Json

        @($result.selected).Count | Should Be 0
        $result.capability_count | Should Be 0
    }

    It 'Fails closed on a stale host snapshot' {
        $snapshotPath = Join-Path $TestDrive 'stale-snapshot.json'
        [ordered]@{
            schema_version = 2
            captured_at = '2020-01-01T00:00:00Z'
            source = 'codex-app-server'
            capabilities = @([ordered]@{ kind = 'app'; name = 'gmail'; description = 'Read Gmail'; availability = 'available'; side_effect = 'external_read' })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8

        $result = Invoke-TestRouter '用 gmail 总结未读邮件' @{ HostSnapshotPath = $snapshotPath; MaxSnapshotAgeMinutes = 30; Candidate = @('app|gmail') }

        $result.host_snapshot.status | Should Be 'stale'
        @($result.selected.name) | Should Not Contain 'gmail'
        @($result.excluded | Where-Object { $_.name -eq 'gmail' -and $_.reason -eq 'stale_snapshot' }).Count | Should Be 1
    }

    It 'Fails closed when every explicitly requested discovery domain is unknown' {
        $result = Invoke-TestRouter '设计模块接口' @{ DomainHint = @('missing-domain') }

        @($result.retrieval.domain_hints).Count | Should Be 0
        @($result.retrieval.candidates).Count | Should Be 0
        @($result.excluded | Where-Object { $_.name -eq 'missing-domain' -and $_.reason -eq 'unknown_domain' }).Count | Should Be 1
        $result.selection_mode | Should Be 'abstain'
        $result.abstained | Should Be $true
    }

    It 'Still validates an explicit skill when an unrelated discovery domain is unknown' {
        $result = Invoke-TestRouter '请使用 $codebase-design 设计模块接口' @{ DomainHint = @('missing-domain') }

        @($result.selected.name) | Should Be @('codebase-design')
        $result.selection_mode | Should Be 'explicit'
        $result.activation_plan[0].action | Should Be 'load_skill'
        @($result.excluded | Where-Object { $_.name -eq 'missing-domain' -and $_.reason -eq 'unknown_domain' }).Count | Should Be 1
    }

    It 'Reports deterministic candidate truncation so the host can refine the domain' {
        $result = Invoke-TestRouter '设计模块接口' @{ DomainHint = @('engineering'); MaxCandidates = 2 }

        $result.retrieval.candidate_count | Should Be 2
        $result.retrieval.available_candidate_count | Should BeGreaterThan 2
        $result.retrieval.truncated | Should Be $true
    }

    It 'Uses a current host snapshot to override static skill and MCP availability' {
        $snapshotPath = Join-Path $TestDrive 'current-snapshot.json'
        [ordered]@{
            schema_version = 2
            captured_at = [DateTimeOffset]::UtcNow.ToString('o')
            source = 'codex-app-server'
            capabilities = @(
                [ordered]@{ kind = 'skill'; name = 'debug:dotnet'; description = 'Host-visible .NET debugger.'; availability = 'disabled'; side_effect = 'read_only' },
                [ordered]@{ kind = 'skill'; name = 'plugin-only-skill'; description = 'Host plugin skill.'; availability = 'available'; side_effect = 'read_only' },
                [ordered]@{ kind = 'mcp'; name = 'openaiDeveloperDocs'; description = 'Host MCP status.'; availability = 'needs_auth'; side_effect = 'external_read' }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $snapshotPath -Encoding UTF8

        $result = Invoke-TestRouter '诊断 .NET 并核对官方文档' @{
            DomainHint = @('dotnet')
            HostSnapshotPath = $snapshotPath
            Candidate = @('skill|debug:dotnet', 'skill|plugin-only-skill', 'mcp|openaiDeveloperDocs')
        }

        $debugCandidate = @($result.retrieval.candidates | Where-Object { $_.kind -eq 'skill' -and $_.name -eq 'debug:dotnet' })[0]
        $debugCandidate.description | Should Be 'Host-visible .NET debugger.'
        $debugCandidate.availability | Should Be 'disabled'
        @($result.activation_plan | Where-Object name -eq 'debug:dotnet')[0].action | Should Be 'request_activation'
        @($result.activation_plan | Where-Object name -eq 'plugin-only-skill')[0].action | Should Be 'use_active_skill'
        @($result.activation_plan | Where-Object name -eq 'openaiDeveloperDocs')[0].action | Should Be 'request_mcp_activation'
    }

    It 'Reuses an already loaded host-selected capability without inventing a task domain' {
        $sessionPath = Join-Path $TestDrive 'session.json'
        [ordered]@{ schema_version = 1; task_domain = 'legacy-value'; loaded = @([ordered]@{ kind = 'skill'; name = 'debug:dotnet' }) } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sessionPath -Encoding UTF8

        $result = Invoke-TestRouter '继续诊断 WPF .NET 启动失败' @{ ProfileHint = @('dotnet'); Candidate = @('skill|debug:dotnet'); SessionSnapshotPath = $sessionPath }

        @($result.session_plan.reuse.name) | Should Contain 'debug:dotnet'
        $result.preheat_recommendation.profile | Should Be 'dotnet'
        $result.preheat_recommendation.apply | Should Be $false
        $result.writes_performed | Should Be $false
    }
}
