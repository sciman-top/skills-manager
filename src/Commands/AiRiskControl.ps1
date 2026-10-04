# AI risk-control command surface.  This command is deliberately read-only:
# it inventories the repository controls and, when requested, runs the bundled
# host checks without changing proxy, account, client, or credential state.

function Parse-AiRiskControlArgs {
    param([string[]]$Tokens = @())
    $result = [ordered]@{
        platform = 'all'; mode = 'auto'; json = $false; run = $false
        out_path = ''; v2ray_config = ''; event = ''; plan = $false; help = $false
        retry_after = ''; reset_at = ''
    }
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = [string]$Tokens[$i]
        switch -Regex ($token) {
            '^(--help|-h)$' { $result.help = $true; continue }
            '^--json$' { $result.json = $true; continue }
            '^--checks$' { $result.run = $true; continue }
            '^--plan$' { $result.plan = $true; continue }
            '^--platform$' { if ($i + 1 -ge $Tokens.Count) { throw '--platform requires all|antigravity|workbuddy' }; $result.platform = [string]$Tokens[++$i]; continue }
            '^--mode$' { if ($i + 1 -ge $Tokens.Count) { throw '--mode requires auto|direct|v2rayn|custom-proxy' }; $result.mode = [string]$Tokens[++$i]; continue }
            '^--event$' { if ($i + 1 -ge $Tokens.Count) { throw '--event requires a supported incident type' }; $result.event = [string]$Tokens[++$i]; continue }
            '^--retry-after$' { if ($i + 1 -ge $Tokens.Count) { throw '--retry-after requires seconds or an HTTP date' }; $result.retry_after = [string]$Tokens[++$i]; continue }
            '^--reset-at$' { if ($i + 1 -ge $Tokens.Count) { throw '--reset-at requires an ISO 8601 timestamp with timezone' }; $result.reset_at = [string]$Tokens[++$i]; continue }
            '^--v2ray-config$' { if ($i + 1 -ge $Tokens.Count) { throw '--v2ray-config requires a path' }; $result.v2ray_config = [string]$Tokens[++$i]; continue }
            '^--out$' { if ($i + 1 -ge $Tokens.Count) { throw '--out requires a path' }; $result.out_path = [string]$Tokens[++$i]; continue }
            default { throw ('Unknown ai-risk-control option: {0}' -f $token) }
        }
    }
    if ($result.platform -notin @('all', 'antigravity', 'workbuddy')) { throw 'platform must be all, antigravity, or workbuddy' }
    if ($result.mode -notin @('auto', 'direct', 'v2rayn', 'custom-proxy')) { throw 'mode must be auto, direct, v2rayn, or custom-proxy' }
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
        purpose = '降低封号、限流和误判降智风险；不绕过服务方限制'
        enforcement = 'advisory_only; this command does not intercept host requests or enforce client concurrency'
        official_sources = @(
            [pscustomobject]@{ url='https://antigravity.google/terms'; verified_on='2026-10-04'; scope='Antigravity OAuth third-party access restriction' }
            [pscustomobject]@{ url='https://www.workbuddy.ai/document/term'; verified_on='2026-10-04'; scope='International service protection and reasonable use' }
            [pscustomobject]@{ url='https://ai.google.dev/gemini-api/docs/rate-limits'; verified_on='2026-10-04'; scope='Gemini API project/model quotas; not Antigravity subscription quotas' }
        )
        principles = @(
            '保持官方客户端、官方认证和单一稳定身份；不做 OAuth 反代、Token 提取、多账号轮换或指纹伪造。'
            '遇到 403/11140 或 429 先停止重试，保存错误证据，再按账号风控与配额限流分流。'
            '降智先核对上下文、模型、配额和调度；没有硬证据时不把主观感觉归因于风控。'
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
                allowed = @('official Antigravity/Gemini client or approved official API path', 'stable low-frequency egress', 'official quota and credits controls')
                blocked = @('third-party software through Antigravity OAuth', 'account rotator or fallback chain used to evade quota')
            }
            workbuddy = [pscustomobject][ordered]@{
                allowed = @('official WorkBuddy International endpoints', 'stable network; direct/bypass is this deployment choice, not proof of account safety', 'custom model only when supported by the current official client and terms', 'official Retry-After/reset handling')
                blocked = @('subscription token extraction or quota bypass through a custom endpoint', 'token extraction or connector-proxy bypass', 'database/device-id edits to evade account risk control')
            }
        }
        flows = [pscustomobject][ordered]@{
            preflight = @('确认官方客户端与版本', '确认出口和代理边界稳定', '确认没有第三方网关、反代或异常连接器', '记录当前模型、配额和会话基线')
            daily = @('控制并发和任务分段', '尊重 Retry-After/reset 时间', '避免错误后的连续重试和频繁重启', '保留脱敏日志与时间线')
            incident = @('停止重试', '区分账号风控、配额限流、网络错误和上下文问题', '按官方申诉或恢复渠道处理', '恢复后先低频观察，不做换号躲避')
        }
        evidence_layers = @('repo_verified', 'filesystem_projected', 'host_loaded', 'live_accepted')
    }
}

