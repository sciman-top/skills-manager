# AI risk-control command surface.  This command is deliberately read-only:
# it inventories repository policy assets and creates triage plans. It does not
# run host scripts or change proxy, account, client, or credential state.

function Parse-AiRiskControlArgs {
    param([string[]]$Tokens = @())
    $result = [ordered]@{
        platform = 'all'; json = $false
        out_path = ''; event = ''; plan = $false; help = $false
        retry_after = ''; reset_at = ''
    }
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = [string]$Tokens[$i]
        switch -Regex ($token) {
            '^(--help|-h)$' { $result.help = $true; continue }
            '^--json$' { $result.json = $true; continue }
            '^--plan$' { $result.plan = $true; continue }
            '^--platform$' { if ($i + 1 -ge $Tokens.Count) { throw '--platform requires all|antigravity|workbuddy' }; $result.platform = [string]$Tokens[++$i]; continue }
            '^--event$' { if ($i + 1 -ge $Tokens.Count) { throw '--event requires a supported incident type' }; $result.event = [string]$Tokens[++$i]; continue }
            '^--retry-after$' { if ($i + 1 -ge $Tokens.Count) { throw '--retry-after requires seconds or an HTTP date' }; $result.retry_after = [string]$Tokens[++$i]; continue }
            '^--reset-at$' { if ($i + 1 -ge $Tokens.Count) { throw '--reset-at requires an ISO 8601 timestamp with timezone' }; $result.reset_at = [string]$Tokens[++$i]; continue }
            '^--out$' { if ($i + 1 -ge $Tokens.Count) { throw '--out requires a path' }; $result.out_path = [string]$Tokens[++$i]; continue }
            default { throw ('Unknown ai-risk-control option: {0}' -f $token) }
        }
    }
    if ($result.platform -notin @('all', 'antigravity', 'workbuddy')) { throw 'platform must be all, antigravity, or workbuddy' }
    $events = @('antigravity-ban', 'antigravity-rate-limit', 'antigravity-degradation', 'workbuddy-account-risk', 'workbuddy-rate-limit', 'workbuddy-degradation')
    if (-not [string]::IsNullOrWhiteSpace([string]$result.event) -and $result.event -notin $events) { throw ('event must be one of: {0}' -f ($events -join ', ')) }
    if ($result.event -like 'antigravity-*' -and $result.platform -eq 'workbuddy') { throw 'the selected event conflicts with --platform workbuddy' }
    if ($result.event -like 'workbuddy-*' -and $result.platform -eq 'antigravity') { throw 'the selected event conflicts with --platform antigravity' }
    if (($result.retry_after -or $result.reset_at) -and $result.event -notlike '*-rate-limit') { throw 'cooldown inputs require a rate-limit event' }
    return [pscustomobject]$result
}

