#Requires -Version 7
# Workspace UserPromptSubmit guard (wired in .zcode/config.json, hooks.enabled=true).
# Scope: forces the cold-routing entry-link judgment when a prompt carries an
# interaction-workflow verb. It never selects skills, never blocks (always exit 0),
# and only injects an obligation line via hookSpecificOutput.additionalContext.
$ErrorActionPreference = 'SilentlyContinue'

# Read stdin as raw bytes and decode UTF-8 explicitly: redirected console input
# otherwise decodes with the OEM codepage and mangles non-ASCII prompts.
$stdinStream = [Console]::OpenStandardInput()
$buffer = New-Object System.IO.MemoryStream
$stdinStream.CopyTo($buffer)
$raw = [Text.Encoding]::UTF8.GetString($buffer.ToArray())
$data = $null
try { $data = $raw | ConvertFrom-Json } catch {}
$prompt = if ($null -ne $data -and $null -ne ($data.PSObject.Properties['prompt'])) { [string]$data.prompt } else { $raw }

if (-not [string]::IsNullOrWhiteSpace($prompt) -and
    $prompt -match '审问|逐轮|一题|多轮|grill|interrogat|interview') {
    [pscustomobject][ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName = 'UserPromptSubmit'
            additionalContext = '[interaction-workflow-guard] This request carries interaction-workflow semantics (grill/interview/one-question-at-a-time/multi-turn). Before answering, run the cold-routing entry judgment: visible capability is sufficient only if it covers the WHOLE workflow including the multi-turn interaction; component-only coverage (for example evidence retrieval alone) is not sufficiency. Whichever path serves it (visible grill-me or cold-discovered grill-with-docs), a one-shot analysis/report/summary with trailing questions is forbidden (multi_turn_summary_substitution); evidence gathering serves the per-question interview and never replaces it.'
        }
    } | ConvertTo-Json -Compress
}
exit 0
