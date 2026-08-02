$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\CapabilityDescriptor.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')
. (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
. (Join-Path $repoRoot 'src\Application\RuleDiagnostics.ps1')
. (Join-Path $repoRoot 'src\Application\RuleAdvisor.ps1')

Describe 'Phase 1 representative acceptance' {
    $fixtureRoot = Join-Path $repoRoot 'tests\fixtures\phase1-acceptance'

    It 'accepts the simple fixture without deterministic findings' {
        $root = Join-Path $fixtureRoot 'simple'
        $result = Invoke-RuleDiagnostics (Get-RuleDiscovery -RepoRoot $root -HostName codex) ([pscustomobject]@{ max_bytes = 10240; max_lines = 80; blocking_codes = @() })
        @($result.findings).Count | Should Be 0
    }

    It 'models root and subtree precedence in the nested fixture' {
        $root = Join-Path $fixtureRoot 'nested'; $cwd = Join-Path $root 'src\feature'
        $discovery = Get-RuleDiscovery -RepoRoot $root -CurrentDirectory $cwd -HostName codex

        @($discovery.documents).Count | Should Be 2
        (@($discovery.documents.scope) -join ',') | Should Be 'repo,override'
        (@($discovery.documents.precedence) -join ',') | Should Be '0,1'
        $discovery.load_verification | Should Be 'not_run'
    }

    It 'finds only the expected deterministic conflict codes in the conflict fixture' {
        $root = Join-Path $fixtureRoot 'conflict'; $cwd = Join-Path $root 'src'
        $result = Invoke-RuleDiagnostics (Get-RuleDiscovery -RepoRoot $root -CurrentDirectory $cwd -HostName codex) ([pscustomobject]@{ max_bytes = 10240; max_lines = 80; blocking_codes = @() })
        $codes = @($result.findings.code | Sort-Object -Unique)

        ($codes -join ',') | Should Be 'exact_duplicate_document,prose_only_enforcement'
        @($result.findings).Count | Should Be 4
        $result.blocking_count | Should Be 0
    }

    It 'scans three authorized repositories within performance and zero-write boundaries' {
        $targets = @(
            'D:\CODE\skills-manager',
            'D:\CODE-other\governed-ai-coding-runtime',
            'D:\CODE\external\skills-manager-references\core\codex'
        )
        foreach ($target in $targets) { Test-Path -LiteralPath $target -PathType Container | Should Be $true }
        $records = New-Object System.Collections.Generic.List[object]
        foreach ($target in $targets) {
            $rulePath = Join-Path $target 'AGENTS.md'
            $before = (Get-FileHash -LiteralPath $rulePath -Algorithm SHA256).Hash
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $discovery = Get-RuleDiscovery -RepoRoot $target -HostName codex
            $diagnostics = Invoke-RuleDiagnostics $discovery ([pscustomobject]@{ max_bytes = 262144; max_lines = 5000; blocking_codes = @('file_missing') })
            $advisor = Invoke-RuleAdvisor -Documents $diagnostics.documents
            $stopwatch.Stop()
            $after = (Get-FileHash -LiteralPath $rulePath -Algorithm SHA256).Hash

            $after | Should Be $before
            $discovery.writes | Should Be 0
            $discovery.provider_calls | Should Be 0
            $discovery.native_mutations | Should Be 0
            $discovery.profile_changed | Should Be $false
            $diagnostics.commands_executed | Should Be 0
            $advisor.provider_calls | Should Be 0
            $stopwatch.ElapsedMilliseconds | Should BeLessThan 5000
            $records.Add([pscustomobject]@{ target = $target; documents = @($discovery.documents).Count; findings = @($diagnostics.findings).Count + @($advisor.findings).Count; elapsed_ms = $stopwatch.ElapsedMilliseconds }) | Out-Null
        }
        $records.Count | Should Be 3
    }
}