function Get-AiRiskControlPolicy {
    [pscustomobject][ordered]@{
        version = 1
        purpose = '降低条款违规、超额用量和错误归因风险；不绕过服务方限制'
        enforcement = 'advisory_only; this command does not intercept host requests or enforce client concurrency'
        official_sources = @(
            [pscustomobject]@{ url='https://antigravity.google/terms'; verified_on='2026-10-13'; scope='Antigravity third-party access restriction' }
            [pscustomobject]@{ url='https://antigravity.google/docs/faq/'; verified_on='2026-10-13'; scope='Antigravity eligibility, direct headless CLI, third-party agents, and account rotation' }
            [pscustomobject]@{ url='https://antigravity.google/docs/plans/'; verified_on='2026-10-13'; scope='Antigravity plan quotas, work-based usage, and credits' }
            [pscustomobject]@{ url='https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Error-Code'; verified_on='2026-10-14'; scope='Public WorkBuddy error-code descriptions; not account-risk thresholds' }
            [pscustomobject]@{ url='https://www.workbuddy.ai/document/term'; verified_on='2026-10-14'; scope='International service protection and reasonable use' }
            [pscustomobject]@{ url='https://ai.google.dev/gemini-api/docs/rate-limits'; verified_on='2026-10-13'; scope='Gemini API project/model quotas; not Antigravity subscription or Gemini CLI quotas' }
        )
        principles = @(
            '使用当前官方支持的客户端和认证路径；不做 OAuth 反代、Token 提取、自动账号轮换或指纹伪造。'
            '遇到 403/11140 或 429 时暂停当前 UI/agent 连续重试；Gemini API 仅对可安全重放的瞬时错误遵循官方 API/SDK 有界退避，不自动重放有副作用的 agent 工作流。'
            '降智先核对上下文、模型、配额和调度；没有硬证据时不把主观感觉归因于风控。'
            '网络出口和 IP 分类只用于连通性诊断，不作为账号安全或资格证明。'
            '仓库、文件投影、宿主加载和真实业务接受分层证明，低层结果不能外推。'
        )
        forbidden_operations = @(
            'account_rotation_or_bulk_registration'
            'oauth_proxy_or_subscription_quota_gateway'
            'token_extraction_or_request_fingerprint_forgery'
            'quota_bypass_or_automatic_retry_storm'
            'device_id_forgery_or_credential_deletion'
        )
        platform_contracts = [pscustomobject][ordered]@{
            antigravity = [pscustomobject][ordered]@{
                allowed = @('official Antigravity client and supported account path', 'agy -p direct scripting or CI within the current FAQ', 'Gemini API key or Gemini Enterprise for a supported third-party coding agent', 'official quota and credits controls')
                blocked = @('third-party software through Antigravity credentials', 'wrapping agy in a third-party agent or app on consumer plans', 'automated account rotation or fallback used to evade quota')
            }
            workbuddy = [pscustomobject][ordered]@{
                allowed = @('official WorkBuddy International endpoints', 'stable network; direct/bypass is this deployment choice, not proof of account safety', 'custom model only when supported by the current official client and terms', 'official Retry-After/reset handling')
                blocked = @('subscription token extraction or quota bypass through a custom endpoint', 'token extraction or connector-proxy bypass', 'database/device-id edits to evade account risk control')
            }
        }
        flows = [pscustomobject][ordered]@{
            preflight = @('确认官方客户端、账号资格和支持地区', '区分 Antigravity 计划、Gemini API project 和 Gemini CLI 额度', '确认没有第三方 OAuth 网关或自动账号轮换', '记录当前模型、配额和会话基线')
            daily = @('控制并发和任务分段', '尊重 Retry-After/reset 时间', '避免错误后的连续重试和频繁重启', '保留脱敏日志与时间线')
            incident = @('停止重试', '区分账号风控、配额限流、网络错误和上下文问题', '按官方申诉或恢复渠道处理', '恢复后先低频观察，不做换号躲避')
        }
        evidence_layers = @('repo_verified', 'filesystem_projected', 'host_loaded', 'live_accepted')
    }
}

