# 五宿主事实的唯一登记点（单一真源）。收编此前散布在
# RuleDiscovery、GlobalRuleProjection、SkillProjection 等处的平行枚举：
# 宿主清单与顺序、全局规则文件名、用户根目录名、显示名。宿主能力、加载
# 语义与各适配器差异留在用点建模，不在注册表内预抽象。
# 新增/退役宿主：在此增删一条 fact，并按 CONTRIBUTING 的宿主触点地图同步
# rules/ 源、skills.json targets 与各宿主适配器。

function Get-AgentHostFacts {
    return @(
        [pscustomobject]@{ id = 'codex'; display = 'Codex'; label = 'OpenAI ChatGPT Work / Codex App / Codex CLI'; file = 'AGENTS.md'; discovery_files = @('AGENTS.override.md', 'AGENTS.md'); root_dir = '.codex'; contract_version = '2026-10'; verified_on = '2026-10-25'; verification_level = 'repo_verified' }
        [pscustomobject]@{ id = 'claude'; display = 'Claude'; label = 'Claude Code'; file = 'CLAUDE.md'; discovery_files = @('CLAUDE.md'); root_dir = '.claude'; contract_version = '2026-10'; verified_on = '2026-10-25'; verification_level = 'repo_verified' }
        [pscustomobject]@{ id = 'zcode'; display = 'ZCode'; label = 'ZCode / GLM'; file = 'AGENTS.md'; discovery_files = @('AGENTS.md'); root_dir = '.zcode'; contract_version = '2026-10'; verified_on = '2026-10-25'; verification_level = 'repo_verified' }
        [pscustomobject]@{ id = 'antigravity'; display = 'Antigravity'; label = 'Antigravity / Gemini'; file = 'GEMINI.md'; discovery_files = @('GEMINI.md'); root_dir = '.gemini'; contract_version = '2026-10'; verified_on = '2026-10-25'; verification_level = 'repo_verified' }
        [pscustomobject]@{ id = 'workbuddy'; display = 'WorkBuddy'; label = 'WorkBuddy / CodeBuddy'; file = 'CODEBUDDY.md'; discovery_files = @('CODEBUDDY.md', 'CODEBUDDY.mdc'); root_dir = '.workbuddy-ai'; contract_version = '2026-10'; verified_on = '2026-10-25'; verification_level = 'repo_verified' }
    )
}

function Get-AgentHostCompatibilityStatus {
    [CmdletBinding()]
    param(
        [datetime]$AsOf = (Get-Date),
        [int]$MaxAgeDays = 30
    )

    if ($MaxAgeDays -lt 0) { throw 'MaxAgeDays must be non-negative.' }
    foreach ($fact in @(Get-AgentHostFacts)) {
        $verifiedOn = $null
        $parseOk = $false
        try {
            $verifiedOn = [datetime]::ParseExact(
                [string]$fact.verified_on,
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal
            )
            $parseOk = $true
        }
        catch { $parseOk = $false }
        $ageDays = $null
        $status = 'missing'
        if ($parseOk) {
            $ageDays = [math]::Floor(($AsOf.ToUniversalTime() - $verifiedOn.ToUniversalTime()).TotalDays)
            $status = if ($ageDays -lt 0) { 'future' } elseif ($ageDays -le $MaxAgeDays) { 'current' } else { 'stale' }
        }
        [pscustomobject][ordered]@{
            host = [string]$fact.id
            display = [string]$fact.display
            contract_version = [string]$fact.contract_version
            verified_on = [string]$fact.verified_on
            verification_level = [string]$fact.verification_level
            age_days = $ageDays
            status = $status
            host_loaded = $false
            live_accepted = $false
        }
    }
}

function Get-AgentHostIds {
    return @((Get-AgentHostFacts) | ForEach-Object { [string]$_.id })
}

function Get-AgentHostFact([string]$HostName) {
    $fact = @(Get-AgentHostFacts) | Where-Object { $_.id -eq $HostName }
    if (@($fact).Count -eq 0) { throw ("unknown_agent_host: {0}" -f $HostName) }
    return $fact[0]
}
