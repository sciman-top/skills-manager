[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourceHookPath = (Join-Path $PSScriptRoot 'block-cross-thread-send.ps1')
)

$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$hooksPath = Join-Path $resolvedCodexHome 'hooks.json'
$configPath = Join-Path $resolvedCodexHome 'config.toml'
$hostHook = Join-Path $resolvedCodexHome 'scripts\block-cross-thread-send.ps1'

$featuresEnabled = $true
if (Test-Path -LiteralPath $configPath) {
    $configText = Get-Content -Raw -LiteralPath $configPath
    if ($configText -match '(?mi)^\s*hooks\s*=\s*false\s*(?:#.*)?$') {
        $featuresEnabled = $false
    }
}

$sourceExists = Test-Path -LiteralPath $SourceHookPath
$hostExists = Test-Path -LiteralPath $hostHook
$hashMatches = $false
$sourceHash = $null
$hostHash = $null
if ($sourceExists) {
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceHookPath).Hash.ToLowerInvariant()
}
if ($hostExists) {
    $hostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant()
}
if ($sourceHash -and $hostHash) {
    $hashMatches = $sourceHash -ceq $hostHash
}

$definitionMatches = $false
if (Test-Path -LiteralPath $hooksPath) {
    try {
        $document = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json -Depth 50
        foreach ($group in @($document.hooks.PreToolUse)) {
            if ([string]$group.matcher -ne '*') {
                continue
            }
            foreach ($handler in @($group.hooks)) {
                if ([string]$handler.command -like "*$hostHook*" -and [string]$handler.command -like "*$hostHash*") {
                    $definitionMatches = $true
                }
            }
        }
    }
    catch {
        $definitionMatches = $false
    }
}

$simulationCases = [ordered]@{
    direct_send_tool = $false
    multiline_shell_send = $false
    nested_shell_send = $false
    read_only_subexpression_send = $false
    reader_exec_option_send = $false
}
if ($hostExists) {
    $probes = [ordered]@{
        direct_send_tool = [ordered]@{
            tool_name = 'codex_app__send_message_to_thread'
            tool_input = [ordered]@{ threadId = 'doctor-target'; prompt = 'blocked probe' }
        }
        multiline_shell_send = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = "Write-Output harmless`ncodex app-server request thread/send --thread doctor-target --prompt blocked"
            }
        }
        nested_shell_send = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = 'cmd /c codex app-server request thread/send --thread doctor-target --prompt blocked'
            }
        }
        read_only_subexpression_send = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = 'rg "$(codex app-server request thread/send --thread doctor-target --prompt blocked)" docs'
            }
        }
        reader_exec_option_send = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = 'rg --pre "codex app-server request thread/send --thread doctor-target --prompt blocked" thread/send docs'
            }
        }
    }

    foreach ($probe in $probes.GetEnumerator()) {
        $payload = [ordered]@{
            session_id = 'doctor-source'
            turn_id = 'doctor-turn'
            hook_event_name = 'PreToolUse'
            tool_name = $probe.Value.tool_name
            tool_use_id = "doctor-$($probe.Key)"
            tool_input = $probe.Value.tool_input
        } | ConvertTo-Json -Depth 8 -Compress
        $output = $payload | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hostHook -ExpectedScriptSha256 $hostHash 2>$null
        if ($LASTEXITCODE -eq 0 -and $output) {
            try {
                $decision = (@($output) -join "`n") | ConvertFrom-Json
                $simulationCases[$probe.Key] = [string]$decision.hookSpecificOutput.permissionDecision -eq 'deny'
            }
            catch {
                $simulationCases[$probe.Key] = $false
            }
        }
    }
}
$simulationPassed = @($simulationCases.Values | Where-Object { -not $_ }).Count -eq 0

$configurationReady = $featuresEnabled -and $hashMatches -and $definitionMatches -and $simulationPassed

[pscustomobject]@{
    configuration_ready = $configurationReady
    feature_enabled = $featuresEnabled
    source_sha256 = $sourceHash
    host_sha256 = $hostHash
    hash_matches = $hashMatches
    definition_matches = $definitionMatches
    simulation_passed = $simulationPassed
    simulation_cases = [pscustomobject]$simulationCases
    trust_status = 'unverified_requires_slash_hooks'
    live_path_status = 'unverified_requires_fresh_session_probe'
    specialized_path_boundary = 'guardrail_only'
    overall = 'soft_guard_only'
}
