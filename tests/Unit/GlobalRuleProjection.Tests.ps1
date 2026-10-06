BeforeAll {
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Root=$repoRoot
    . (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Application\GlobalRuleProjection.ps1')
    . (Join-Path $repoRoot 'src\Commands\GlobalRules.ps1')
    $script:globalRuleOriginalWriteBytes = ${function:Write-BytesAtomic}

    function Copy-GlobalRuleFixture([string]$Fixture,[string]$Codex,[string]$Claude,[string]$ZCode = '', [string]$Antigravity = '', [string]$WorkBuddy = '') {
        $dirs = @((Join-Path $Fixture 'rules\global\codex'),(Join-Path $Fixture 'rules\global\claude'),(Join-Path $Fixture 'rules\global\zcode'),(Join-Path $Fixture 'rules\global\antigravity'),$Codex,$Claude,(Join-Path $Fixture 'reports\global-rule-projection'))
        if (-not [string]::IsNullOrWhiteSpace($ZCode)) { $dirs += $ZCode }
        if (-not [string]::IsNullOrWhiteSpace($Antigravity)) { $dirs += $Antigravity }
        New-Item -ItemType Directory -Path $dirs -Force|Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Fixture 'rules/global/platforms'), (Join-Path $Fixture 'rules/global/workbuddy') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules/global/common.md') -Destination (Join-Path $Fixture 'rules/global/common.md')
        foreach ($hostName in @('codex','claude','zcode','antigravity','workbuddy')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot "rules/global/platforms/$hostName.md") -Destination (Join-Path $Fixture "rules/global/platforms/$hostName.md")
        }
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules/global/workbuddy/CODEBUDDY.md') -Destination (Join-Path $Fixture 'rules/global/workbuddy/CODEBUDDY.md')
        if (-not [string]::IsNullOrWhiteSpace($WorkBuddy)) { New-Item -ItemType Directory -Path $WorkBuddy -Force | Out-Null }
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules\global\codex\AGENTS.md') -Destination (Join-Path $Fixture 'rules\global\codex\AGENTS.md')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules\global\claude\CLAUDE.md') -Destination (Join-Path $Fixture 'rules\global\claude\CLAUDE.md')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules\global\zcode\AGENTS.md') -Destination (Join-Path $Fixture 'rules\global\zcode\AGENTS.md')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules\global\antigravity\GEMINI.md') -Destination (Join-Path $Fixture 'rules\global\antigravity\GEMINI.md')
        Set-Content -LiteralPath (Join-Path $Codex 'AGENTS.md') -Value '# old codex' -Encoding utf8NoBOM -NoNewline
        Set-Content -LiteralPath (Join-Path $Claude 'CLAUDE.md') -Value '# old claude' -Encoding utf8NoBOM -NoNewline
        if (-not [string]::IsNullOrWhiteSpace($ZCode)) { Set-Content -LiteralPath (Join-Path $ZCode 'AGENTS.md') -Value '# old zcode' -Encoding utf8NoBOM -NoNewline }
        if (-not [string]::IsNullOrWhiteSpace($Antigravity)) { Set-Content -LiteralPath (Join-Path $Antigravity 'GEMINI.md') -Value '# old antigravity' -Encoding utf8NoBOM -NoNewline }
    }

    # Restore the fixture in place instead of deleting and rebuilding its tree.
    # The directory layout is identical for every test and only file contents
    # differ, so re-copying the sources restores the fixture exactly. A recursive
    # delete is what used to dominate this file: in a sandboxed host deletion is
    # charged per directory node, and deleting these ten directories costs about
    # 8-15s per test, i.e. most of the suite's wall clock (see
    # docs/runbooks/agent-sandbox-instrumentation.md). Re-copying is ~0.1s.
    # Control files (receipts, backups) are cleared explicitly so a test that
    # asserts the absence of a receipt still starts clean. Only files are removed
    # -- removing the directories themselves is the expensive operation this
    # function exists to avoid, and the host's Remove-Item wrapper does not accept
    # pipeline input, so each path is passed explicitly.
    function Reset-GlobalRuleFixture([string]$Fixture,[string]$Codex,[string]$Claude) {
        Copy-GlobalRuleFixture $Fixture $Codex $Claude
        $control = Join-Path $Fixture 'reports\global-rule-projection'
        if (Test-Path -LiteralPath $control) {
            foreach ($file in @(Get-ChildItem -LiteralPath $control -File -Recurse -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    function Invoke-TestApply($Plan,[string]$Fixture,[string]$Codex,[string]$Claude,[string]$Receipt,[switch]$Resume,[string]$ZCode = '', [string]$Antigravity = '', [string]$WorkBuddy = '') {
        $backupRoot=Join-Path $Fixture 'reports\global-rule-projection\backups'
        return Invoke-GlobalRuleProjectionApply -Plan $Plan -Token $Plan.apply.required_token -BackupRoot $backupRoot -ReceiptPath $Receipt -RepoRoot $Fixture -CodexUserRoot $Codex -ClaudeUserRoot $Claude -Resume:$Resume -ZCodeUserRoot $ZCode -AntigravityUserRoot $Antigravity -WorkBuddyUserRoot $WorkBuddy
    }
}

Describe 'Global rule source contract' {
    BeforeEach {
        $fixture=Join-Path $TestDrive 'repo';$codex=Join-Path $TestDrive 'codex';$claude=Join-Path $TestDrive 'claude'
        Reset-GlobalRuleFixture $fixture $codex $claude
    }

    It 'renders all five hosts deterministically without writing in check mode' {
        @(Get-GlobalRuleRenderedEntries $fixture).Count | Should -Be 5
        $path = Join-Path $fixture 'rules/global/workbuddy/CODEBUDDY.md'
        $before = (Get-FileHash -LiteralPath $path).Hash
        Sync-GlobalRuleGeneratedFiles $fixture -Check
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
    }

    It 'rejects common source drift before target writes' {
        $plan = New-GlobalRuleProjectionPlan $fixture $codex $claude
        $path = Join-Path $fixture 'rules/global/common.md'
        [IO.File]::AppendAllText($path, "`nchanged")
        { Sync-GlobalRuleGeneratedFiles $fixture -Check } | Should -Throw '*generated_global_rule_drift*'
        @((Test-GlobalRuleSourceFamily $fixture $codex $claude).findings.code) | Should -Contain 'source_generation_drift'
        { Invoke-TestApply $plan $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/drift.json') } | Should -Throw
        [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md')) | Should -Be '# old codex'
    }

    It 'rejects a common source whose heading version differs from its metadata version: <case>' -TestCases @(
        @{ case = 'stale heading'; heading = '# AGENTS.md - Universal Agent Protocol v0.1 | OpenAI ChatGPT Work / Codex App / Codex CLI' },
        @{ case = 'missing heading version'; heading = '# AGENTS.md - Universal Agent Protocol | OpenAI ChatGPT Work / Codex App / Codex CLI' }
    ) {
        param($case, $heading)
        $path = Join-Path $fixture 'rules/global/common.md'
        $text = [regex]::Replace([IO.File]::ReadAllText($path), '\A[^\n]*', $heading)
        [IO.File]::WriteAllText($path, $text)
        { Get-GlobalRuleRenderedEntries $fixture } | Should -Throw '*heading version must match the metadata version*'
        { Sync-GlobalRuleGeneratedFiles $fixture } | Should -Throw
        { New-GlobalRuleProjectionPlan $fixture $codex $claude } | Should -Throw
    }

    It 'keeps the shipped common source heading and metadata versions in sync' {
        $text = [IO.File]::ReadAllText((Join-Path $repoRoot 'rules/global/common.md'))
        $metadata = [regex]::Match($text, '(?m)^\*\*版本\*\*:\s*([0-9][0-9A-Za-z_.-]*)\s*$')
        $heading = [regex]::Match($text, '\A#[^\r\n]*\bv([0-9][0-9A-Za-z_.-]*)\b')
        $metadata.Success | Should -BeTrue
        $heading.Success | Should -BeTrue
        $heading.Groups[1].Value | Should -BeExactly $metadata.Groups[1].Value
    }

    It 'rejects a malformed fragment without replacing generated files' {
        $output = Join-Path $fixture 'rules/global/codex/AGENTS.md'
        $before = (Get-FileHash -LiteralPath $output).Hash
        [IO.File]::WriteAllText((Join-Path $fixture 'rules/global/platforms/workbuddy.md'), 'invalid')
        { Sync-GlobalRuleGeneratedFiles $fixture } | Should -Throw
        (Get-FileHash -LiteralPath $output).Hash | Should -Be $before
    }

    It 'creates and rolls back an explicitly configured WorkBuddy rule' {
        $workbuddy = Join-Path $TestDrive 'workbuddy'
        New-Item -ItemType Directory -Path $workbuddy -Force | Out-Null
        $target = Join-Path $workbuddy 'CODEBUDDY.md'
        $plan = New-GlobalRuleProjectionPlan $fixture $codex $claude -WorkBuddyUserRoot $workbuddy
        @($plan.actions).Count | Should -Be 3
        $receiptPath = Join-Path $fixture 'reports/global-rule-projection/workbuddy.json'
        $receipt = Invoke-TestApply $plan $fixture $codex $claude $receiptPath -WorkBuddy $workbuddy
        $receipt.status | Should -Be 'applied'
        (Get-FileHash -LiteralPath $target).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $fixture 'rules/global/workbuddy/CODEBUDDY.md')).Hash
        $otherRoot = Join-Path $TestDrive 'other-workbuddy'
        New-Item -ItemType Directory -Path $otherRoot -Force | Out-Null
        { Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups') -WorkBuddyUserRoot $otherRoot } | Should -Throw
        $rollback = Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups') -WorkBuddyUserRoot $workbuddy
        $rollback.status | Should -Be 'rolled_back'
        Test-Path -LiteralPath $target | Should -BeFalse
    }

    It 'requires the 1 section' {
        $path=Join-Path $fixture 'rules\global\codex\AGENTS.md';$text=[IO.File]::ReadAllText($path).Replace('## 1. 阅读指引','## 阅读指引');[IO.File]::WriteAllText($path,$text)
        @((Test-GlobalRuleSourceFamily $fixture $codex $claude).findings.code)|Should -Contain 'source_structure_invalid'
    }

    It 'requires the D section' {
        $path=Join-Path $fixture 'rules\global\claude\CLAUDE.md';$text=[IO.File]::ReadAllText($path).Replace('## D. 维护校验清单','## 维护校验清单');[IO.File]::WriteAllText($path,$text)
        @((Test-GlobalRuleSourceFamily $fixture $codex $claude).findings.code)|Should -Contain 'source_structure_invalid'
    }

    It 'rejects identical platform sections' {
        $codexText=[IO.File]::ReadAllText((Join-Path $fixture 'rules\global\codex\AGENTS.md'))
        $codexB=[regex]::Match($codexText,'(?s)## B\..*?(?=## C\.)').Value
        $path=Join-Path $fixture 'rules\global\claude\CLAUDE.md';$text=[regex]::Replace([IO.File]::ReadAllText($path),'(?s)## B\..*?(?=## C\.)',$codexB);[IO.File]::WriteAllText($path,$text)
        @((Test-GlobalRuleSourceFamily $fixture $codex $claude).findings.code)|Should -Contain 'source_platform_sections_identical'
    }

    It 'rejects an empty platform section' {
        $path=Join-Path $fixture 'rules\global\claude\CLAUDE.md';$text=[regex]::Replace([IO.File]::ReadAllText($path),'(?s)## B\..*?(?=## C\.)',"## B. Claude 平台差异`n`n");[IO.File]::WriteAllText($path,$text)
        @((Test-GlobalRuleSourceFamily $fixture $codex $claude).findings.code)|Should -Contain 'source_platform_section_empty'
    }

    It 'rejects drift between common sections' {
        $path=Join-Path $fixture 'rules\global\claude\CLAUDE.md';$text=[IO.File]::ReadAllText($path).Replace('### A.1 三层职责','### A.1 漂移');[IO.File]::WriteAllText($path,$text)
        @((Test-GlobalRuleSourceFamily $fixture $codex $claude).findings.code)|Should -Contain 'source_common_sections_drift'
    }

    It 'rejects a ZCode global-rule version that differs from the shared release' {
        $path=Join-Path $fixture 'rules\global\zcode\AGENTS.md';$text=[regex]::Replace([IO.File]::ReadAllText($path),'(?m)^\*\*版本\*\*:.*$', '**版本**: 99.0');[IO.File]::WriteAllText($path,$text)
        @((Test-GlobalRuleSourceFamily $fixture $codex $claude).findings.code)|Should -Contain 'source_version_mismatch'
    }

    It 'rejects ZCode platform sections copied from another host' -TestCases @(
        @{ HostSource = 'codex/AGENTS.md' }, @{ HostSource = 'claude/CLAUDE.md' }
    ) {
        param($HostSource)
        $source = [IO.File]::ReadAllText((Join-Path $fixture "rules/global/$HostSource"))
        $platform = [regex]::Match($source, '(?s)## B\..*?(?=## C\.)').Value
        $path = Join-Path $fixture 'rules/global/zcode/AGENTS.md'
        [IO.File]::WriteAllText($path, [regex]::Replace([IO.File]::ReadAllText($path), '(?s)## B\..*?(?=## C\.)', $platform))
        @((Test-GlobalRuleSourceFamily $fixture $codex $claude).findings.code) | Should -Contain 'source_platform_sections_identical'
    }

    It 'rejects ZCode common-section drift even without a configured ZCode target' -TestCases @(
        @{ Heading = '### A.1 三层职责' },
        @{ Heading = '### C.1 边界与版本' },
        @{ Heading = '## D. 维护校验清单' }
    ) {
        param($Heading)
        $path = Join-Path $fixture 'rules\global\zcode\AGENTS.md'
        [IO.File]::WriteAllText($path, ([IO.File]::ReadAllText($path).Replace($Heading, "$Heading drift")))
        $result = Test-GlobalRuleSourceFamily $fixture $codex $claude
        $result.pass | Should -BeFalse
        @($result.findings.code) | Should -Contain 'source_common_sections_drift'
        { New-GlobalRuleProjectionPlan $fixture $codex $claude } | Should -Throw
        [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md')) | Should -Be '# old codex'
    }

    It 'rejects a drive root as a user projection root' {
        {New-GlobalRuleProjectionPlan $fixture ([IO.Path]::GetPathRoot($codex)) $claude}|Should -Throw '*Drive roots*'
    }

    It 'adds ZCode as a plan-bound action only when its user root is present' {
        $zcode=Join-Path $TestDrive 'zcode';Copy-GlobalRuleFixture $fixture $codex $claude $zcode
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude $zcode

        @($plan.actions.id | Sort-Object) | Should -Be @('claude','codex','zcode')
        $receiptPath=Join-Path $fixture 'reports\global-rule-projection\zcode-receipt.json'
        $receipt=Invoke-TestApply $plan $fixture $codex $claude $receiptPath -ZCode $zcode
        $receipt.writes | Should -Be 3
        [IO.File]::ReadAllText((Join-Path $zcode 'AGENTS.md')) | Should -Match 'ZCode 平台差异'
        (Invoke-GlobalRuleProjectionRollback -ReceiptPath $receiptPath -Token $receipt.rollback.required_token -RepoRoot $fixture -CodexUserRoot $codex -ClaudeUserRoot $claude -BackupRoot (Join-Path $fixture 'reports\global-rule-projection\backups') -ZCodeUserRoot $zcode).pass | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $zcode 'AGENTS.md')) | Should -Be '# old zcode'
    }

    It 'adds Antigravity as a plan-bound action only when its user root is explicitly present' {
        $antigravity=Join-Path $TestDrive 'antigravity';Copy-GlobalRuleFixture $fixture $codex $claude '' $antigravity
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude '' $antigravity

        @($plan.actions.id | Sort-Object) | Should -Be @('antigravity','claude','codex')
        $receiptPath=Join-Path $fixture 'reports\global-rule-projection\antigravity-receipt.json'
        $receipt=Invoke-TestApply $plan $fixture $codex $claude $receiptPath -Antigravity $antigravity
        $receipt.writes | Should -Be 3
        [IO.File]::ReadAllText((Join-Path $antigravity 'GEMINI.md')) | Should -Match 'Antigravity 平台差异'
        (Invoke-GlobalRuleProjectionRollback -ReceiptPath $receiptPath -Token $receipt.rollback.required_token -RepoRoot $fixture -CodexUserRoot $codex -ClaudeUserRoot $claude -BackupRoot (Join-Path $fixture 'reports\global-rule-projection\backups') -AntigravityUserRoot $antigravity).pass | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $antigravity 'GEMINI.md')) | Should -Be '# old antigravity'
    }
}

Describe 'Global rule schema v2 apply and rollback' {
    BeforeEach {
        $fixture=Join-Path $TestDrive 'repo';$codex=Join-Path $TestDrive 'codex';$claude=Join-Path $TestDrive 'claude';$receiptPath=Join-Path $fixture 'reports\global-rule-projection\receipt.json'
        Reset-GlobalRuleFixture $fixture $codex $claude
    }

    It 'plans, applies, verifies, and rolls back with operation-specific tokens' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude
        $plan.schema_version|Should -Be 2
        $receipt=Invoke-TestApply $plan $fixture $codex $claude $receiptPath
        $receipt.status|Should -Be 'applied';$receipt.writes|Should -Be 2
        $receipt.rollback.required_token|Should -Match '^ROLLBACK_GLOBAL_RULES_[A-F0-9]{16}$'
        (Test-GlobalRuleProjection $fixture $codex $claude).pass|Should -BeTrue
        $rollback=Invoke-GlobalRuleProjectionRollback -ReceiptPath $receiptPath -Token $receipt.rollback.required_token -RepoRoot $fixture -CodexUserRoot $codex -ClaudeUserRoot $claude -BackupRoot (Join-Path $fixture 'reports\global-rule-projection\backups')
        $rollback.pass|Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md'))|Should -Be '# old codex'
        [IO.File]::ReadAllText((Join-Path $claude 'CLAUDE.md'))|Should -Be '# old claude'
    }

    It 'rolls back after source <Change> without weakening apply freshness' -TestCases @(
        @{ Change = 'changed' }, @{ Change = 'removed' }
    ) {
        param($Change)
        $plan = New-GlobalRuleProjectionPlan $fixture $codex $claude
        $receipt = Invoke-TestApply $plan $fixture $codex $claude $receiptPath
        $source = Join-Path $fixture 'rules/global/codex/AGENTS.md'
        if ($Change -eq 'changed') { Add-Content -LiteralPath $source -Value 'later revision' }
        else { Remove-Item -LiteralPath $source }
        { Invoke-TestApply $plan $fixture $codex $claude $receiptPath -Resume } | Should -Throw '*source_hash_stale*'
        $result = Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups')
        $result.pass | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md')) | Should -Be '# old codex'
        [IO.File]::ReadAllText((Join-Path $claude 'CLAUDE.md')) | Should -Be '# old claude'
    }

    It 'rolls back partial apply with the second action <Stage> and operation <Operation>' -TestCases @(
        @{ Stage='pending'; Operation='update' },
        @{ Stage='prepared'; Operation='update' },
        @{ Stage='landed'; Operation='update' },
        @{ Stage='prepared'; Operation='create' },
        @{ Stage='landed'; Operation='create' }
    ) {
        param($Stage,$Operation)
        $target = Join-Path $claude 'CLAUDE.md'
        if ($Operation -eq 'create') { Remove-Item -LiteralPath $target }
        $plan = New-GlobalRuleProjectionPlan $fixture $codex $claude
        $script:globalRuleFaultEnabled = $true
        $script:globalRuleFaultTarget = $target
        $script:globalRuleFaultStage = $Stage
        Mock Write-BytesAtomic {
            param($Path,$Bytes)
            if ($script:globalRuleFaultEnabled -and (($script:globalRuleFaultStage -eq 'pending' -and $Path -like '*claude.bak') -or ($script:globalRuleFaultStage -ne 'pending' -and $Path -eq $script:globalRuleFaultTarget))) {
                if ($script:globalRuleFaultStage -eq 'landed') { & $script:globalRuleOriginalWriteBytes -Path $Path -Bytes $Bytes }
                throw 'fixture second action failure'
            }
            & $script:globalRuleOriginalWriteBytes -Path $Path -Bytes $Bytes
        }
        { Invoke-TestApply $plan $fixture $codex $claude $receiptPath } | Should -Throw '*fixture second action failure*'
        $script:globalRuleFaultEnabled = $false
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        $receipt.status | Should -Be 'recovery_required'
        $receipt.actions[0].status | Should -Be 'applied'
        $receipt.actions[1].status | Should -Be $(if ($Stage -eq 'pending') { 'pending' } else { 'prepared' })
        if ($Stage -eq 'pending') {
            [IO.File]::WriteAllText($target,'foreign change')
            { Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups') } | Should -Throw '*Pending target drift*'
            (Get-GlobalRuleFileFacts (Join-Path $codex 'AGENTS.md')).hash | Should -Be $plan.actions[0].source_hash
            [IO.File]::WriteAllText($target,'# old claude')
        }
        $result = Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups')
        $result.pass | Should -BeTrue
        [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md')) | Should -Be '# old codex'
        if ($Operation -eq 'create') { Test-Path -LiteralPath $target | Should -BeFalse }
        else { [IO.File]::ReadAllText($target) | Should -Be '# old claude' }
        (Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups')).writes | Should -Be 0
    }

    It 'resumes an interrupted rollback and still blocks target drift after source changes' {
        $plan = New-GlobalRuleProjectionPlan $fixture $codex $claude
        $receipt = Invoke-TestApply $plan $fixture $codex $claude $receiptPath
        Add-Content -LiteralPath (Join-Path $fixture 'rules/global/codex/AGENTS.md') -Value 'later revision'
        $script:globalRuleFaultEnabled = $true
        $script:globalRuleFaultTarget = Join-Path $codex 'AGENTS.md'
        Mock Write-BytesAtomic {
            param($Path,$Bytes)
            if ($script:globalRuleFaultEnabled -and $Path -eq $script:globalRuleFaultTarget) { throw 'fixture rollback interruption' }
            & $script:globalRuleOriginalWriteBytes -Path $Path -Bytes $Bytes
        }
        { Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups') } | Should -Throw '*fixture rollback interruption*'
        $interrupted = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        $interrupted.status | Should -Be 'rollback_in_progress'
        $interrupted.actions[1].status | Should -Be 'rolled_back'
        $script:globalRuleFaultEnabled = $false
        [IO.File]::WriteAllText((Join-Path $claude 'CLAUDE.md'),'foreign change')
        { Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups') } | Should -Throw '*Rolled-back target drift*'
        [IO.File]::WriteAllText((Join-Path $claude 'CLAUDE.md'),'# old claude')
        (Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports/global-rule-projection/backups')).writes | Should -Be 1
        [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md')) | Should -Be '# old codex'
    }

    It 'fails closed for schema v1 plans' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$plan.schema_version=1
        {Invoke-TestApply $plan $fixture $codex $claude $receiptPath}|Should -Throw '*plan_schema_invalid*'
    }

    It 'fails closed when a source changes after planning' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude
        Add-Content -LiteralPath (Join-Path $fixture 'rules\global\codex\AGENTS.md') -Value "`n# drift"
        {Invoke-TestApply $plan $fixture $codex $claude $receiptPath}|Should -Throw '*stale*'
    }

    It 'rejects a tampered source path' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$plan.actions[0].source_path=$plan.actions[1].source_path
        {Invoke-TestApply $plan $fixture $codex $claude $receiptPath}|Should -Throw '*plan_action_binding_mismatch*'
    }

    It 'rejects a tampered target path' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$plan.actions[0].target_path=Join-Path $TestDrive 'outside.md'
        {Invoke-TestApply $plan $fixture $codex $claude $receiptPath}|Should -Throw '*plan_action_binding_mismatch*'
    }

    It 'rejects missing or duplicate canonical actions' {
        $missing=New-GlobalRuleProjectionPlan $fixture $codex $claude;$missing.actions=@($missing.actions[0])
        {Invoke-TestApply $missing $fixture $codex $claude $receiptPath}|Should -Throw '*plan_action_set_invalid*'
        $duplicate=New-GlobalRuleProjectionPlan $fixture $codex $claude;$duplicate.actions=@($duplicate.actions[0],$duplicate.actions[0])
        {Invoke-TestApply $duplicate $fixture $codex $claude $receiptPath}|Should -Throw '*plan_action_binding_mismatch*'
    }

    It 'rejects tampered operation identity and token' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$plan.operation_id='global-rules-0000000000000000'
        {Invoke-TestApply $plan $fixture $codex $claude $receiptPath}|Should -Throw '*plan_identity_invalid*'
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$plan.apply.required_token='APPLY_GLOBAL_RULES_0000000000000000'
        {Invoke-TestApply $plan $fixture $codex $claude $receiptPath}|Should -Throw '*plan_identity_invalid*'
    }

    It 'requires explicit resume when a receipt exists' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude
        [IO.File]::WriteAllText($receiptPath,'{}')
        {Invoke-TestApply $plan $fixture $codex $claude $receiptPath}|Should -Throw '*already exists*'
    }

    It 'requires an existing receipt for resume' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude
        {Invoke-TestApply $plan $fixture $codex $claude $receiptPath -Resume}|Should -Throw '*requires an existing receipt*'
    }

    It 'resumes a canonical pending journal' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$identity=Get-GlobalRulePlanIdentity $fixture $codex $claude $plan.actions
        $actions=@($plan.actions|ForEach-Object{[pscustomobject]@{id=$_.id;source_path=$_.source_path;target_path=$_.target_path;source_hash=$_.source_hash;before_exists=[bool]$_.before_exists;before_hash=$_.before_hash;operation=$_.operation;status='pending';backup_path=$null;backup_sha256=$null;backup_length=$null}})
        $receipt=[pscustomobject]@{schema_version=2;domain='global_rule_projection';operation_id=$plan.operation_id;plan_hash=$plan.plan_hash;status='in_progress';repo_root=$fixture;codex_user_root=$codex;claude_user_root=$claude;actions=$actions;writes=0;rollback=[pscustomobject]@{required_token=$identity.rollback_token}}
        Write-Utf8FileAtomic $receiptPath ($receipt|ConvertTo-Json -Depth 20 -Compress)
        (Invoke-TestApply $plan $fixture $codex $claude $receiptPath -Resume).status|Should -Be 'applied'
    }

    It 'resumes a prepared action after the desired write landed' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$identity=Get-GlobalRulePlanIdentity $fixture $codex $claude $plan.actions;$backupRoot=Join-Path $fixture 'reports\global-rule-projection\backups';$backupBase=Join-Path $backupRoot $plan.operation_id;New-Item -ItemType Directory -Path $backupBase -Force|Out-Null
        $actions=@($plan.actions|ForEach-Object{[pscustomobject]@{id=$_.id;source_path=$_.source_path;target_path=$_.target_path;source_hash=$_.source_hash;before_exists=[bool]$_.before_exists;before_hash=$_.before_hash;operation=$_.operation;status='pending';backup_path=$null;backup_sha256=$null;backup_length=$null}})
        $first=$actions[0];$bytes=[IO.File]::ReadAllBytes($first.target_path);$backup=Join-Path $backupBase "$($first.id).bak";Write-BytesAtomic $backup $bytes;$first.status='prepared';$first.backup_path=$backup;$first.backup_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant();$first.backup_length=$bytes.Length;Write-BytesAtomic $first.target_path ([IO.File]::ReadAllBytes($first.source_path))
        $receipt=[pscustomobject]@{schema_version=2;domain='global_rule_projection';operation_id=$plan.operation_id;plan_hash=$plan.plan_hash;status='in_progress';repo_root=$fixture;codex_user_root=$codex;claude_user_root=$claude;actions=$actions;writes=0;rollback=[pscustomobject]@{required_token=$identity.rollback_token}}
        Write-Utf8FileAtomic $receiptPath ($receipt|ConvertTo-Json -Depth 20 -Compress)
        $result=Invoke-TestApply $plan $fixture $codex $claude $receiptPath -Resume
        $result.status|Should -Be 'applied';$result.writes|Should -Be 2
    }

    It 'rejects tampered rollback target and backup paths' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$receipt=Invoke-TestApply $plan $fixture $codex $claude $receiptPath
        $doc=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json;$doc.actions[0].target_path=Join-Path $TestDrive 'outside.md';Write-Utf8FileAtomic $receiptPath ($doc|ConvertTo-Json -Depth 20 -Compress)
        {Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports\global-rule-projection\backups')}|Should -Throw '*canonical binding*'
        Reset-GlobalRuleFixture $fixture $codex $claude;$plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$receipt=Invoke-TestApply $plan $fixture $codex $claude $receiptPath
        $doc=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json;$doc.actions[0].backup_path=Join-Path $TestDrive 'outside.bak';Write-Utf8FileAtomic $receiptPath ($doc|ConvertTo-Json -Depth 20 -Compress)
        {Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports\global-rule-projection\backups')}|Should -Throw '*receipt_backup_path_invalid*'
    }

    It 'rejects a corrupted backup and a generic rollback token' {
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$receipt=Invoke-TestApply $plan $fixture $codex $claude $receiptPath
        {Invoke-GlobalRuleProjectionRollback $receiptPath 'ROLLBACK_GLOBAL_RULES' $fixture $codex $claude (Join-Path $fixture 'reports\global-rule-projection\backups')}|Should -Throw '*token*'
        [IO.File]::WriteAllText([string]$receipt.actions[0].backup_path,'corrupt')
        {Invoke-GlobalRuleProjectionRollback $receiptPath $receipt.rollback.required_token $fixture $codex $claude (Join-Path $fixture 'reports\global-rule-projection\backups')}|Should -Throw '*integrity*'
    }
}

