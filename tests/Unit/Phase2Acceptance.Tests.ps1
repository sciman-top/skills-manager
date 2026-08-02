$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$fixtureSource = Join-Path $repoRoot 'tests\fixtures\phase2-acceptance'
. (Join-Path $repoRoot 'skills.ps1')

Describe 'Phase 2 repository-side acceptance' {
    function New-Phase2Fixture([string]$Name, [bool]$WithMarker = $true) {
        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        if ($WithMarker) { [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture') }
        $target = Join-Path $root 'AGENTS.md'; $desired = Join-Path $root 'desired.md'
        [IO.File]::Copy((Join-Path $fixtureSource 'AGENTS.before.md'), $target, $true)
        [IO.File]::Copy((Join-Path $fixtureSource 'AGENTS.desired.md'), $desired, $true)
        $current = [IO.File]::ReadAllText($target); $wanted = [IO.File]::ReadAllText($desired)
        $plan = New-RulePatchPlan -TargetPath $target -AuthorizedRoot $root -CurrentText $current -DesiredText $wanted -DesiredSource reviewed_file
        return [pscustomobject]@{ root=$root; target=$target; desired=$desired; current=$current; wanted=$wanted; plan=$plan }
    }

    It 'applies the reviewed desired fixture exactly and reports repo-only truth' {
        $f = New-Phase2Fixture success
        $result = Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH

        $result.pass | Should Be $true
        [IO.File]::ReadAllText($f.target) | Should Be $f.wanted
        (Test-OperationReceiptContract $result.receipt).pass | Should Be $true
        $result.receipt.verification.static_validated | Should Be 'pass'
        $result.receipt.verification.repo_gates_passed | Should Be 'not_run'
        $result.receipt.verification.host_loaded | Should Be 'not_run'
        $result.receipt.verification.live_accepted | Should Be 'not_run'
    }

    It 'blocks stale content and wrong tokens with zero writes' {
        foreach ($case in @('stale','token')) {
            $f = New-Phase2Fixture $case
            if ($case -eq 'stale') { [IO.File]::WriteAllText($f.target, 'concurrent') }
            $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.target))
            $token = if ($case -eq 'token') { 'WRONG' } else { 'APPLY_RULE_PATCH' }
            $result = Invoke-RulePatchApply $f.plan $f.root $token

            $result.status | Should Be 'blocked'; $result.writes | Should Be 0
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.target)) | Should Be $before
        }
    }

    It 'rejects outside-root targets and roots without a fixture marker' {
        $inside = New-Phase2Fixture inside
        $outsideRoot = Join-Path $TestDrive 'outside'; New-Item -ItemType Directory $outsideRoot -Force | Out-Null
        $outsideTarget = Join-Path $outsideRoot 'AGENTS.md'; [IO.File]::WriteAllText($outsideTarget, 'before')
        $outsidePlan = New-RulePatchPlan -TargetPath $outsideTarget -AuthorizedRoot $inside.root -CurrentText before -DesiredText after -DesiredSource reviewed_file
        $outsideResult = Invoke-RulePatchApply $outsidePlan $inside.root APPLY_RULE_PATCH
        $unmarked = New-Phase2Fixture unmarked $false
        $unmarkedResult = Invoke-RulePatchApply $unmarked.plan $unmarked.root APPLY_RULE_PATCH

        $outsideResult.status | Should Be 'blocked'; $outsideResult.writes | Should Be 0
        [IO.File]::ReadAllText($outsideTarget) | Should Be 'before'
        $unmarkedResult.status | Should Be 'blocked'; $unmarkedResult.writes | Should Be 0
        [IO.File]::ReadAllText($unmarked.target) | Should Be $unmarked.current
    }

    It 'rejects sensitive desired content at planning and apply validation' {
        $f = New-Phase2Fixture sensitive
        $sensitive = [IO.File]::ReadAllText((Join-Path $fixtureSource 'AGENTS.sensitive.md'))
        $plan = New-RulePatchPlan -TargetPath $f.target -AuthorizedRoot $f.root -CurrentText $f.current -DesiredText $sensitive -DesiredSource reviewed_file
        $validation = Test-RulePatchPlanContract $plan
        $before = (Get-FileHash -LiteralPath $f.target -Algorithm SHA256).Hash
        $result = Invoke-RulePatchApply $plan $f.root APPLY_RULE_PATCH

        $validation.pass | Should Be $false
        @($validation.findings.code) | Should Contain 'sensitive_content_present'
        $result.status | Should Be 'blocked'; $result.writes | Should Be 0
        (Get-FileHash -LiteralPath $f.target -Algorithm SHA256).Hash | Should Be $before
    }

    It 'keeps pre-replace faults at zero writes and restores exact bytes after replace' {
        foreach ($fault in @('before_stage','after_stage','before_replace')) {
            $f = New-Phase2Fixture ('fault-'+$fault); $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.target))
            $result = Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH -TestFaultPoint $fault
            $result.pass | Should Be $false; $result.writes | Should Be 0
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.target)) | Should Be $before
        }
        foreach ($fault in @('after_replace','before_receipt')) {
            $f = New-Phase2Fixture ('fault-'+$fault); $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.target))
            $result = Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH -TestFaultPoint $fault
            $result.status | Should Be 'rolled_back'; $result.rollback | Should Be 'restored'
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.target)) | Should Be $before
        }
    }

    It 'reports simulated rollback failure truthfully and retains recovery evidence' {
        $f = New-Phase2Fixture rollback-failed
        $result = Invoke-RulePatchApply $f.plan $f.root APPLY_RULE_PATCH -TestFaultPoint after_replace_rollback_failure

        $result.pass | Should Be $false; $result.status | Should Be 'failed'; $result.rollback | Should Be 'rollback_failed'
        [IO.File]::ReadAllText($f.target) | Should Be $f.wanted
        @(Get-ChildItem -LiteralPath $f.root -Force | Where-Object Name -match '\.backup$').Count | Should Be 1
    }

    It 'preserves all authorized real rule and config hashes while rejecting real apply' {
        $paths = @(
            (Join-Path $repoRoot 'AGENTS.md'),
            (Join-Path $repoRoot 'skills.json'),
            'D:\CODE-other\governed-ai-coding-runtime\AGENTS.md'
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        $before = @{}; foreach ($path in $paths) { $before[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }

        { Invoke-RulePlanCommand @('--target',(Join-Path $repoRoot 'AGENTS.md'),'--desired-file',(Join-Path $repoRoot 'README.md'),'--fixture-root',$repoRoot,'--json') } | Should Throw

        foreach ($path in $paths) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should Be $before[$path] }
    }
}
