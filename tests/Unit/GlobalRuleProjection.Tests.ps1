BeforeAll {
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Root=$repoRoot
    . (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Application\GlobalRuleProjection.ps1')
    . (Join-Path $repoRoot 'src\Commands\GlobalRules.ps1')

    function Copy-GlobalRuleFixture([string]$Fixture,[string]$Codex,[string]$Claude) {
        New-Item -ItemType Directory -Path (Join-Path $Fixture 'rules\global\codex'),(Join-Path $Fixture 'rules\global\claude'),$Codex,$Claude,(Join-Path $Fixture 'reports\global-rule-projection') -Force|Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules\global\codex\AGENTS.md') -Destination (Join-Path $Fixture 'rules\global\codex\AGENTS.md')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules\global\claude\CLAUDE.md') -Destination (Join-Path $Fixture 'rules\global\claude\CLAUDE.md')
        Set-Content -LiteralPath (Join-Path $Codex 'AGENTS.md') -Value '# old codex' -Encoding utf8NoBOM -NoNewline
        Set-Content -LiteralPath (Join-Path $Claude 'CLAUDE.md') -Value '# old claude' -Encoding utf8NoBOM -NoNewline
    }

    function Invoke-TestApply($Plan,[string]$Fixture,[string]$Codex,[string]$Claude,[string]$Receipt,[switch]$Resume) {
        $backupRoot=Join-Path $Fixture 'reports\global-rule-projection\backups'
        return Invoke-GlobalRuleProjectionApply -Plan $Plan -Token $Plan.apply.required_token -BackupRoot $backupRoot -ReceiptPath $Receipt -RepoRoot $Fixture -CodexUserRoot $Codex -ClaudeUserRoot $Claude -Resume:$Resume
    }
}

Describe 'Global rule source contract' {
    BeforeEach {
        $fixture=Join-Path $TestDrive 'repo';$codex=Join-Path $TestDrive 'codex';$claude=Join-Path $TestDrive 'claude'
        foreach($path in @($fixture,$codex,$claude)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force}}
        Copy-GlobalRuleFixture $fixture $codex $claude
    }

    It 'validates the tracked source family, shared A/C/D sections, and budgets' {
        $result=Test-GlobalRuleSourceFamily $fixture $codex $claude
        $result.pass|Should -BeTrue
        $result.facts.codex.version|Should -Be '9.76'
        $result.facts.claude.bytes|Should -BeLessOrEqual 16384
        @($result.observations).Count|Should -Be 0
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

    It 'rejects a drive root as a user projection root' {
        {New-GlobalRuleProjectionPlan $fixture ([IO.Path]::GetPathRoot($codex)) $claude}|Should -Throw '*Drive roots*'
    }
}

Describe 'Global rule schema v2 apply and rollback' {
    BeforeEach {
        $fixture=Join-Path $TestDrive 'repo';$codex=Join-Path $TestDrive 'codex';$claude=Join-Path $TestDrive 'claude';$receiptPath=Join-Path $fixture 'reports\global-rule-projection\receipt.json'
        foreach($path in @($fixture,$codex,$claude)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force}}
        Copy-GlobalRuleFixture $fixture $codex $claude
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
        foreach($path in @($fixture,$codex,$claude)){Remove-Item -LiteralPath $path -Recurse -Force};Copy-GlobalRuleFixture $fixture $codex $claude;$plan=New-GlobalRuleProjectionPlan $fixture $codex $claude;$receipt=Invoke-TestApply $plan $fixture $codex $claude $receiptPath
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
        foreach($path in @($fixture,$codex,$claude)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force}}
        Copy-GlobalRuleFixture $fixture $codex $claude
    }

    It 'uses active Codex and Claude profile roots unless explicit roots override them' {
        $oldCodex=$env:CODEX_HOME;$oldClaude=$env:CLAUDE_CONFIG_DIR
        try{
            $env:CODEX_HOME=$codex;$env:CLAUDE_CONFIG_DIR=$claude
            $parsed=Parse-GlobalRuleOptions @() check;$parsed.codex_user_root|Should -Be $codex;$parsed.codex_user_root_source|Should -Be 'CODEX_HOME'
            $parsed.claude_user_root|Should -Be $claude;$parsed.claude_user_root_source|Should -Be 'CLAUDE_CONFIG_DIR'
            $parsed=Parse-GlobalRuleOptions @('--codex-user-root',$claude) check;$parsed.codex_user_root|Should -Be $claude;$parsed.codex_user_root_source|Should -Be 'cli'
            $parsed=Parse-GlobalRuleOptions @('--claude-user-root',$codex) check;$parsed.claude_user_root|Should -Be $codex;$parsed.claude_user_root_source|Should -Be 'cli'
        }finally{$env:CODEX_HOME=$oldCodex;$env:CLAUDE_CONFIG_DIR=$oldClaude}
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
