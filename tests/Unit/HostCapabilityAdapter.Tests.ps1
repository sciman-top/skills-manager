$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\HostCapabilitySnapshot.ps1')
. (Join-Path $repoRoot 'src\Application\HostCapabilityResolution.ps1')

$adapterPath = Join-Path $repoRoot 'src\Infrastructure\HostCapabilityAdapters.ps1'
if (Test-Path -LiteralPath $adapterPath -PathType Leaf) { . $adapterPath }
$snapshotScriptPath = Join-Path $repoRoot 'scripts\get-codex-app-server-capability-snapshot.ps1'

Describe 'Host capability adapters' {
    It 'maps a complete App Server response into the frozen snapshot schema' {
        $adapter = Get-Command New-HostCapabilitySnapshotFromAppServer -ErrorAction SilentlyContinue
        $adapter | Should Not BeNullOrEmpty
        if ($null -eq $adapter) { return }

        $capturedAt = '2026-08-07T04:00:00Z'
        $responses = [pscustomobject]@{
            config_read = [pscustomobject]@{
                model = 'gpt-5.6'
                context_window = 128000
            }
            model_list = [pscustomobject]@{
                data = @([pscustomobject]@{ id = 'gpt-5.6'; context_window = 128000 })
            }
            model_provider_capabilities_read = [pscustomobject]@{
                metadata_budget = 4096
            }
            skills_list = [pscustomobject]@{
                data = @(
                    [pscustomobject]@{ name = 'test-driven-development'; description = 'Use when implementing a feature.'; enabled = $true }
                    [pscustomobject]@{ name = 'verification-before-completion'; description = 'Verify before claiming completion.'; enabled = $true }
                )
            }
        }

        $snapshot = New-HostCapabilitySnapshotFromAppServer -Responses $responses -Surface 'app_server' -CapturedAt $capturedAt

        $snapshot.schema_version | Should Be 1
        $snapshot.source | Should Be 'app_server'
        $snapshot.status | Should Be 'complete'
        $snapshot.capabilities.model.value | Should Be 'gpt-5.6'
        $snapshot.capabilities.context_window.value | Should Be 128000
        $snapshot.capabilities.metadata_budget.value | Should Be 4096
        @($snapshot.capabilities.skills_inventory.value).Count | Should Be 2
        $snapshot.provider_calls | Should Be 0
        $snapshot.writes | Should Be 0
        (Test-HostCapabilitySnapshotContract $snapshot).pass | Should Be $true
    }

    It 'keeps missing App Server methods partial and leaves unknown facts unpromoted' {
        $capturedAt = '2026-08-07T04:00:00Z'
        $responses = [pscustomobject]@{
            skills_list = [pscustomobject]@{
                data = @([pscustomobject]@{ name = 'verification-before-completion'; description = 'Verify before claiming completion.'; enabled = $true })
            }
        }

        $snapshot = New-HostCapabilitySnapshotFromAppServer -Responses $responses -Surface 'app_server' -CapturedAt $capturedAt

        $snapshot.status | Should Be 'partial'
        $snapshot.capabilities.model.value | Should BeNullOrEmpty
        $snapshot.capabilities.model.source | Should Be 'unknown_fallback'
        $snapshot.capabilities.model.freshness | Should Be 'unknown'
        $snapshot.capabilities.context_window.value | Should BeNullOrEmpty
        $snapshot.capabilities.context_window.source | Should Be 'unknown_fallback'
        $snapshot.capabilities.context_window.freshness | Should Be 'unknown'
        @($snapshot.capabilities.skills_inventory.value).Count | Should Be 1
        @($snapshot.unknown_reasons) | Should Contain 'thread_runtime:app_server_model_unknown'
        @($snapshot.unknown_reasons) | Should Contain 'thread_runtime:app_server_context_window_unknown'
        (Test-HostCapabilitySnapshotContract $snapshot).pass | Should Be $true
    }

    It 'does not infer an effective model from catalog ordering' {
        $responses = [pscustomobject]@{
            config_read = [pscustomobject]@{}
            model_list = [pscustomobject]@{
                data = @([pscustomobject]@{ id = 'catalog-first'; context_window = 111000 }, [pscustomobject]@{ id = 'catalog-second'; context_window = 222000 })
            }
        }

        $snapshot = New-HostCapabilitySnapshotFromAppServer -Responses $responses -Surface 'app_server' -CapturedAt '2026-08-07T04:00:00Z'

        $snapshot.capabilities.model.value | Should BeNullOrEmpty
        $snapshot.capabilities.context_window.value | Should BeNullOrEmpty
        (Test-HostCapabilitySnapshotContract $snapshot).pass | Should Be $true
    }

    It 'uses the model-matching catalog row when config omits only context window' {
        $responses = [pscustomobject]@{
            config_read = [pscustomobject]@{ model = 'catalog-second' }
            model_list = [pscustomobject]@{
                data = @([pscustomobject]@{ id = 'catalog-first'; context_window = 111000 }, [pscustomobject]@{ id = 'catalog-second'; context_window = 222000 })
            }
        }

        $snapshot = New-HostCapabilitySnapshotFromAppServer -Responses $responses -Surface 'app_server' -CapturedAt '2026-08-07T04:00:00Z'

        $snapshot.capabilities.model.value | Should Be 'catalog-second'
        $snapshot.capabilities.context_window.value | Should Be 222000
        (Test-HostCapabilitySnapshotContract $snapshot).pass | Should Be $true
    }

    It 'flattens the Codex 0.146 skills list response by cwd' {
        $responses = [pscustomobject]@{
            skills_list = [pscustomobject]@{
                result = [pscustomobject]@{
                    data = @([pscustomobject]@{
                        cwd = 'D:\repo'
                        errors = @()
                        skills = @(
                            [pscustomobject]@{ name = 'grill-with-docs'; description = 'Challenge a design.'; enabled = $true; scope = 'user'; path = 'D:\skills\grill-with-docs\SKILL.md' }
                            [pscustomobject]@{ name = 'verification-before-completion'; description = 'Verify before claiming completion.'; enabled = $true; scope = 'user'; path = 'D:\skills\verification-before-completion\SKILL.md' }
                        )
                    })
                }
            }
        }

        $snapshot = New-HostCapabilitySnapshotFromAppServer -Responses $responses -Surface 'app_server' -CapturedAt '2026-08-08T10:00:00Z'

        @($snapshot.capabilities.skills_inventory.value).Count | Should Be 2
        @($snapshot.capabilities.skills_inventory.value.name) | Should Contain 'grill-with-docs'
        $snapshot.coverage.skills_list | Should Be $true
        $snapshot.capabilities.skills_inventory.freshness | Should Be 'fresh'
    }

    It 'marks an unavailable CLI as platform_na without promoting unknown facts' {
        $adapter = Get-Command New-HostCapabilitySnapshotFromCli -ErrorAction SilentlyContinue
        $adapter | Should Not BeNullOrEmpty
        if ($null -eq $adapter) { return }

        $snapshot = New-HostCapabilitySnapshotFromCli -PromptInput $null -CapturedAt '2026-08-07T04:00:00Z' -ExecutableAvailable $false

        $snapshot.adapter | Should Be 'cli'
        $snapshot.source | Should Be 'cli'
        $snapshot.status | Should Be 'platform_na'
        $snapshot.platform_na | Should Be $true
        $snapshot.capabilities.model.value | Should BeNullOrEmpty
        $snapshot.capabilities.model.source | Should Be 'unknown_fallback'
        @($snapshot.unknown_reasons) | Should Contain 'cli_unavailable_platform_na'
        $snapshot.provider_calls | Should Be 0
        $snapshot.writes | Should Be 0
        (Test-HostCapabilitySnapshotContract $snapshot).pass | Should Be $true
    }

    It 'maps fresh debug prompt-input skill metadata without inventing unavailable runtime facts' {
        $promptInput = @(
            [pscustomobject]@{
                type = 'message'
                role = 'developer'
                content = @([pscustomobject]@{
                    type = 'input_text'
                    text = "<skills_instructions>`n### Available skills`n- test-driven-development: Use when implementing a feature.`n- verification-before-completion: Verify before claiming completion.`n### End skills"
                })
            }
        )

        $snapshot = New-HostCapabilitySnapshotFromCli -PromptInput $promptInput -CapturedAt '2026-08-07T04:00:00Z' -ExecutableAvailable $true

        $snapshot.status | Should Be 'partial'
        @($snapshot.capabilities.skills_inventory.value).Count | Should Be 2
        @($snapshot.capabilities.skills_inventory.value | ForEach-Object name) | Should Contain 'test-driven-development'
        $snapshot.capabilities.model.value | Should BeNullOrEmpty
        $snapshot.capabilities.model.source | Should Be 'unknown_fallback'
        $snapshot.provider_calls | Should Be 0
        $snapshot.writes | Should Be 0
        (Test-HostCapabilitySnapshotContract $snapshot).pass | Should Be $true
    }

    It 'labels offline config as config_fallback and redacts secrets without runtime promotion' {
        $configText = @'
model = "gpt-5.6"
model_context_window = 272000
api_key = "offline-secret-key"
[provider]
api_key = "provider-secret-key"
'@

        $snapshot = New-HostCapabilitySnapshotFromConfigFallback -ConfigText $configText -CapturedAt '2026-08-07T04:00:00Z'
        $serialized = $snapshot | ConvertTo-Json -Depth 30 -Compress

        $snapshot.adapter | Should Be 'offline_config'
        $snapshot.source | Should Be 'config_fallback'
        $snapshot.status | Should Be 'partial'
        $snapshot.capabilities.model.value | Should Be 'gpt-5.6'
        $snapshot.capabilities.model.source | Should Be 'config_layered'
        $snapshot.capabilities.context_window.value | Should Be 272000
        $snapshot.capabilities.context_window.source | Should Be 'config_layered'
        $snapshot.capabilities.context_window.freshness | Should Be 'fresh'
        $snapshot.capabilities.metadata_budget.source | Should Be 'unknown_fallback'
        $serialized | Should Not Match 'offline-secret-key|provider-secret-key'
        $serialized | Should Match '<redacted>'
        $snapshot.provider_calls | Should Be 0
        $snapshot.writes | Should Be 0
        (Test-HostCapabilitySnapshotContract $snapshot).pass | Should Be $true
    }

    It 'validates the shared adapter envelope and rejects side-effect counters' {
        $valid = New-HostCapabilitySnapshotFromConfigFallback -ConfigText 'model = "gpt-5.6"' -CapturedAt '2026-08-07T04:00:00Z'
        $validResult = Test-HostCapabilityAdapterContract $valid

        $validResult.pass | Should Be $true
        $validResult.findings.Count | Should Be 0

        $invalid = $valid | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $invalid.writes = 1
        $invalidResult = Test-HostCapabilityAdapterContract $invalid

        $invalidResult.pass | Should Be $false
        @($invalidResult.findings | Where-Object code -eq 'adapter_writes_forbidden').Count | Should Be 1
    }

    It 'keeps an App Server RPC error partial and redacts its diagnostic text' {
        $responses = [pscustomobject]@{
            config_read = [pscustomobject]@{ model = 'gpt-5.6'; context_window = 128000 }
            model_list = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Authorization: Bearer rpc-secret-token' } }
            model_provider_capabilities_read = [pscustomobject]@{ metadata_budget = 4096 }
            skills_list = [pscustomobject]@{ data = @([pscustomobject]@{ name = 'verification-before-completion'; description = 'Verify.'; enabled = $true }) }
        }

        $snapshot = New-HostCapabilitySnapshotFromAppServer -Responses $responses -Surface 'app_server' -CapturedAt '2026-08-07T04:00:00Z'
        $serialized = $snapshot | ConvertTo-Json -Depth 30 -Compress

        $snapshot.status | Should Be 'partial'
        @($snapshot.errors).Count | Should Be 1
        $snapshot.errors[0].message | Should Match '<redacted>'
        $snapshot.coverage.model_list | Should Be $false
        $snapshot.capabilities.model.freshness | Should Be 'fresh'
        $serialized | Should Not Match 'rpc-secret-token'
        (Test-HostCapabilityAdapterContract $snapshot).pass | Should Be $true
    }

    It 'emits the shared schema from the offline script mode and only writes an explicit report' {
        $configPath = Join-Path $TestDrive 'config.toml'
        $outputPath = Join-Path $TestDrive 'snapshot.json'
        @'
model = "gpt-5.6"
model_context_window = 128000
api_key = "script-secret"
'@ | Set-Content -LiteralPath $configPath -Encoding utf8

        $raw = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $snapshotScriptPath -Mode offline -ConfigPath $configPath -CapturedAt '2026-08-07T04:00:00Z' -OutputPath $outputPath 2>&1)
        $exitCode = $LASTEXITCODE
        $snapshot = (($raw -join "`n") | ConvertFrom-Json)
        $written = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json

        $exitCode | Should Be 0
        $snapshot.source | Should Be 'config_fallback'
        $snapshot.schema_version | Should Be 1
        $snapshot.writes | Should Be 0
        $snapshot.provider_calls | Should Be 0
        $written.snapshot_id | Should Be $snapshot.snapshot_id
        $snapshot | ConvertTo-Json -Depth 30 -Compress | Should Not Match 'script-secret'
        (Test-HostCapabilityAdapterContract $snapshot).pass | Should Be $true
    }
}
