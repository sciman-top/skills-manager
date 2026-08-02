$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'skills.ps1')

Describe 'Fixture-only rule patch CLI' {
    function New-CliFixture([string]$Name, [bool]$WithMarker = $true) {
        $root = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        if ($WithMarker) { [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture') }
        $target = Join-Path $root 'AGENTS.md'
        $desired = Join-Path $root 'desired.md'
        [IO.File]::WriteAllText($target, 'before')
        [IO.File]::WriteAllText($desired, 'after')
        return [pscustomobject]@{ root=$root; target=$target; desired=$desired; plan=(Join-Path $root 'plan.json') }
    }

    It 'requires an explicit fixture marker' {
        $f = New-CliFixture missing $false
        { Invoke-RulePlanCommand @('--target',$f.target,'--desired-file',$f.desired,'--fixture-root',$f.root,'--json') } | Should Throw
        [IO.File]::ReadAllText($f.target) | Should Be 'before'
    }

    It 'creates one JSON plan report without changing the target' {
        $f = New-CliFixture plan
        $before = (Get-FileHash -LiteralPath $f.target -Algorithm SHA256).Hash
        $result = Invoke-RulePlanCommand @('--target',$f.target,'--desired-file',$f.desired,'--fixture-root',$f.root,'--json','--out',$f.plan)
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.command | Should Be 'rule-plan'
        $parsed.target_writes | Should Be 0
        $parsed.host_writes | Should Be 0
        (Get-FileHash -LiteralPath $f.target -Algorithm SHA256).Hash | Should Be $before
        @((Get-Content -LiteralPath $f.plan -Raw).Split([Environment]::NewLine)).Count | Should Be 1
    }

    It 'applies only a reviewed fixture plan with the explicit token' {
        $f = New-CliFixture apply
        $null = Invoke-RulePlanCommand @('--target',$f.target,'--desired-file',$f.desired,'--fixture-root',$f.root,'--json','--out',$f.plan)
        $result = Invoke-RuleApplyCommand @('--plan',$f.plan,'--fixture-root',$f.root,'--token','APPLY_RULE_PATCH','--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.truth_boundary | Should Be 'fixture_only'
        $parsed.result.receipt.verification.host_loaded | Should Be 'not_run'
        $parsed.result.receipt.verification.live_accepted | Should Be 'not_run'
        [IO.File]::ReadAllText($f.target) | Should Be 'after'
    }

    It 'returns blocked for a wrong token or stale target without writing desired content' {
        foreach ($case in @('token','stale')) {
            $f = New-CliFixture $case
            $null = Invoke-RulePlanCommand @('--target',$f.target,'--desired-file',$f.desired,'--fixture-root',$f.root,'--json','--out',$f.plan)
            if ($case -eq 'stale') { [IO.File]::WriteAllText($f.target, 'concurrent') }
            $before = (Get-FileHash -LiteralPath $f.target -Algorithm SHA256).Hash
            $token = if ($case -eq 'token') { 'WRONG' } else { 'APPLY_RULE_PATCH' }
            $result = Invoke-RuleApplyCommand @('--plan',$f.plan,'--fixture-root',$f.root,'--token',$token,'--json')
            $result.exit_code | Should Be 2
            $result.envelope.result.status | Should Be 'blocked'
            (Get-FileHash -LiteralPath $f.target -Algorithm SHA256).Hash | Should Be $before
        }
    }

    It 'rejects plans and report outputs outside the fixture boundary' {
        $f = New-CliFixture boundary
        $outside = Join-Path $TestDrive 'outside.json'
        { Invoke-RulePlanCommand @('--target',$f.target,'--desired-file',$f.desired,'--fixture-root',$f.root,'--json','--out',$outside) } | Should Throw
        [IO.File]::WriteAllText($outside, '{}')
        { Invoke-RuleApplyCommand @('--plan',$outside,'--fixture-root',$f.root,'--token','APPLY_RULE_PATCH','--json') } | Should Throw
    }

    It 'refuses report paths that overwrite target desired or plan inputs' {
        $f = New-CliFixture overwrite
        { Invoke-RulePlanCommand @('--target',$f.target,'--desired-file',$f.desired,'--fixture-root',$f.root,'--json','--out',$f.target) } | Should Throw
        $null = Invoke-RulePlanCommand @('--target',$f.target,'--desired-file',$f.desired,'--fixture-root',$f.root,'--json','--out',$f.plan)
        { Invoke-RuleApplyCommand @('--plan',$f.plan,'--fixture-root',$f.root,'--token','APPLY_RULE_PATCH','--json','--out',$f.plan) } | Should Throw
        [IO.File]::ReadAllText($f.target) | Should Be 'before'
    }

    It 'rejects semantic recommendation plans before any write' {
        $f = New-CliFixture semantic
        $plan = New-RulePatchPlan -TargetPath $f.target -AuthorizedRoot $f.root -CurrentText before -DesiredText after -DesiredSource semantic_recommendation
        [IO.File]::WriteAllText($f.plan, ($plan | ConvertTo-Json -Depth 40))
        $before = (Get-FileHash -LiteralPath $f.target -Algorithm SHA256).Hash
        $result = Invoke-RuleApplyCommand @('--plan',$f.plan,'--fixture-root',$f.root,'--token','APPLY_RULE_PATCH','--json')
        $result.exit_code | Should Be 2
        (Get-FileHash -LiteralPath $f.target -Algorithm SHA256).Hash | Should Be $before
    }

    It 'rejects the real repository because it has no fixture marker' {
        $before = (Get-FileHash -LiteralPath (Join-Path $repoRoot 'AGENTS.md') -Algorithm SHA256).Hash
        { Invoke-RulePlanCommand @('--target',(Join-Path $repoRoot 'AGENTS.md'),'--desired-file',(Join-Path $repoRoot 'README.md'),'--fixture-root',$repoRoot,'--json') } | Should Throw
        (Get-FileHash -LiteralPath (Join-Path $repoRoot 'AGENTS.md') -Algorithm SHA256).Hash | Should Be $before
    }

    It 'plans and applies one reviewed repository rule creation' {
        $root = Join-Path $TestDrive 'repo-cli'; New-Item -ItemType Directory -Path (Join-Path $root '.git') -Force | Out-Null
        $review = Join-Path $root 'reviewed-CLAUDE.md'; [IO.File]::WriteAllText($review, "@AGENTS.md`n")
        $target = Join-Path $root 'CLAUDE.md'; $planPath = Join-Path $root 'plan.json'

        $planned = Invoke-RulePlanCommand @('--target',$target,'--desired-file',$review,'--repo-root',$root,'--allow-create','--out',$planPath,'--json')
        $planned.exit_code | Should Be 0
        ($planned.output | ConvertFrom-Json).truth_boundary | Should Be 'single_repository'
        $applied = Invoke-RuleApplyCommand @('--plan',$planPath,'--repo-root',$root,'--token','APPLY_RULE_REPO_PATCH','--json')
        $applied.exit_code | Should Be 0
        [IO.File]::ReadAllText($target) | Should Be "@AGENTS.md`n"
    }
}
