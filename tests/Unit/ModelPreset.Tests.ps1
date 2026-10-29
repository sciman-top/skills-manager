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

    It 'fails closed for the retired Claude host facet without writing host files' {
        $scriptPath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) 'src/model-orchestration/Set-ModelPreset.ps1'
        $claudeRoot = Join-Path $TestDrive 'claude-retired'
        foreach ($action in @('Plan','Apply')) {
            { & $scriptPath -ExecutionHost claude -ClaudeRoot $claudeRoot -Action $action -SubagentsOnly } | Should -Throw 'No active preset is available on host claude.'
            Test-Path -LiteralPath $claudeRoot | Should -BeFalse
        }
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
