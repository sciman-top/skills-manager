BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\Receipt.ps1')
    . (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
    . (Join-Path $repoRoot 'src\Application\RulePatchGuard.ps1')
    . (Join-Path $repoRoot 'src\Application\RulePatchExecutor.ps1')

}
Describe 'Fixture-only rule patch executor' {
    BeforeAll {
function New-ExecutorFixture([string]$Name) {
        $root = Join-Path $TestDrive $Name; New-Item -ItemType Directory $root -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture')
        $path = Join-Path $root 'AGENTS.md'; [System.IO.File]::WriteAllText($path, 'before')
        $other = Join-Path $root 'other.txt'; [System.IO.File]::WriteAllText($other, 'untouched')
        $plan = New-RulePatchPlan -TargetPath $path -AuthorizedRoot $root -CurrentText before -DesiredText after -DesiredSource reviewed_file
        return [pscustomobject]@{ root=$root; path=$path; other=$other; plan=$plan }
    }
}

    It 'atomically applies desired content and returns a truthful receipt' {
        $f=New-ExecutorFixture success; $result=Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH
        $result.pass | Should -Be $true; [System.IO.File]::ReadAllText($f.path) | Should -Be 'after'; [System.IO.File]::ReadAllText($f.other) | Should -Be 'untouched'
        (Test-OperationReceiptContract $result.receipt).pass | Should -Be $true
        $result.receipt.verification.static_validated | Should -Be 'pass'; $result.receipt.verification.host_loaded | Should -Be 'not_run'; $result.receipt.verification.live_accepted | Should -Be 'not_run'
    }

    It 'does not write when guard blocks' {
        $f=New-ExecutorFixture blocked; $before=(Get-FileHash $f.path).Hash; $result=Invoke-RulePatchApply $f.plan $f.root wrong
        $result.status | Should -Be 'blocked'; $result.writes | Should -Be 0; (Get-FileHash $f.path).Hash | Should -Be $before
    }

    It 'restores exact before content after a post-replace failure' {
        $f=New-ExecutorFixture rollback; $result=Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH -TestFaultPoint after_replace
        $result.status | Should -Be 'rolled_back'; $result.rollback | Should -Be 'restored'; [System.IO.File]::ReadAllText($f.path) | Should -Be 'before'
        (Test-OperationReceiptContract $result.receipt).pass | Should -Be $true
    }

    It 'restores the exact original bytes including a UTF-8 BOM' {
        $root = Join-Path $TestDrive 'rollback-bytes'; New-Item -ItemType Directory $root -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture')
        $path = Join-Path $root 'AGENTS.md'; $beforeBytes = [byte[]](0xEF,0xBB,0xBF,0x62,0x65,0x66,0x6F,0x72,0x65)
        [IO.File]::WriteAllBytes($path, $beforeBytes)
        $current = [IO.File]::ReadAllText($path)
        $plan = New-RulePatchPlan -TargetPath $path -AuthorizedRoot $root -CurrentText $current -DesiredText after -DesiredSource reviewed_file
        $result = Invoke-RulePatchApply $plan $root APPLY_RULE_PATCH -TestFaultPoint after_replace

        $result.status | Should -Be 'rolled_back'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -Be ([Convert]::ToBase64String($beforeBytes))
    }

    It 'cleans transaction files on success and rollback' {
        foreach($fault in @('none','after_stage','after_replace')) { $f=New-ExecutorFixture ('cleanup-'+$fault); $null=Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH -TestFaultPoint $fault; @(Get-ChildItem $f.root -Force | Where-Object Name -match '^\.patch-.*\.(stage|backup)$').Count | Should -Be 0 }
    }

    It 'creates one reviewed repository rule and rolls creation back on failure' {
        $root = Join-Path $TestDrive 'repo-create'; New-Item -ItemType Directory -Path (Join-Path $root '.git') -Force | Out-Null
        $path = Join-Path $root 'CLAUDE.md'
        $plan = New-RulePatchPlan -TargetPath $path -AuthorizedRoot $root -CurrentText '' -DesiredText "@AGENTS.md`n" -DesiredSource reviewed_file -AuthorizationScope repository -TargetOperation create

        $blocked = Invoke-RulePatchApply $plan $root wrong
        $blocked.status | Should -Be 'blocked'; Test-Path -LiteralPath $path | Should -Be $false
        $rolledBack = Invoke-RulePatchApply $plan $root APPLY_RULE_REPO_PATCH -TestFaultPoint after_replace
        $rolledBack.status | Should -Be 'rolled_back'; Test-Path -LiteralPath $path | Should -Be $false
        $applied = Invoke-RulePatchApply $plan $root APPLY_RULE_REPO_PATCH
        $applied.status | Should -Be 'applied'; [IO.File]::ReadAllText($path) | Should -Be "@AGENTS.md`n"
    }

    It 'rejects unknown repository rule filenames' {
        $root = Join-Path $TestDrive 'repo-name'; New-Item -ItemType Directory -Path (Join-Path $root '.git') -Force | Out-Null
        $path = Join-Path $root 'README.md'; [IO.File]::WriteAllText($path, 'before')
        $plan = New-RulePatchPlan -TargetPath $path -AuthorizedRoot $root -CurrentText before -DesiredText after -DesiredSource reviewed_file -AuthorizationScope repository

        $result = Invoke-RulePatchApply $plan $root APPLY_RULE_REPO_PATCH
        $result.status | Should -Be 'blocked'
        @($result.findings.code) | Should -Contain 'repository_target_name_forbidden'
        [IO.File]::ReadAllText($path) | Should -Be 'before'
    }
}
