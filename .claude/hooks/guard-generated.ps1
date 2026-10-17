#requires -Version 7.0
# Claude Code PreToolUse 守卫：阻断对生成物与物化目录的直接 Edit/Write。
# 宿主通过 stdin 传入 JSON；阻断时以退出码 2 返回原因。输入无法解析或不含路径时放行，
# 避免守卫自身卡住工具调用。Bash 写入不在此守卫覆盖范围内，由 CI -CheckGenerated 兜底。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).ProviderPath
$raw = [Console]::In.ReadToEnd()
try { $event = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }
$target = [string]$event.tool_input.file_path
if ([string]::IsNullOrWhiteSpace($target)) { exit 0 }

$full = if ([IO.Path]::IsPathRooted($target)) { [IO.Path]::GetFullPath($target) } else { [IO.Path]::GetFullPath((Join-Path $root $target)) }
$rel = [IO.Path]::GetRelativePath($root, $full).Replace('\', '/')

$guardedFiles = @('skills.ps1')
$guardedDirs = @(
    'skills.lib/', 'agent/', 'vendor/', 'imports/',
    'rules/global/claude/', 'rules/global/codex/', 'rules/global/zcode/',
    'rules/global/antigravity/', 'rules/global/workbuddy/'
)
$blocked = ($guardedFiles -contains $rel) -or
    [bool]($guardedDirs | Where-Object { $rel.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })
if ($blocked) {
    [Console]::Error.WriteLine("blocked: $rel 是生成物或物化目录。请修改 src/、overrides/ 或 rules/global 源，再运行 build.ps1 重建。")
    exit 2
}
exit 0
