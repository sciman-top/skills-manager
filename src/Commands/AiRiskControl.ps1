# AI risk-control command surface.  This command is deliberately read-only:
# it inventories the repository controls and, when requested, runs the bundled
# host checks without changing proxy, account, client, or credential state.

function Parse-AiRiskControlArgs {
    param([string[]]$Tokens = @())
    $result = [ordered]@{
        platform = 'all'; mode = 'auto'; json = $false; run = $false
        out_path = ''; v2ray_config = ''; help = $false
    }
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = [string]$Tokens[$i]
        switch -Regex ($token) {
            '^(--help|-h)$' { $result.help = $true; continue }
            '^--json$' { $result.json = $true; continue }
            '^--checks$' { $result.run = $true; continue }
            '^--platform$' { if ($i + 1 -ge $Tokens.Count) { throw '--platform requires all|antigravity|workbuddy' }; $result.platform = [string]$Tokens[++$i]; continue }
            '^--mode$' { if ($i + 1 -ge $Tokens.Count) { throw '--mode requires auto|direct|v2rayn|custom-proxy' }; $result.mode = [string]$Tokens[++$i]; continue }
            '^--v2ray-config$' { if ($i + 1 -ge $Tokens.Count) { throw '--v2ray-config requires a path' }; $result.v2ray_config = [string]$Tokens[++$i]; continue }
            '^--out$' { if ($i + 1 -ge $Tokens.Count) { throw '--out requires a path' }; $result.out_path = [string]$Tokens[++$i]; continue }
            default { throw ('Unknown ai-risk-control option: {0}' -f $token) }
        }
    }
    if ($result.platform -notin @('all', 'antigravity', 'workbuddy')) { throw 'platform must be all, antigravity, or workbuddy' }
    if ($result.mode -notin @('auto', 'direct', 'v2rayn', 'custom-proxy')) { throw 'mode must be auto, direct, v2rayn, or custom-proxy' }
    return [pscustomobject]$result
}

function Get-AiRiskControlAsset([string]$Root, [string]$RelativePath) {
    $path = Join-Path $Root $RelativePath
    return [pscustomobject][ordered]@{
        path = $RelativePath
        exists = [IO.File]::Exists($path) -or [IO.Directory]::Exists($path)
        kind = if ([IO.Directory]::Exists($path)) { 'directory' } elseif ([IO.File]::Exists($path)) { 'file' } else { 'missing' }
    }
}

function Invoke-AiRiskControlReadOnlyCheck([string]$Path, [string[]]$Arguments = @()) {
    if (-not [IO.File]::Exists($Path)) {
        return [pscustomobject][ordered]@{ status = 'not_available'; path = $Path; exit_code = $null; output = '' }
    }
    try {
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1)
        return [pscustomobject][ordered]@{
            status = if ($LASTEXITCODE -eq 0) { 'pass' } else { 'findings' }
            path = $Path; exit_code = [int]$LASTEXITCODE
            output = (($output | ForEach-Object { [string]$_ }) -join "`n")
        }
    }
    catch {
        return [pscustomobject][ordered]@{ status = 'error'; path = $Path; exit_code = $null; output = $_.Exception.Message }
    }
}

function Invoke-AiRiskControlCommand {
    param([string[]]$Tokens = @())
    $opts = Parse-AiRiskControlArgs $Tokens
    if ($opts.help) {
        return [pscustomobject][ordered]@{
            usage = '.\skills.ps1 ai-risk-control [--platform all|antigravity|workbuddy] [--mode auto|direct|v2rayn|custom-proxy] [--checks] [--json]'
            notes = @(
                '默认只读：只检查仓库资产，不改代理、账号、客户端、凭据或进程。'
                '直连与 v2rayN 都是网络模式声明；v2rayN 配置只接受显式 --v2ray-config 路径并做存在性检查。'
                '不提供多账号轮换、OAuth 反代、配额绕过、伪造指纹或自动重试。'
            )
        }
    }
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
    if ($opts.run -and $opts.platform -in @('all', 'antigravity')) {
        $checks += Invoke-AiRiskControlReadOnlyCheck (Join-Path $root 'docs/handover/ai-risk-control/tools/ag-health-check.ps1')
    }
    if ($opts.run -and $opts.platform -in @('all', 'workbuddy')) {
        $checks += Invoke-AiRiskControlReadOnlyCheck (Join-Path $root 'docs/handover/ai-risk-control/tools/workbuddy/workbuddy-risk-selfcheck.ps1') @('-NoFile')
    }
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
        assets = $assets; checks = $checks
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

