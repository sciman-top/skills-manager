#requires -Version 7.0
# Codex Stop 守卫：把"验证证据"和"生成物漂移"变成确定性裁决。
#
# 依据 learn.chatgpt.com/docs/hooks（2026-11-06 读取）：Stop 的决策不拒绝本轮，
# 而是以 reason 作为新的一轮继续提示词；exit 2 同样生效。本脚本只在任务真的
# 改过被跟踪或新增的文件时才裁决，纯问答轮次直接放行。
#
# 两条裁决：
#   1. 漂移：`build.ps1 -Check` 失败即阻断，stderr 回传给模型继续修。
#   2. 证据：本轮 worktree 有改动，但最后一条回复既没有命令块，也没有
#      "验证/verification" 段落，说明会话没跑任何检查就宣称完成。
#
# 这不是完整边界：`stop_hook_active` 为真时不再阻断，避免死循环；最终的
# 合并裁决仍是 CI。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
function Read-GuardStdinText {
    # 有界读取：宿主若不关闭 stdin，同步 ReadToEnd 会无限等待。Stop 守卫放行的
    # 后果只是本轮不裁决，因此超时即 fail-open，绝不挂住回合。实测未关闭
    # stdin 时旧实现会一直不返回。在基础流上异步读并给每次读一个上限，
    # 不派生子进程（守卫每回合都跑，额外进程会拖慢并造成并行抖动）。
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
        return ''
    }
    finally {
        $memory.Dispose()
    }
}
$raw = Read-GuardStdinText
try { $event = $raw | ConvertFrom-Json -ErrorAction Stop } catch { exit 0 }

# A turn already continued by this hook must be allowed to finish.
if ($event.stop_hook_active -eq $true) { exit 0 }

function Write-GuardReason([string]$Text) {
    # Stop 事件的非零退出必须把原因写进 stderr 才会回传给模型；exit 2 与
    # decision=block 等价，不需要额外的 JSON 输出。
    [Console]::Error.WriteLine($Text)
    [Console]::Out.Flush()
    [Console]::Error.Flush()
    exit 2
}

Push-Location $root
try {
    $changed = @(& git status --porcelain 2>$null)
    $statusExit = $LASTEXITCODE
    if ($statusExit -ne 0) { exit 0 }
    # 未跟踪文件同样算"改过工作区"：新增源文件也必须带证据。
    if (@($changed).Count -eq 0) { exit 0 }

    $checkOutput = @(& pwsh -NoProfile -File (Join-Path $root 'build.ps1') -Check 2>&1)
    $checkExit = $LASTEXITCODE
    if ($checkExit -ne 0) {
        $tail = @($checkOutput | Select-Object -Last 12 | ForEach-Object { [string]$_ }) -join "`n"
        Write-GuardReason "Stop guard: build.ps1 -Check failed. 生成物与源不同步或清单不符，先修复再结束本轮。输出：`n$tail"
    }

    $message = [string]$event.last_assistant_message
    if ([string]::IsNullOrWhiteSpace($message)) { exit 0 }
    $hasEvidence = ($message -match '(?m)^\s*```') -or ($message -match '(?i)\b(?:verification|verif(?:y|ied|ication)|验证|证据)\b')
    if ($hasEvidence) { exit 0 }

    Write-GuardReason 'Stop guard: 本轮改动了工作区，但最后一条回复没有给出命令/退出码或验证段落。请补上实际运行的检查与结果（未验证项也要明说），再结束本轮。'
}
finally {
    Pop-Location
}