Describe 'Global rule CLI boundaries' {
    BeforeEach {
        $fixture=Join-Path $TestDrive 'repo';$codex=Join-Path $TestDrive 'codex';$claude=Join-Path $TestDrive 'claude'
        Reset-GlobalRuleFixture $fixture $codex $claude
    }

    It 'uses active Codex and Claude profile roots unless explicit roots override them' {
        $oldCodex=$env:CODEX_HOME;$oldClaude=$env:CLAUDE_CONFIG_DIR
        try{
            $env:CODEX_HOME=$codex;$env:CLAUDE_CONFIG_DIR=$claude
            $parsed=Parse-GlobalRuleOptions @() check;$parsed.codex_user_root|Should -Be $codex;$parsed.codex_user_root_source|Should -Be 'CODEX_HOME'
            $parsed.claude_user_root|Should -Be $claude;$parsed.claude_user_root_source|Should -Be 'CLAUDE_CONFIG_DIR'
            $parsed=Parse-GlobalRuleOptions @('--codex-user-root',$claude) check;$parsed.codex_user_root|Should -Be $claude;$parsed.codex_user_root_source|Should -Be 'cli'
            $parsed=Parse-GlobalRuleOptions @('--claude-user-root',$codex) check;$parsed.claude_user_root|Should -Be $codex;$parsed.claude_user_root_source|Should -Be 'cli'
            $parsed=Parse-GlobalRuleOptions @('--zcode-user-root',$codex) check;$parsed.zcode_user_root|Should -Be $codex;$parsed.zcode_user_root_source|Should -Be 'cli'
            $parsed=Parse-GlobalRuleOptions @('--antigravity-user-root',$codex) check;$parsed.antigravity_user_root|Should -Be $codex;$parsed.antigravity_user_root_source|Should -Be 'cli'
        }finally{$env:CODEX_HOME=$oldCodex;$env:CLAUDE_CONFIG_DIR=$oldClaude}
    }

    It 'rejects a missing explicit ZCode root instead of treating it as disabled' {
        $missing = Join-Path $TestDrive 'missing-zcode-root'
        {
            Invoke-GlobalRuleCommand check @('--repo-root',$fixture,'--codex-user-root',$codex,'--claude-user-root',$claude,'--zcode-user-root',$missing)
        } | Should -Throw '*ZCode user root does not exist or is not a directory*'
    }

    It 'rejects a missing explicit Antigravity root instead of treating it as disabled' {
        $missing = Join-Path $TestDrive 'missing-antigravity-root'
        {
            Invoke-GlobalRuleCommand check @('--repo-root',$fixture,'--codex-user-root',$codex,'--claude-user-root',$claude,'--antigravity-user-root',$missing)
        } | Should -Throw '*Antigravity user root does not exist or is not a directory*'
    }

    It 'enables the WorkBuddy host root without a pre-existing projected rule' {
        $old=$env:CODEBUDDY_CONFIG_DIR;$oldWork=$env:WORKBUDDY_CONFIG_DIR
        try{
            $env:WORKBUDDY_CONFIG_DIR=$null
            $env:CODEBUDDY_CONFIG_DIR=Join-Path $TestDrive 'workbuddy-host-without-rule'
            New-Item -ItemType Directory -Path $env:CODEBUDDY_CONFIG_DIR -Force|Out-Null
            $parsed=Parse-GlobalRuleOptions @() check
            $parsed.workbuddy_user_root|Should -Be $env:CODEBUDDY_CONFIG_DIR
            $parsed.workbuddy_user_root_source|Should -Be 'CODEBUDDY_CONFIG_DIR'
        }finally{$env:CODEBUDDY_CONFIG_DIR=$old;$env:WORKBUDDY_CONFIG_DIR=$oldWork}
    }

    It 'prefers WORKBUDDY_CONFIG_DIR and auto-detects an existing .workbuddy-ai root' {
        $old=$env:CODEBUDDY_CONFIG_DIR;$oldWork=$env:WORKBUDDY_CONFIG_DIR
        $profileRoot=[Environment]::GetFolderPath('UserProfile');$legacy=Join-Path $profileRoot '.workbuddy-ai';$hadLegacy=Test-Path -LiteralPath $legacy
        try{
            $env:CODEBUDDY_CONFIG_DIR=$null;$env:WORKBUDDY_CONFIG_DIR=Join-Path $TestDrive 'workbuddy-new-root'
            New-Item -ItemType Directory -Path $env:WORKBUDDY_CONFIG_DIR -Force|Out-Null
            $parsed=Parse-GlobalRuleOptions @() check
            $parsed.workbuddy_user_root|Should -Be $env:WORKBUDDY_CONFIG_DIR
            $parsed.workbuddy_user_root_source|Should -Be 'WORKBUDDY_CONFIG_DIR'
            $env:WORKBUDDY_CONFIG_DIR=$null
            if(-not $hadLegacy){New-Item -ItemType Directory -Path $legacy -Force|Out-Null}
            $parsed=Parse-GlobalRuleOptions @() check
            $parsed.workbuddy_user_root|Should -Be $legacy
            $parsed.workbuddy_user_root_source|Should -Be 'default'
        }finally{
            $env:CODEBUDDY_CONFIG_DIR=$old;$env:WORKBUDDY_CONFIG_DIR=$oldWork
            if(-not $hadLegacy -and (Test-Path -LiteralPath $legacy)){Remove-Item -LiteralPath $legacy -Recurse -Force}
        }
    }

    It 'rejects a missing CODEBUDDY_CONFIG_DIR root instead of treating it as disabled' {
        $old=$env:CODEBUDDY_CONFIG_DIR;$oldWork=$env:WORKBUDDY_CONFIG_DIR
        try{
            # WORKBUDDY_CONFIG_DIR takes precedence over the legacy
            # CODEBUDDY_CONFIG_DIR, so it must be cleared for this case to reach
            # the legacy variable at all. Without this the test silently depends
            # on the ambient environment: on a host that sets WORKBUDDY_CONFIG_DIR
            # (WorkBuddy sessions do) the resolved root stays valid and the
            # expected throw never happens.
            $env:WORKBUDDY_CONFIG_DIR=$null
            $env:CODEBUDDY_CONFIG_DIR=Join-Path $TestDrive 'missing-workbuddy-root'
            {
                Invoke-GlobalRuleCommand check @('--repo-root',$fixture,'--codex-user-root',$codex,'--claude-user-root',$claude)
            } | Should -Throw '*WorkBuddy user root does not exist or is not a directory*'
        }finally{$env:CODEBUDDY_CONFIG_DIR=$old;$env:WORKBUDDY_CONFIG_DIR=$oldWork}
    }

    It 'rejects control outputs outside the dedicated reports directory' {
        {Resolve-GlobalRuleControlPath (Join-Path $fixture 'plan.json') $fixture}|Should -Throw '*reports/global-rule-projection*'
        {Resolve-GlobalRuleControlPath (Join-Path $fixture 'rules\global\codex\AGENTS.md') $fixture}|Should -Throw '*reports/global-rule-projection*'
    }

    It 'rejects backup-directory control files and equal plan/receipt paths' {
        {Resolve-GlobalRuleControlPath (Join-Path $fixture 'reports\global-rule-projection\backups\plan.json') $fixture}|Should -Throw '*backups*'
        $planPath=Join-Path $fixture 'reports\global-rule-projection\plan.json'
        $plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$envelope=[pscustomobject]@{command='global-rules-plan';plan=$plan};Write-Utf8FileAtomic $planPath ($envelope|ConvertTo-Json -Depth 20 -Compress)
        {Invoke-GlobalRuleCommand apply @('--repo-root',$fixture,'--codex-user-root',$codex,'--claude-user-root',$claude,'--plan',$planPath,'--token',$plan.apply.required_token,'--out',$planPath)}|Should -Throw '*must differ*'
    }
}
