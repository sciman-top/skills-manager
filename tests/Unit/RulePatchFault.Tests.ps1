$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1'); . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1'); . (Join-Path $repoRoot 'src\Domain\Receipt.ps1'); . (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1'); . (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1'); . (Join-Path $repoRoot 'src\Application\RulePatchGuard.ps1'); . (Join-Path $repoRoot 'src\Application\RulePatchExecutor.ps1')

Describe 'Rule patch fault and concurrency recovery' {
    function New-FaultFixture([string]$Name) { $root=Join-Path $TestDrive $Name;New-Item -ItemType Directory $root -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'),'fixture');$path=Join-Path $root 'AGENTS.md';[IO.File]::WriteAllText($path,'before');$plan=New-RulePatchPlan -TargetPath $path -AuthorizedRoot $root -CurrentText before -DesiredText after -DesiredSource reviewed_file;[pscustomobject]@{root=$root;path=$path;plan=$plan} }

    It 'keeps exact before content across all pre-replace fault points' {
        foreach($fault in @('before_stage','after_stage','before_replace')) { $f=New-FaultFixture $fault;$result=Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH -TestFaultPoint $fault;[IO.File]::ReadAllText($f.path)|Should Be 'before';$result.writes|Should Be 0 }
    }

    It 'restores after replace and before receipt faults' {
        foreach($fault in @('after_replace','before_receipt')) { $f=New-FaultFixture $fault;$result=Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH -TestFaultPoint $fault;[IO.File]::ReadAllText($f.path)|Should Be 'before';$result.rollback|Should Be 'restored' }
    }

    It 'reports rollback failure without claiming restoration' {
        $f=New-FaultFixture rollback_failure;$result=Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH -TestFaultPoint after_replace_rollback_failure
        $result.status | Should Be 'failed'; $result.rollback | Should Be 'rollback_failed'; [IO.File]::ReadAllText($f.path) | Should Be 'after'
    }

    It 'blocks a concurrent target change before replace' {
        $f=New-FaultFixture concurrent; [IO.File]::WriteAllText($f.path,'concurrent');$result=Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH
        $result.status | Should Be 'blocked'; [IO.File]::ReadAllText($f.path) | Should Be 'concurrent'
    }
}