function Get-AiRiskControlIncidentPlan([string]$Event) {
    $plans = @{
        'antigravity-ban' = [ordered]@{ platform='antigravity'; category='account_safety'; severity='critical'; diagnosis='403 / service disabled / ToS 违规提示优先按账号或服务资格风控处理'; immediate=@('立即停止第三方 OAuth、网关和复用订阅的工具', '保存脱敏错误、时间、客户端版本和请求上下文', '使用 Google 官方申诉或再认证渠道'); forbidden=@('换号继续同一套工具链', '反复重试或重启', '伪造设备或请求指纹') }
        'antigravity-rate-limit' = [ordered]@{ platform='antigravity'; category='quota_rate_limit'; severity='high'; diagnosis='429 RESOURCE_EXHAUSTED / Quota exceeded 属配额或频率窗口，不等同封号'; immediate=@('读取服务端给出的 reset 时间或配额面板', '暂停请求并把长任务切段', '仅使用官方允许的模型或 credits 方案'); forbidden=@('绕过配额', '并发压测', '用多账号轮换掩盖消耗') }
        'antigravity-degradation' = [ordered]@{ platform='antigravity'; category='degradation_triage'; severity='medium'; diagnosis='先比较上下文长度、实际模型、配额状态和高峰调度；静默降智没有硬证据时不作结论'; immediate=@('新开短会话复现', '记录模型标识、上下文规模和输出差异', '等待配额或调度窗口后低频复测'); forbidden=@('把主观质量变化当作封号证据', '用降级链或第三方路由绕过官方选择') }
        'workbuddy-account-risk' = [ordered]@{ platform='workbuddy'; category='account_safety'; severity='critical'; diagnosis='403 / 11140 / request illegal 是拒绝信号；单条错误不能确认账号封禁，需排除认证、权限、内容和连接器错误'; immediate=@('停止重试和频繁重启', '保存 Trace ID、脱敏日志和账号时间线，区分模型请求与 MCP 认证', '通过 WorkBuddy 官方反馈渠道核实拒绝原因'); forbidden=@('伪造 device-id', '删除凭据或修改数据库绕过风控', '用订阅反代、积分中转或换号规避限制') }
        'workbuddy-rate-limit' = [ordered]@{ platform='workbuddy'; category='quota_rate_limit'; severity='high'; diagnosis='429 / 6003 / 6004 属频率或额度限制，与 403/11140 处置路径不同'; immediate=@('读取 Retry-After 或 reset 时间', '等待窗口并降低并发', '按官方建议切换模型或切段任务'); forbidden=@('连续重试风暴', '自建中转绕过限制', '切换账号规避窗口') }
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

function Protect-AiRiskControlOutput([string]$Value) {
    $Value = [regex]::Replace($Value, '(?i)(?<=://)[^/@\s]+@', '<redacted>@')
    $Value = [regex]::Replace($Value, '(?i)\bBearer\s+[^\s,;"\x27]+', 'Bearer <redacted>')
    $Value = [regex]::Replace($Value, '(?i)(["\x27]?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|authorization|password|secret)["\x27]?\s*[:=]\s*)(?:"[^"\r\n]*"|\x27[^\x27\r\n]*\x27|[^\s,;]+)', '$1<redacted>')
    $Value = [regex]::Replace($Value, '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', '<id-redacted>')
    return $Value
}

function Get-AiRiskControlBaselinePlan {
    [pscustomobject][ordered]@{
        preflight = @('运行仓库资产检查', '确认目标客户端使用官方入口', '确认代理/直连边界与出口稳定', '记录模型、配额和并发基线')
        during_use = @('单账号低并发', '长任务切段', '遇到 Retry-After/reset 立即停手', '保留脱敏错误证据')
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

function Invoke-AiRiskControlReadOnlyCheck([string]$Path, [string[]]$Arguments = @(), [int]$TimeoutSeconds = 180) {
    if (-not [IO.File]::Exists($Path)) {
        return [pscustomobject][ordered]@{ status = 'not_available'; path = $Path; exit_code = $null; output = '' }
    }
    # Bounded wait: the bundled host checks contain several 25s network probes, so
    # an unbounded invocation could stall this read-only command for minutes.
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Process -Id $PID).Path
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($arg in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path) + @($Arguments)) { $psi.ArgumentList.Add([string]$arg) }
    $proc = $null
    try {
        $proc = [Diagnostics.Process]::Start($psi)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)) {
            try { $proc.Kill($true) } catch { }
            return [pscustomobject][ordered]@{
                status = 'timeout'; path = $Path; exit_code = $null
                output = Protect-AiRiskControlOutput (("check exceeded {0}s and was terminated; a timeout is not a risk finding. partial output: {1}" -f $TimeoutSeconds, $stdoutTask.Result))
            }
        }
        $proc.WaitForExit()
        $out = @($stdoutTask.Result, $stderrTask.Result) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        return [pscustomobject][ordered]@{
            status = if ($proc.ExitCode -eq 0) { 'pass' } else { 'findings' }
            path = $Path; exit_code = [int]$proc.ExitCode
            output = Protect-AiRiskControlOutput ($out -join "`n")
        }
    }
    catch {
        return [pscustomobject][ordered]@{ status = 'error'; path = $Path; exit_code = $null; output = (Protect-AiRiskControlOutput $_.Exception.Message) }
    }
    finally {
        if ($proc) { $proc.Dispose() }
    }
}

