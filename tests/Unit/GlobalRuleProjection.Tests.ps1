BeforeAll {
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Application\GlobalRuleProjection.ps1')
}

Describe 'Global rule source and projection' {
    BeforeEach {
        $fixture=Join-Path $TestDrive 'repo';$codex=Join-Path $TestDrive 'codex';$claude=Join-Path $TestDrive 'claude'
        New-Item -ItemType Directory -Path (Join-Path $fixture 'rules\global\codex'),(Join-Path $fixture 'rules\global\claude'),$codex,$claude -Force|Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules\global\codex\AGENTS.md') -Destination (Join-Path $fixture 'rules\global\codex\AGENTS.md')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules\global\claude\CLAUDE.md') -Destination (Join-Path $fixture 'rules\global\claude\CLAUDE.md')
        Set-Content -LiteralPath (Join-Path $codex 'AGENTS.md') -Value '# old codex' -Encoding utf8NoBOM -NoNewline
        Set-Content -LiteralPath (Join-Path $claude 'CLAUDE.md') -Value '# old claude' -Encoding utf8NoBOM -NoNewline
    }

    It 'validates the tracked source family and shared A/C/D sections' {
        $result=Test-GlobalRuleSourceFamily $fixture $codex $claude
        $result.pass|Should -BeTrue
        $result.facts.codex.version|Should -Be '9.75'
        $result.facts.claude.bytes|Should -BeLessThan 13926
    }

    It 'plans, applies, verifies, and rolls back through one interface' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude
        @($plan.actions|Where-Object operation -eq 'update').Count|Should -Be 2
        $receiptPath=Join-Path $TestDrive 'receipt.json';$backupRoot=Join-Path $TestDrive 'backups'
        $receipt=Invoke-GlobalRuleProjectionApply $plan $plan.apply.required_token $backupRoot $receiptPath
        $receipt.writes|Should -Be 2
        (Test-GlobalRuleProjection $fixture $codex $claude).pass|Should -BeTrue
        $rollback=Invoke-GlobalRuleProjectionRollback $receiptPath 'ROLLBACK_GLOBAL_RULES'
        $rollback.pass|Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md'))|Should -Be '# old codex'
        [IO.File]::ReadAllText((Join-Path $claude 'CLAUDE.md'))|Should -Be '# old claude'
    }

    It 'fails closed when a source changes after planning' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude
        Add-Content -LiteralPath (Join-Path $fixture 'rules\global\codex\AGENTS.md') -Value "`n# drift"
        { Invoke-GlobalRuleProjectionApply $plan $plan.apply.required_token (Join-Path $TestDrive 'backups') (Join-Path $TestDrive 'receipt.json') }|Should -Throw '*stale*'
    }

    It 'rejects drift between Codex and Claude common sections' {
        $path=Join-Path $fixture 'rules\global\claude\CLAUDE.md';$text=[IO.File]::ReadAllText($path).Replace('## A. 共性基线','## A. 漂移');[IO.File]::WriteAllText($path,$text)
        $result=Test-GlobalRuleSourceFamily $fixture $codex $claude
        $result.pass|Should -BeFalse
        @($result.findings.code)|Should -Contain 'source_common_sections_drift'
    }

    It 'rejects a drive root as a user projection root' {
        { New-GlobalRuleProjectionPlan $fixture ([IO.Path]::GetPathRoot($codex)) $claude }|Should -Throw '*Drive roots*'
    }
}
