#requires -Version 7.0
# Claude Code PreToolUse 守卫：阻断对生成物与物化目录的直接写入（Edit/Write 与 Bash）。
# 宿主通过 stdin 传入 JSON；阻断时以退出码 2 返回原因。输入无法解析或无法判定时放行，
# 避免守卫自身卡住工具调用。Bash 只检查三类明确写入：重定向目标、写入动词的路径参数，
# 不检查命令整体，因此只读命令与写其他文件的命令不受影响。最终裁决仍是 CI -CheckGenerated。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).ProviderPath
$raw = [Console]::In.ReadToEnd()
try { $event = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

$guardedFiles = @('skills.ps1')
$guardedDirs = @(
    'skills.lib/', 'agent/', 'vendor/', 'imports/',
    'rules/global/claude/', 'rules/global/codex/', 'rules/global/zcode/',
    'rules/global/antigravity/', 'rules/global/workbuddy/'
)

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
    [Console]::Error.WriteLine("blocked: $Rel 是生成物或物化目录（$Via）。请修改 src/、overrides/ 或 rules/global 源，再运行 build.ps1 重建。")
    exit 2
}

$filePath = [string]$event.tool_input.file_path
if (-not [string]::IsNullOrWhiteSpace($filePath)) {
    $hit = Get-GuardedRel $filePath
    if ($hit) { Block $hit 'Edit/Write' }
    exit 0
}

$command = [string]$event.tool_input.command
if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

# 1) Redirections write to their target: `> path`, `>> path`. `2>&1` has no path target and is skipped.
foreach ($m in [regex]::Matches($command, '(?<!\d)>>?\s*(?<t>"[^"]+"|''[^'']+''|[^\s;&|]+)')) {
    $hit = Get-GuardedRel $m.Groups['t'].Value
    if ($hit) { Block $hit 'Bash redirection' }
}

# 2) Write verbs modify their path arguments: any guarded token after such a verb is a write.
# sed 只有原地编辑（-i / --in-place）才写文件，只读 sed -n 不应被阻断。
$writeVerb = '(?i)(?<![\w-])(Set-Content|Add-Content|Out-File|Remove-Item|Move-Item|Copy-Item|Rename-Item|Clear-Content|rm|mv|cp|tee|rmdir|del)(?![\w-])|(?<![\w-])sed\b[^|;&]*\s--?(?:\w*i\w*|in-place)(?=\s|\.|$)'
if ([regex]::IsMatch($command, $writeVerb)) {
    foreach ($tok in [regex]::Matches($command, '"[^"]+"|''[^'']+''|[^\s;&|()]+')) {
        $hit = Get-GuardedRel $tok.Value
        if ($hit) { Block $hit 'Bash write verb' }
    }
}
exit 0
