$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\CapabilityDescriptor.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
. (Join-Path $repoRoot 'src\Application\RuleDiagnostics.ps1')

Describe 'Deterministic rule diagnostics' {
    function New-TestDocument([string]$Path, [string]$Scope = 'repo') {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $sha = [System.Security.Cryptography.SHA256]::Create(); try { $hash = (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
        return New-RuleDocument -Host codex -Scope $Scope -Responsibility $(if ($Scope -eq 'global') { 'common' } else { 'project_action' }) -Path $Path -Owner repo -ContentHash $hash -ByteSize $bytes.Length -DiscoveryState observed -SourceOfTruth fixture
    }

    It 'emits stable budget and wrapper findings without executing commands' {
        $path = Join-Path $TestDrive 'CLAUDE.md'; Set-Content -LiteralPath $path -Value "wrong`nline2`nline3" -Encoding UTF8
        $document = New-TestDocument $path
        $discovery = [pscustomobject]@{ documents = @($document) }
        $profile = [pscustomobject]@{ max_bytes = 1; max_lines = 1; wrapper_first_line = '@AGENTS.md'; blocking_codes = @('wrapper_first_line_mismatch') }
        $first = Invoke-RuleDiagnostics $discovery $profile
        $second = Invoke-RuleDiagnostics $discovery $profile

        @($first.findings.code) | Should Contain 'byte_budget_exceeded'
        @($first.findings.code) | Should Contain 'line_budget_exceeded'
        @($first.findings.code) | Should Contain 'wrapper_first_line_mismatch'
        (@($first.findings.finding_id) -join ',') | Should Be (@($second.findings.finding_id) -join ',')
        $first.blocking_count | Should Be 1
        $first.commands_executed | Should Be 0
    }

    It 'detects exact duplicate documents and scope leakage' {
        $a = Join-Path $TestDrive 'a.md'; $b = Join-Path $TestDrive 'b.md'; $text = 'Use D:\CODE\repo\build.ps1'; Set-Content $a $text -Encoding UTF8; Set-Content $b $text -Encoding UTF8
        $discovery = [pscustomobject]@{ documents = @((New-TestDocument $a global), (New-TestDocument $b global)) }
        $result = Invoke-RuleDiagnostics $discovery ([pscustomobject]@{ max_bytes = 1000; max_lines = 100; blocking_codes = @() })

        @($result.findings | Where-Object code -eq exact_duplicate_document).Count | Should Be 2
        @($result.findings | Where-Object code -eq global_repo_private_path).Count | Should Be 2
    }

    It 'detects prose-only deterministic enforcement claims' {
        $path = Join-Path $TestDrive 'enforcement.md'; Set-Content $path '[deterministic-enforcement] must block' -Encoding UTF8
        $result = Invoke-RuleDiagnostics ([pscustomobject]@{ documents = @((New-TestDocument $path)) }) ([pscustomobject]@{ blocking_codes = @('prose_only_enforcement') })

        @($result.findings | Where-Object code -eq prose_only_enforcement).Count | Should Be 1
        $result.blocking_count | Should Be 1
    }

    It 'applies separate global and project budgets in one discovery chain' {
        $globalPath = Join-Path $TestDrive 'global-budget.md'; $projectPath = Join-Path $TestDrive 'project-budget.md'
        Set-Content $globalPath ((('g' * 20) + "`n") * 2) -Encoding UTF8
        Set-Content $projectPath ((('p' * 20) + "`n") * 2) -Encoding UTF8
        $discovery = [pscustomobject]@{ documents = @((New-TestDocument $globalPath global), (New-TestDocument $projectPath repo)) }
        $profile = [pscustomobject]@{ max_bytes = 1000; max_lines = 100; global_max_bytes = 1000; global_max_lines = 10; project_max_bytes = 10; project_max_lines = 1; blocking_codes = @() }

        $result = Invoke-RuleDiagnostics $discovery $profile

        @($result.findings | Where-Object path -eq $globalPath).Count | Should Be 0
        @($result.findings | Where-Object path -eq $projectPath).Count | Should Be 2
    }
}
