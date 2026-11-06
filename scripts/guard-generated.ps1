#requires -Version 7.0
param(
    # Codex 的 hook 只认 JSON 决策：实测 `exit 2` 会被记为 "PreToolUse Failed" 并
    # 继续执行工具（真实 apply_patch 因此写穿了生成物），而 Claude Code 的约定是
    # `exit 2` + stderr。用显式开关区分，不靠猜宿主。
    [switch]$DenyJson
)
# 生成物守卫（宿主中立）：阻断对生成物与物化目录的直接写入。
#
# 两个宿主共用本脚本，不各自复制一份守卫：
#   - Claude Code: .claude/settings.json 的 PreToolUse（Edit|MultiEdit|Write|Bash）
#   - Codex:       .codex/config.toml 的 [[hooks.PreToolUse]]（^Bash$ 与 ^apply_patch$）
#
# 契约：宿主的 stdin 事件 JSON 含 tool_input.file_path（编辑类）或
# tool_input.command（Bash/apply_patch patch 文本）。命中的路径以退出码 2 阻断，
# 原因写 stderr。输入无法解析、路径无法规范化或没有可判定字段时放行（exit 0），
# 守卫自身不能把工具调用卡死。Bash 只检查三类明确写入：重定向目标、写入动词的
# 路径参数、git 写入子命令的路径参数。
#
# 该守卫不是完整边界：它挡不住未建模的写入路径（例如任意程序内部写文件）。
# 最终裁决是 CI 的 `build.ps1 -Check`（-CheckGenerated）。见 docs/runbooks/agent-hook-enforcement.md。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$script:DenyJsonMode = [bool]$DenyJson
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
function Read-GuardStdinText {
    # 有界读取：宿主写完事件后若迟迟不关 stdin，同步 ReadToEnd 会无限等待，
    # 把工具调用挂死（实测未关闭 stdin 时旧实现 8s 仍未返回）。
    #
    # 在基础流上做异步读并给每次读一个上限，不派生子进程：守卫每次工具调用
    # 都会执行，额外进程既拖慢判定，也会在并行测试里争抢资源导致抖动。
    # 判据是守卫对不可读输入本就 fail-open，因此超时即返回空串（调用方 exit 0）。
    $stream = [Console]::OpenStandardInput()
    if ($null -eq $stream) { return '' }
    $buffer = [byte[]]::new(65536)
    $memory = [IO.MemoryStream]::new()
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    try {
        while ($true) {
            $remaining = [int](($deadline - [DateTime]::UtcNow).TotalMilliseconds)
            if ($remaining -le 0) { return '' }
            $readTask = $stream.ReadAsync($buffer, 0, $buffer.Length)
            if (-not $readTask.Wait($remaining)) { return '' }
            $count = $readTask.Result
            if ($count -le 0) { break }
            $memory.Write($buffer, 0, $count)
        }
        return [Text.Encoding]::UTF8.GetString($memory.ToArray())
    }
    catch {
        # 读取失败同样按不可读放行。
        return ''
    }
    finally {
        $memory.Dispose()
    }
}
$raw = Read-GuardStdinText
try { $event = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$guardedFiles = @('skills.ps1')
$guardedDirs = @(
    'skills.lib/', 'agent/', 'vendor/', 'imports/',
    'rules/global/claude/', 'rules/global/codex/', 'rules/global/zcode/',
    'rules/global/antigravity/', 'rules/global/workbuddy/', 'rules/global/dsh/'
)
# 代码宿主（生成 skills.ps1 / skills.lib 的输入）。只用于 Codex apply_patch 的
# "生成物必须与其源同批提交" 判定，普通编辑不阻断。
$sourceMarkers = @('src/', 'build.ps1')

# Returns the repo-relative guarded path for a token, or '' when the token is not guarded.
function Get-GuardedRel([string]$Token) {
    if ([string]::IsNullOrWhiteSpace($Token)) { return '' }
    try {
        $p = $Token.Trim('"', "'")
        $full = if ([IO.Path]::IsPathRooted($p)) { [IO.Path]::GetFullPath($p) } else { [IO.Path]::GetFullPath((Join-Path $root $p)) }
        $rel = [IO.Path]::GetRelativePath($root, $full).Replace('\', '/')
    }
    catch { return '' }
    if ($guardedFiles -contains $rel) { return $rel }
    if ([bool]($guardedDirs | Where-Object { $rel.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })) { return $rel }
    return ''
}

function Block([string]$Rel, [string]$Via) {
    $reason = "blocked: $Rel 是生成物或物化目录（$Via）。请修改 src/、overrides/ 或 rules/global 源，再运行 build.ps1 重建。"
    if ($script:DenyJsonMode) {
        # Codex 的阻断形态：stdout 上的 hookSpecificOutput.permissionDecision。
        # 退出码仍用 0，避免 Codex 把它归为 hook 失败。
        $decision = [pscustomobject][ordered]@{
            hookSpecificOutput = [pscustomobject][ordered]@{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = $reason
            }
        }
        [Console]::Out.WriteLine(($decision | ConvertTo-Json -Compress -Depth 5))
        [Console]::Out.Flush()
        exit 0
    }
    [Console]::Error.WriteLine($reason)
    exit 2
}

function Test-Guarded([string]$Token, [string]$Via) {
    $hit = Get-GuardedRel $Token
    if ($hit) { Block $hit $Via }
}

# Codex apply_patch payload: count occurrences of the patch marker for one path so
# Add/Update need a source file in the same patch while Delete stands alone.
function Get-PatchPathCount([string]$Patch, [string]$Rel) {
    $escaped = [regex]::Escape($Rel)
    return [regex]::Matches($Patch, "(?im)^\*\*\* (?:Add|Update) File:\s*(?:\S*[\\/])?$escaped\s*$").Count
}

$filePath = [string]$event.tool_input.file_path
if (-not [string]::IsNullOrWhiteSpace($filePath)) {
    Test-Guarded $filePath 'Edit/Write'
    exit 0
}

# Codex sends the apply_patch payload in `tool_input.command` (the patch text is
# the "command"), not in a `patch` field: a real `apply_patch` edit slipped past
# an earlier version of this guard that only read `tool_input.patch`. Accept both
# shapes, and also treat any command that starts with the patch header as a patch
# so the Bash path-write heuristics cannot silently pass it.
$patch = [string]$event.tool_input.patch
if ([string]::IsNullOrWhiteSpace($patch)) {
    $candidateCommand = [string]$event.tool_input.command
    if ($candidateCommand -match '(?im)^\s*\*\*\* Begin Patch') { $patch = $candidateCommand }
}
if (-not [string]::IsNullOrWhiteSpace($patch)) {
    $targets = @([regex]::Matches($patch, '(?im)^\*\*\* (?:Add|Update|Delete) File:\s*(?<p>\S+)\s*$') | ForEach-Object { $_.Groups['p'].Value })
    if (@($targets).Count -eq 0) { exit 0 }
    $guardedTargets = @($targets | Where-Object { Get-GuardedRel $_ })
    if (@($guardedTargets).Count -eq 0) { exit 0 }
    $codeTargets = @($targets | Where-Object { $rel = $_.Replace('\', '/'); [bool](@($sourceMarkers | Where-Object { $rel.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })) })
    if (@($codeTargets).Count -gt 0) { exit 0 }
    foreach ($target in $guardedTargets) {
        # 删除生成文件不需要同批源改动；新增/修改必须带上源，否则就是一键手工改生成物。
        if ($patch -match ('(?im)^\*\*\* Delete File:\s*' + [regex]::Escape($target) + '\s*$')) { continue }
        Block (Get-GuardedRel $target) 'apply_patch'
    }
    exit 0
}

$command = [string]$event.tool_input.command
if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

# 1) Redirections write to their target: `> path`, `>> path`. `2>&1` has no path target and is skipped.
foreach ($m in [regex]::Matches($command, '(?<!\d)>>?\s*(?<t>"[^"]+"|''[^'']+''|[^\s;&|]+)')) {
    Test-Guarded $m.Groups['t'].Value 'Bash redirection'
}

# 2) Write verbs modify their path arguments: any guarded token after such a verb is a write.
# sed 只有原地编辑（-i / --in-place）才写文件，只读 sed -n 不应被阻断。
$writeVerb = '(?i)(?<![\w-])(Set-Content|Add-Content|Out-File|Remove-Item|Move-Item|Copy-Item|Rename-Item|Clear-Content|rm|mv|cp|tee|rmdir|del)(?![\w-])|(?<![\w-])sed\b[^|;&]*(?<=\s)(?:-[A-Za-z]*i\S*|--in-place(?:=\S*)?)(?=\s|$)'
# 3) git 子命令可整体切换树内的受管路径（git checkout -- <path>），也能把授权改动
#    回退掉，因此 v1 纳入 guard。其余 git 子命令（如 `git diff -- skills.lib/x`）是只读。
$gitWrite = '(?i)(?<![\w-])git(?:\s+-{1,2}[A-Za-z0-9-]+(?:=\S+)?)*\s+(?:(?:-{1,2}[A-Za-z0-9-]+(?:=\S+)?)\s+)*(?:rm|mv|restore|checkout|reset|clean|stash|apply|switch)(?![\w-])'
if ([regex]::IsMatch($command, $writeVerb) -or [regex]::IsMatch($command, $gitWrite)) {
    foreach ($tok in [regex]::Matches($command, '"[^"]+"|''[^'']+''|[^\s;&|()]+')) {
        $value = $tok.Value
        # `git clean -fd rules/global/dsh` 的最后一个 token 是目录前缀本身，不带尾斜杠；
        # 目录前缀需要按前缀命中，因此补一个分隔符再判定。只影响 guard 比对，不改写路径。
        if ($guardedDirs -contains "$value/") { $value = "$value/" }
        Test-Guarded $value 'Bash write verb'
    }
}
exit 0