function Get-AiRiskControlIncidentPlan([string]$Event) {
    $plans = @{
        'antigravity-ban' = [ordered]@{ platform='antigravity'; category='account_safety'; severity='critical'; diagnosis='明确 service disabled / ToS 文本是服务限制信号；一般 403 仍需区分权限、资格与认证问题'; immediate=@('停止被拒服务的请求', '保存脱敏错误、时间、请求 ID 和客户端版本', '使用当前 Google 官方支持或反馈入口'); forbidden=@('换号继续同一套工具链', '反复重试或重启', '伪造设备或请求指纹') }
        'antigravity-rate-limit' = [ordered]@{ platform='antigravity'; category='quota_rate_limit'; severity='high'; diagnosis='429 RESOURCE_EXHAUSTED 可能来自配额窗口或服务容量，不等同封号；分别核验 Antigravity 订阅五小时/周额度、Gemini API project/model/spend cap 与 Gemini CLI 认证额度'; immediate=@('读取对应产品用量页和服务端等待提示；没有明确时间时按对应 API 官方建议减速并等待，不自造恢复时间', 'UI/agent 请求停止连续重试；Gemini API 仅对可安全重试的瞬时错误按官方 API/SDK 建议有限退避，不自动重放有副作用的任务；Antigravity 五小时刷新不保证周额度恢复', '只用当前产品支持的 credits 或模型选择，不自动换模型重放任何任务；控制后续非必要请求'); forbidden=@('绕过配额', '并发压测', '用多账号轮换掩盖消耗') }
        'antigravity-degradation' = [ordered]@{ platform='antigravity'; category='degradation_triage'; severity='medium'; diagnosis='对照同一任务并检查可见模型、上下文、思考/采样参数、输出截断、安全反馈和工具失败；没有官方证据不推断静默降智'; immediate=@('用相同材料和验收标准作少量短会话对照', '记录可见模型标识、上下文规模、finishReason/usage（若入口提供）及具体遗漏', '遇到 429、认证或明确服务拒绝时停止当前任务；复现问题提交官方反馈'); forbidden=@('把主观质量变化当作封号证据', '用降级链或第三方路由绕过官方选择') }
        'workbuddy-account-risk' = [ordered]@{ platform='workbuddy'; category='account_safety'; severity='critical'; diagnosis='403 / 11140 / request illegal 是拒绝信号；单条错误不能确认账号封禁，需排除认证、权限、内容和连接器错误'; immediate=@('停止重试和频繁重启', '保存 Trace ID、脱敏日志和账号时间线，区分模型请求与 MCP 认证', '通过 WorkBuddy 官方反馈渠道核实拒绝原因'); forbidden=@('伪造 device-id', '删除凭据或修改数据库绕过风控', '用订阅反代、积分中转或换号规避限制') }
        'workbuddy-rate-limit' = [ordered]@{ platform='workbuddy'; category='quota_rate_limit'; severity='high'; diagnosis='429 是服务限流线索；6003 / 6004 官方描述为请求频率受限，不能据此推导账号封禁或公开额度阈值；与 403 / 11140 拒绝信号分开处理'; immediate=@('遵守服务端 Retry-After/reset 或客户端显示的恢复提示；没有等待信息时停止重复请求并查官方用量/支持', '仅对 6003 / 6004 且当前官方客户端明确建议时，用户手动切换模型并重试一次；持续受限即停止', '降低后续不必要的并发和重复提交'); forbidden=@('连续重试风暴', '自建中转绕过限制', '切换账号规避窗口') }
        'workbuddy-degradation' = [ordered]@{ platform='workbuddy'; category='degradation_triage'; severity='medium'; diagnosis='先排查上下文、模型调度和额度；没有官方证据时不宣称存在静默风控降智'; immediate=@('新开短会话对照', '固定模型和任务输入后再测', '记录服务时间、模型和响应质量'); forbidden=@('用自定义 API 改道', '把偶发质量变化归因于账号处罚') }
    }
    if ([string]::IsNullOrWhiteSpace($Event)) { return $null }
    $entry = $plans[$Event]
    $entry['event'] = $Event
    $entry['basis'] = 'user_selected_scenario; not an automated diagnosis of the account'
    return [pscustomobject]$entry
}

function Get-AiRiskControlCooldown {
    param([string]$RetryAfter = '', [string]$ResetAt = '', [datetimeoffset]$Now = [datetimeoffset]::UtcNow)
    $candidates = [Collections.Generic.List[datetimeoffset]]::new()
    if ($RetryAfter) {
        [long]$seconds = 0
        [datetimeoffset]$httpDate = [datetimeoffset]::MinValue
        if ($RetryAfter -match '^\d+$' -and [long]::TryParse($RetryAfter, [ref]$seconds)) {
            try { $candidates.Add($Now.AddSeconds($seconds)) } catch { throw 'Retry-After seconds are out of range' }
        } elseif ([datetimeoffset]::TryParseExact($RetryAfter, 'r', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$httpDate)) {
            $candidates.Add($httpDate)
        } else { throw 'Retry-After must be nonnegative seconds or an RFC 1123 HTTP date' }
    }
    if ($ResetAt) {
        [datetimeoffset]$resetDate = [datetimeoffset]::MinValue
        if ($ResetAt -notmatch '^\d{4}-\d{2}-\d{2}T.+(?:Z|[+-]\d{2}:\d{2})$' -or
            -not [datetimeoffset]::TryParse($ResetAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$resetDate)) { throw 'reset-at must be an ISO 8601 timestamp with timezone' }
        $candidates.Add($resetDate)
    }
    if ($candidates.Count -eq 0) { return [pscustomobject]@{ state='unknown'; earliest_review_at=$null; automatic_retry=$false; note='服务端没有等待信息时查官方额度或人工复查；不自造恢复时间。' } }
    $candidates.Add($Now)
    $until = $candidates | Sort-Object -Descending | Select-Object -First 1
    [pscustomobject]@{ state='server_hint'; earliest_review_at=$until.ToUniversalTime().ToString('o'); automatic_retry=$false; note='采用 Retry-After、reset 和当前时间的最晚值；到期只允许复查，不保证请求会被接受。' }
}

