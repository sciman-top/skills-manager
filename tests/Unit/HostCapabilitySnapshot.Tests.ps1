$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')

$snapshotDomainPath = Join-Path $repoRoot 'src\Domain\HostCapabilitySnapshot.ps1'
$snapshotResolutionPath = Join-Path $repoRoot 'src\Application\HostCapabilityResolution.ps1'
if (Test-Path -LiteralPath $snapshotDomainPath -PathType Leaf) { . $snapshotDomainPath }
if (Test-Path -LiteralPath $snapshotResolutionPath -PathType Leaf) { . $snapshotResolutionPath }

Describe 'HostCapabilitySnapshot contract and precedence' {
    It 'prefers a turn model override over thread and lower-precedence sources' {
        $resolver = Get-Command Resolve-HostCapabilitySnapshot -ErrorAction SilentlyContinue
        $resolver | Should Not BeNullOrEmpty
        if ($null -eq $resolver) { return }

        $capturedAt = '2026-08-07T03:00:00Z'
        $turn = [pscustomobject]@{
            model = [pscustomobject]@{ value = 'turn-model'; captured_at = $capturedAt; freshness = 'fresh' }
        }
        $thread = [pscustomobject]@{
            model = [pscustomobject]@{ value = 'thread-model'; captured_at = $capturedAt; freshness = 'fresh' }
        }
        $config = [pscustomobject]@{
            model = [pscustomobject]@{ value = 'config-model'; captured_at = $capturedAt; freshness = 'fresh' }
        }
        $catalog = [pscustomobject]@{
            model = [pscustomobject]@{ value = 'catalog-model'; captured_at = $capturedAt; freshness = 'fresh' }
        }

        $result = Resolve-HostCapabilitySnapshot -Surface 'cli' -ThreadId 'thread-1' -TurnId 'turn-1' -CapturedAt $capturedAt -TurnOverride $turn -ThreadRuntime $thread -ConfigLayered $config -ModelCatalog $catalog

        $result.capabilities.model.value | Should Be 'turn-model'
        $result.capabilities.model.source | Should Be 'turn_override'
    }

    It 'uses the thread effective model when no turn override exists' {
        $capturedAt = '2026-08-07T03:00:00Z'
        $thread = [pscustomobject]@{
            model = [pscustomobject]@{ value = 'thread-model'; captured_at = $capturedAt; freshness = 'fresh' }
        }
        $config = [pscustomobject]@{
            model = [pscustomobject]@{ value = 'config-model'; captured_at = $capturedAt; freshness = 'fresh' }
        }

        $result = Resolve-HostCapabilitySnapshot -Surface 'app_server' -ThreadId 'thread-1' -CapturedAt $capturedAt -ThreadRuntime $thread -ConfigLayered $config

        $result.capabilities.model.value | Should Be 'thread-model'
        $result.capabilities.model.source | Should Be 'thread_runtime'
    }

    It 'keeps unknown context conservative and exposes the fallback reason' {
        $capturedAt = '2026-08-07T03:00:00Z'
        $config = [pscustomobject]@{
            context_window = [pscustomobject]@{ value = 0; captured_at = $capturedAt; freshness = 'fresh' }
        }

        $result = Resolve-HostCapabilitySnapshot -Surface 'offline' -CapturedAt $capturedAt -ConfigLayered $config

        $result.capabilities.context_window.value | Should BeNullOrEmpty
        $result.capabilities.context_window.source | Should Be 'unknown_fallback'
        $result.capabilities.context_window.freshness | Should Be 'unknown'
        @($result.unknown_reasons) | Should Contain 'context_window_unknown'
        (Test-HostCapabilitySnapshotContract $result).pass | Should Be $true
    }

    It 'retains a stale higher-precedence source instead of hiding it behind config' {
        $capturedAt = '2026-08-07T03:00:00Z'
        $thread = [pscustomobject]@{
            context_window = [pscustomobject]@{ value = 128000; captured_at = '2026-07-01T03:00:00Z'; freshness = 'stale' }
        }
        $config = [pscustomobject]@{
            context_window = [pscustomobject]@{ value = 272000; captured_at = $capturedAt; freshness = 'fresh' }
        }

        $result = Resolve-HostCapabilitySnapshot -Surface 'cli' -CapturedAt $capturedAt -ThreadRuntime $thread -ConfigLayered $config

        $result.capabilities.context_window.value | Should Be 128000
        $result.capabilities.context_window.source | Should Be 'thread_runtime'
        $result.capabilities.context_window.freshness | Should Be 'stale'
    }
}
