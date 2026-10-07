# 五宿主事实的唯一登记点（单一真源）。收编此前散布在 RuleEstate、
# RuleDiscovery、GlobalRuleProjection、SkillProjection 等处的平行枚举：
# 宿主清单与顺序、全局规则文件名、用户根目录名、显示名。宿主能力、加载
# 语义与各适配器差异留在用点建模，不在注册表内预抽象。
# 新增/退役宿主：在此增删一条 fact，并按 CONTRIBUTING 的宿主触点地图同步
# rules/ 源、skills.json targets 与各宿主适配器。

function Get-AgentHostFacts {
    return @(
        [pscustomobject]@{ id = 'codex'; display = 'Codex'; label = 'OpenAI ChatGPT Work / Codex App / Codex CLI'; file = 'AGENTS.md'; discovery_files = @('AGENTS.override.md', 'AGENTS.md'); root_dir = '.codex' }
        [pscustomobject]@{ id = 'claude'; display = 'Claude'; label = 'Claude Code'; file = 'CLAUDE.md'; discovery_files = @('CLAUDE.md'); root_dir = '.claude' }
        [pscustomobject]@{ id = 'zcode'; display = 'ZCode'; label = 'ZCode / GLM'; file = 'AGENTS.md'; discovery_files = @('AGENTS.md'); root_dir = '.zcode' }
        [pscustomobject]@{ id = 'antigravity'; display = 'Antigravity'; label = 'Antigravity / Gemini'; file = 'GEMINI.md'; discovery_files = @('GEMINI.md'); root_dir = '.gemini' }
        [pscustomobject]@{ id = 'workbuddy'; display = 'WorkBuddy'; label = 'WorkBuddy / CodeBuddy'; file = 'CODEBUDDY.md'; discovery_files = @('CODEBUDDY.md', 'CODEBUDDY.mdc'); root_dir = '.workbuddy-ai' }
    )
}

function Get-AgentHostIds {
    return @((Get-AgentHostFacts) | ForEach-Object { [string]$_.id })
}

function Get-AgentHostFact([string]$HostName) {
    $fact = @(Get-AgentHostFacts) | Where-Object { $_.id -eq $HostName }
    if (@($fact).Count -eq 0) { throw ("unknown_agent_host: {0}" -f $HostName) }
    return $fact[0]
}