function Get-AiRiskControlBaselinePlan {
    [pscustomobject][ordered]@{
        preflight = @('运行仓库资产检查', '确认目标客户端、账号资格和认证方式受当前官方文档支持', '确认适用产品的模型与额度页面', '把网络连通性检查与账号风险判断分开')
        during_use = @('并发不超产品公开限制，避免不必要并发', '长任务切段', '遇到 Retry-After/reset 立即停手', '保留脱敏错误证据')
        recovery = @('按事件类型分诊', '优先官方申诉或等待窗口', '恢复后低频观察并复核四层证据')
        stop_conditions = @('禁止绕过限制、自动轮换账号、伪造身份、提取令牌或压测服务')
    }
}

function Get-AiRiskControlAsset([string]$Root, [string]$RelativePath) {
    $path = Join-Path $Root $RelativePath
    return [pscustomobject][ordered]@{
        path = $RelativePath
        exists = [IO.File]::Exists($path) -or [IO.Directory]::Exists($path)
        kind = if ([IO.Directory]::Exists($path)) { 'directory' } elseif ([IO.File]::Exists($path)) { 'file' } else { 'missing' }
    }
}

function Invoke-AiRiskControlCommand {
    param([string[]]$Tokens = @())
    $opts = Parse-AiRiskControlArgs $Tokens
    if ($opts.help) {
        return [pscustomobject][ordered]@{
            usage = '.\skills.ps1 ai-risk-control [--platform all|antigravity|workbuddy] [--event <incident>] [--plan] [--json]'
            notes = @(
                '默认只读：只检查仓库资产，不改代理、账号、客户端、凭据或进程。'
                '使用 --plan 查看内置日常防范与恢复流程；使用 --event 查看事件分诊计划。'
                '本命令不运行宿主自检脚本，也不读取网络配置；它不能核验账号状态、服务端配额或实际网络链路。'
                '不提供多账号轮换、OAuth 反代、配额绕过、伪造指纹或自动重试。'
            )
            events = @('antigravity-ban', 'antigravity-rate-limit', 'antigravity-degradation', 'workbuddy-account-risk', 'workbuddy-rate-limit', 'workbuddy-degradation')
            cooldown_usage = '--event <platform>-rate-limit [--retry-after <seconds|HTTP-date>] [--reset-at <ISO8601-with-timezone>]'
        }
    }
    $cooldown = if ($opts.event -like '*-rate-limit') { Get-AiRiskControlCooldown -RetryAfter $opts.retry_after -ResetAt $opts.reset_at } else { $null }
    $root = $PSScriptRoot
    while (-not [IO.File]::Exists((Join-Path $root 'skills.json')) -and $root -ne [IO.Path]::GetPathRoot($root)) {
        $root = Split-Path $root -Parent
    }
    $assets = @(
        (Get-AiRiskControlAsset $root 'overrides/custom/antigravity-gemini-risk-triage/SKILL.md'),
        (Get-AiRiskControlAsset $root 'overrides/custom/workbuddy-risk-triage/SKILL.md')
    )
    $assetPass = @($assets | Where-Object { -not $_.exists }).Count -eq 0
    $result = [pscustomobject][ordered]@{
        schema_version = 2; command = 'ai-risk-control'; generated_at = [datetimeoffset]::UtcNow.ToString('o')
        truth_boundary = 'repo_verified'; platform = [string]$opts.platform
        controls = [pscustomobject][ordered]@{
            repository_assets = if ($assetPass) { 'present' } else { 'missing' }
            account_safety = 'policy_and_triage_plans'
            quota_and_backoff = 'documented; no automatic retry or quota bypass'
            degradation_triage = 'documented; compare model, quota, context, and scheduler before attributing risk control'
        }
        policy = Get-AiRiskControlPolicy
        plan = if ($opts.plan) { Get-AiRiskControlBaselinePlan } else { $null }
        incident = Get-AiRiskControlIncidentPlan ([string]$opts.event)
        cooldown = $cooldown
        assets = $assets
        status = if (-not $assetPass) { 'findings' } else { 'pass' }
        exit_code = if (-not $assetPass) { 1 } else { 0 }
        status_scope = 'repository_policy_assets_and_explicit_input_validation; not host_state_or_account_recovery'
        acceptance = [pscustomobject][ordered]@{ repo_verified = $assetPass; filesystem_projected = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }
        side_effects = @('no host configuration reads or writes', 'no process restart', 'no account or credential mutation')
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$opts.out_path)) {
        $out = [IO.Path]::GetFullPath($opts.out_path)
        $parent = Split-Path $out -Parent
        if ($parent -and -not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
        [IO.File]::WriteAllText($out, ($result | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    }
    return $result
}

