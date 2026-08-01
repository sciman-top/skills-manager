Describe "Skill profile benchmark" {
    It "Validates the complete lean versus strict corpus without model calls" {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        $scriptPath = Join-Path $repoRoot "scripts\benchmark-codex-skill-profiles.ps1"

        $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Json
        $LASTEXITCODE | Should Be 0
        $plan = ($raw -join "`n") | ConvertFrom-Json

        $plan.valid | Should Be $true
        @($plan.profiles) | Should Be @("coding", "coding-strict")
        @($plan.cases).Count | Should Be 12
        $plan.planned_calls | Should Be 24

        $corpus = Get-Content -LiteralPath (Join-Path $repoRoot "config\codex-skill-profile-benchmark.json") -Raw | ConvertFrom-Json
        $strictExpectations = @($corpus.cases | ForEach-Object { $_.expectations.'coding-strict' })
        @($strictExpectations | ForEach-Object { $_.required } | Where-Object { $_ -eq "using-superpowers" }).Count | Should Be 0
        @($strictExpectations | ForEach-Object { $_.forbidden } | Where-Object { $_ -eq "using-superpowers" }).Count | Should Be 12
    }

    It "Accepts comma-separated case filters from an external PowerShell process" {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        $scriptPath = Join-Path $repoRoot "scripts\benchmark-codex-skill-profiles.ps1"

        $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -CaseId "simple-explanation,unexpected-test-failure" -Json
        $LASTEXITCODE | Should Be 0
        $plan = ($raw -join "`n") | ConvertFrom-Json

        @($plan.cases) | Should Be @("simple-explanation", "unexpected-test-failure")
        $plan.planned_calls | Should Be 4
    }

    It "Rejects unsafe case ids before creating benchmark artifacts" {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        $scriptPath = Join-Path $repoRoot "scripts\benchmark-codex-skill-profiles.ps1"
        $corpusPath = Join-Path $TestDrive "unsafe-corpus.json"
        @'
{"profiles":["coding"],"cases":[{"id":"../escape","request":"read only","expectations":{"coding":{"required":[],"forbidden":[]}}}]}
'@ | Set-Content -LiteralPath $corpusPath -Encoding utf8

        $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -CorpusPath $corpusPath 2>&1

        $LASTEXITCODE | Should Not Be 0
        ($raw -join "`n") | Should Match "unsafe benchmark case id"
    }

    It "Fails closed when a successful model call violates expectations" {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        $sandboxRoot = Join-Path $TestDrive "semantic-failure"
        $scriptsRoot = Join-Path $sandboxRoot "scripts"
        $configRoot = Join-Path $sandboxRoot "config"
        $binRoot = Join-Path $sandboxRoot "bin"
        New-Item -ItemType Directory -Path $scriptsRoot, $configRoot, $binRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\benchmark-codex-skill-profiles.ps1") -Destination $scriptsRoot
        Copy-Item -LiteralPath (Join-Path $repoRoot "config\codex-skill-profile-benchmark-output.schema.json") -Destination $configRoot
        @'
param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Remaining)
exit 0
'@ | Set-Content -LiteralPath (Join-Path $sandboxRoot "skills.ps1") -Encoding utf8
        @'
{"skill_projection":{"active_profile":"default","profiles":{"default":{"enabled_names":[]}}}}
'@ | Set-Content -LiteralPath (Join-Path $sandboxRoot "skills.json") -Encoding utf8
        @'
{"profiles":["default"],"cases":[{"id":"semantic-failure","request":"read only","expectations":{"default":{"required":[],"forbidden":["forbidden-skill"]}}}]}
'@ | Set-Content -LiteralPath (Join-Path $configRoot "corpus.json") -Encoding utf8
        @'
@echo off
echo {"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}
echo {"type":"item.completed","item":{"type":"agent_message","text":"{\"selected_skills\":[\"forbidden-skill\"],\"would_create_plan\":false,\"would_delegate\":false,\"would_use_worktree\":false,\"reason\":\"fixture\"}"}}
'@ | Set-Content -LiteralPath (Join-Path $binRoot "codex.cmd") -Encoding ascii

        $oldPath = $env:PATH
        try {
            $env:PATH = "$binRoot;$oldPath"
            & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot "benchmark-codex-skill-profiles.ps1") `
                -CorpusPath (Join-Path $configRoot "corpus.json") -OutputRoot (Join-Path $sandboxRoot "artifacts") `
                -Profiles default -CaseId semantic-failure -Execute -Json | Out-Null
            $LASTEXITCODE | Should Be 1
        }
        finally {
            $env:PATH = $oldPath
        }
    }
}
