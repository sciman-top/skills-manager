Describe 'Independent model preset behavior' {
    It 'preserves exact process arguments without contacting a model' {
        $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'src/model-orchestration/Start-ModelSlot.ps1'), [ref]$null, [ref]$null)
        $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ModelSlotProcess' }, $true).Extent.Text
        . ([scriptblock]::Create($definition))
        $shimPath = Join-Path $TestDrive 'argument shim.ps1'
        [IO.File]::WriteAllText($shimPath, 'ConvertTo-Json -InputObject @($args) -Compress -EscapeHandling EscapeNonAscii')
        $expected = @('two words','中文参数','quote"inside','trailing\')
        $result = Invoke-ModelSlotProcess -Executable $shimPath -Arguments $expected -LimitSeconds 10
        $result.started | Should -BeTrue
        $result.exit_code | Should -Be 0
        $result.timed_out | Should -BeFalse
        $actual = ($result.output -join "`n") | ConvertFrom-Json
        $actual.Count | Should -Be $expected.Count
        for ($i=0; $i -lt $expected.Count; $i++) { $actual[$i] | Should -BeExactly $expected[$i] }
    }

    It 'terminates its own timed-out local process with a bounded wait' {
        $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'src/model-orchestration/Start-ModelSlot.ps1'), [ref]$null, [ref]$null)
        $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ModelSlotProcess' }, $true).Extent.Text
        . ([scriptblock]::Create($definition))
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-ModelSlotProcess -Executable pwsh -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 30') -LimitSeconds 1
        $watch.Stop()
        $result.started | Should -BeTrue
        $result.timed_out | Should -BeTrue
        $result.timeout_kind | Should -Be 'process_timeout'
        $result.exit_code | Should -Be 124
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 10
        Get-Process -Id $result.process_id -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'verifies routes, launch arguments, disposable projections and exact rollback' {
        $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $output = & pwsh -NoProfile -File (Join-Path $repoRoot 'src/model-orchestration/Test-ModelPreset.ps1') 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }

    It 'plans, creates and rolls back a first-run Claude configuration' {
        $scriptPath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) 'src/model-orchestration/Set-ModelPreset.ps1'
        $claudeRoot = Join-Path $TestDrive 'claude-first-run'
        $plan = & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Plan -SubagentsOnly | ConvertFrom-Json
        $plan.files.Count | Should -Be 10
        Test-Path -LiteralPath $claudeRoot | Should -BeFalse
        $applied = & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Apply -SubagentsOnly | ConvertFrom-Json
        $settingsPath = Join-Path $claudeRoot 'settings.json'
        Test-Path -LiteralPath $settingsPath | Should -BeTrue
        (& $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Plan -SubagentsOnly | ConvertFrom-Json).files.Count | Should -Be 0
        $legacyPath = Join-Path $claudeRoot 'agents/standard-review.md'
        $legacyText = [IO.File]::ReadAllText($legacyPath).Replace("`n<!-- skills-manager:model-orchestration:claude -->`n", '')
        [IO.File]::WriteAllText($legacyPath, $legacyText)
        $adopted = & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Apply -SubagentsOnly | ConvertFrom-Json
        $adopted.changed | Should -Be 1
        & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Rollback -ReceiptPath $adopted.receipt | Out-Null
        [IO.File]::ReadAllText($legacyPath) | Should -BeExactly $legacyText
        # Restore the first projection's exact bytes before rolling it back.
        & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Apply -SubagentsOnly | Out-Null
        & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Rollback -ReceiptPath $applied.receipt | Out-Null
        Test-Path -LiteralPath $settingsPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath (Join-Path $claudeRoot 'agents') -File).Count | Should -Be 0
    }

    It 'refuses an unowned Claude agent before writing settings or agents' {
        $scriptPath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) 'src/model-orchestration/Set-ModelPreset.ps1'
        $claudeRoot = Join-Path $TestDrive 'claude-collision'
        $agentRoot = Join-Path $claudeRoot 'agents'
        New-Item -ItemType Directory -Path $agentRoot | Out-Null
        $agentPath = Join-Path $agentRoot 'standard-review.md'
        $userText = "---`nname: standard-review`ndescription: User agent`n---`nPreserve this custom agent.`n"
        [IO.File]::WriteAllText($agentPath, $userText)
        foreach ($action in @('Plan','Apply')) {
            { & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action $action -SubagentsOnly } | Should -Throw
            [IO.File]::ReadAllText($agentPath) | Should -BeExactly $userText
            Test-Path -LiteralPath (Join-Path $claudeRoot 'settings.json') | Should -BeFalse
            @(Get-ChildItem -LiteralPath $agentRoot -File).Count | Should -Be 1
        }
    }

    It 'preserves parent settings and does not introduce a global effort override' {
        $scriptPath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) 'src/model-orchestration/Set-ModelPreset.ps1'
        $claudeRoot = Join-Path $TestDrive 'claude-parent'
        New-Item -ItemType Directory -Path $claudeRoot | Out-Null
        $settingsPath = Join-Path $claudeRoot 'settings.json'
        $original = '{"model":"parent-model","effortLevel":"medium","env":{"CUSTOM_VALUE":"preserve"}}'
        [IO.File]::WriteAllText($settingsPath, $original)
        $applied = & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Apply -SubagentsOnly | ConvertFrom-Json
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        $settings.model | Should -Be 'parent-model'
        $settings.effortLevel | Should -Be 'medium'
        $settings.env.CUSTOM_VALUE | Should -Be 'preserve'
        $settings.env.Contains('CLAUDE_CODE_EFFORT_LEVEL') | Should -BeFalse
        & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Rollback -ReceiptPath $applied.receipt | Out-Null
        [IO.File]::ReadAllText($settingsPath) | Should -BeExactly $original
        $full = & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Apply | ConvertFrom-Json
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        $settings.env.Contains('CLAUDE_CODE_EFFORT_LEVEL') | Should -BeFalse
        & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action Rollback -ReceiptPath $full.receipt | Out-Null
        [IO.File]::ReadAllText($settingsPath) | Should -BeExactly $original
    }

    It 'rejects stale, unbound and future native catalog snapshots in both entrypoints' {
        $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $snapshotPath = Join-Path $TestDrive 'catalog.json'
        $targetRoot = Join-Path $TestDrive 'target-codex'
        $now = [DateTimeOffset]::UtcNow
        foreach ($entrypoint in @('Set-ModelPreset.ps1','Start-ModelSlot.ps1')) {
            $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot "src/model-orchestration/$entrypoint"), [ref]$null, [ref]$null)
            $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-CodexCatalog' }, $true).Extent.Text
            & {
                param($functionText, $root, $path, $observedNow)
                . ([scriptblock]::Create($functionText))
                $CodexRoot = $root
                $priorRoot = $env:CODEX_HOME
                $env:CODEX_HOME = $root
                try {
                    $valid = @{
                        source = 'codex debug models'; codex_root = $root
                        observed_at = $observedNow.AddSeconds(-10).ToString('o')
                        expires_at = $observedNow.AddMinutes(3).ToString('o')
                        models = @(@{ slug='gpt-6-luna'; supported_reasoning_levels=@(@{effort='max'}) })
                    }
                    [IO.File]::WriteAllText($path, ($valid | ConvertTo-Json -Depth 8))
                    @(Get-CodexCatalog $path).models.Count | Should -Be 1
                    foreach ($invalid in @(
                        @{ source='other-source' },
                        @{ codex_root='relative-root' },
                        @{ codex_root=(Join-Path $root 'different') },
                        @{ observed_at=$observedNow.AddMinutes(-10).ToString('o'); expires_at=$observedNow.AddMinutes(-6).ToString('o') },
                        @{ observed_at=$observedNow.AddMinutes(1).ToString('o') },
                        @{ expires_at=$observedNow.AddHours(1).ToString('o') },
                        @{ observed_at='invalid-date' }
                    )) {
                        $candidate = $valid.Clone()
                        foreach ($key in $invalid.Keys) { $candidate[$key] = $invalid[$key] }
                        [IO.File]::WriteAllText($path, ($candidate | ConvertTo-Json -Depth 8))
                        { Get-CodexCatalog $path } | Should -Throw
                    }
                    [IO.File]::WriteAllText($path, (@{ models=$valid.models } | ConvertTo-Json -Depth 8))
                    { Get-CodexCatalog $path } | Should -Throw
                }
                finally {
                    if ($null -eq $priorRoot) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue }
                    else { $env:CODEX_HOME = $priorRoot }
                }
            } $definition $targetRoot $snapshotPath $now
        }
    }
}