function Invoke-AiRiskControlCommand {
    param([string[]]$Tokens = @())
    $opts = Parse-AiRiskControlArgs $Tokens
    if ($opts.help) {
        return [pscustomobject][ordered]@{
            usage = '.\skills.ps1 ai-risk-control [--platform all|antigravity|workbuddy] [--mode auto|direct|v2rayn|custom-proxy] [--event <incident>] [--plan] [--checks] [--json]'
            notes = @(
                '默认只读：只检查仓库资产，不改代理、账号、客户端、凭据或进程。'
                '直连与 v2rayN 都是网络模式声明；v2rayN 配置只接受显式 --v2ray-config 路径并做存在性检查。'
                '使用 --plan 查看内置日常防范与恢复流程；使用 --event 查看事件分诊计划。'
                '--checks 有 180 秒上限；超时记为 timeout，不计入风险 findings。'
                'Antigravity 自检需要 v2rayN/10810 部署根（默认 D:\TOOL\v2rayN，可用 AG_RISK_V2RAY_ROOT 覆盖）；缺失时记为 not_configured 而不是风险。'
                'WorkBuddy 自检使用 PowerShell 简化版，不含 .sh 版的 MCP 认证细分。'
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
        (Get-AiRiskControlAsset $root 'overrides/custom/workbuddy-risk-triage/SKILL.md'),
        (Get-AiRiskControlAsset $root 'docs/handover/ai-risk-control/tools/ag-health-check.ps1'),
        (Get-AiRiskControlAsset $root 'docs/handover/ai-risk-control/tools/workbuddy/workbuddy-risk-selfcheck.ps1'),
        (Get-AiRiskControlAsset $root 'docs/handover/ai-risk-control/tools/workbuddy/workbuddy-risk-selfcheck.sh')
    )
    $assetPass = @($assets | Where-Object { -not $_.exists }).Count -eq 0
    $network = [ordered]@{ requested_mode = [string]$opts.mode; v2ray_config = $null; mutation = 'none' }
    if (-not [string]::IsNullOrWhiteSpace([string]$opts.v2ray_config)) {
        $cfgPath = [IO.Path]::GetFullPath($opts.v2ray_config)
        $network.v2ray_config = [pscustomobject][ordered]@{ path = $cfgPath; exists = [IO.File]::Exists($cfgPath); readable = $false; sha256 = $null }
        if ([IO.File]::Exists($cfgPath)) {
            try {
                $bytes = [IO.File]::ReadAllBytes($cfgPath)
                $network.v2ray_config.readable = $true
                $network.v2ray_config.sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            } catch { $network.v2ray_config.readable = $false }
        }
    }
    $checks = @()
    if ($opts.run -and $opts.platform -in @('all', 'antigravity') -and $opts.mode -in @('direct', 'custom-proxy')) {
        $checks += [pscustomobject]@{ status='not_available'; path='ag-health-check.ps1'; exit_code=$null; output='现有 Antigravity 网络自检只覆盖本项目的 v2rayN/10810 分流部署；当前模式不能据此验收。' }
    } elseif ($opts.run -and $opts.platform -in @('all', 'antigravity')) {
        # The Antigravity check hard-depends on the v2rayN/ag-split deployment.
        # Without that deployment it can only emit FAILs, which must not be
        # mistaken for account risk. Override the root with AG_RISK_V2RAY_ROOT.
        $agRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:AG_RISK_V2RAY_ROOT)) { [string]$env:AG_RISK_V2RAY_ROOT } else { 'D:\TOOL\v2rayN' }
        if (-not [IO.Directory]::Exists($agRoot)) {
            $checks += [pscustomobject][ordered]@{
                status = 'not_configured'; path = 'ag-health-check.ps1'; exit_code = $null; deployment_root = $agRoot
                output = ("未检测到部署根 {0}；Antigravity 链路自检依赖该部署，已跳过，以免把「未部署」误报为风险。可用 AG_RISK_V2RAY_ROOT 覆盖。" -f $agRoot)
            }
        } else {
            $checks += Invoke-AiRiskControlReadOnlyCheck (Join-Path $root 'docs/handover/ai-risk-control/tools/ag-health-check.ps1') -TimeoutSeconds 180
        }
    }
    if ($opts.run -and $opts.platform -in @('all', 'workbuddy')) {
        $checks += Invoke-AiRiskControlReadOnlyCheck (Join-Path $root 'docs/handover/ai-risk-control/tools/workbuddy/workbuddy-risk-selfcheck.ps1') @('-NoFile') -TimeoutSeconds 180
    }
    $configUnavailable = $null -ne $network.v2ray_config -and -not $network.v2ray_config.readable
    # not_configured / timeout mean "could not assess", not "risk found".
    $checksHaveFindings = @($checks | Where-Object { $_.status -notin @('pass', 'not_configured', 'timeout') }).Count -gt 0
    $result = [pscustomobject][ordered]@{
        schema_version = 1; command = 'ai-risk-control'; generated_at = [datetimeoffset]::UtcNow.ToString('o')
        truth_boundary = 'repo_verified'; platform = [string]$opts.platform; network = [pscustomobject]$network
        controls = [pscustomobject][ordered]@{
            repository_assets = if ($assetPass) { 'present' } else { 'missing' }
            account_safety = 'policy_and_read_only_diagnostics'
            quota_and_backoff = 'documented; no automatic retry or quota bypass'
            degradation_triage = 'documented; compare model, quota, context, and scheduler before attributing risk control'
            proxy_scope = 'egress_only; never reuse OAuth or expose subscription quota through a gateway'
        }
        policy = Get-AiRiskControlPolicy
        plan = if ($opts.plan) { Get-AiRiskControlBaselinePlan } else { $null }
        incident = Get-AiRiskControlIncidentPlan ([string]$opts.event)
        cooldown = $cooldown
        assets = $assets; checks = $checks
        check_variants = [pscustomobject][ordered]@{
            antigravity = 'ag-health-check.ps1 over the v2rayN/10810 split deployment; needs AG_RISK_V2RAY_ROOT (default D:\TOOL\v2rayN)'
            workbuddy = 'workbuddy-risk-selfcheck.ps1 PowerShell simplified variant; omits the MCP-auth breakdown the .sh variant covers'
            timeout_seconds = 180
            note = 'not_configured / not_available / timeout mean "could not assess"; only pass/findings/error feed the aggregate status.'
        }
        status = if (-not $assetPass -or $checksHaveFindings -or $configUnavailable) { 'findings' } else { 'pass' }
        exit_code = if (-not $assetPass -or $checksHaveFindings -or $configUnavailable) { 1 } else { 0 }
        status_scope = 'repository_assets_and_requested_checks; not account_recovery'
        acceptance = [pscustomobject][ordered]@{ repo_verified = $assetPass; filesystem_projected = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }
        side_effects = @('no configuration writes', 'no process restart', 'no account or credential mutation')
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$opts.out_path)) {
        $out = [IO.Path]::GetFullPath($opts.out_path)
        $parent = Split-Path $out -Parent
        if ($parent -and -not [IO.Directory]::Exists($parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
        [IO.File]::WriteAllText($out, ($result | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    }
    return $result
}

