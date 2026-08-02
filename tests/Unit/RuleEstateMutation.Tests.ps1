$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1')
. (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
. (Join-Path $repoRoot 'src\Application\RuleEstate.ps1')
. (Join-Path $repoRoot 'src\Application\RuleEstateMutation.ps1')
. (Join-Path $repoRoot 'src\Commands\RuleEstate.ps1')

Describe 'Reviewed rule estate mutation' {
    function New-EstateMutationFixture {
        $fixtureId = [guid]::NewGuid().ToString('N')
        $workspace = Join-Path $TestDrive ('workspace-' + $fixtureId)
        $repoA = Join-Path $workspace 'repo-a'
        $repoB = Join-Path $workspace 'repo-b'
        $reviewRoot = Join-Path $workspace 'review'
        $codex = Join-Path $TestDrive ('codex-' + $fixtureId)
        $claude = Join-Path $TestDrive ('claude-' + $fixtureId)
        foreach ($path in @($repoA, $repoB, $reviewRoot, $codex, $claude)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
        foreach ($path in @($repoA, $repoB)) {
            git -C $path init --quiet
            git -C $path config user.email fixture@example.invalid
            git -C $path config user.name fixture
            Set-Content -LiteralPath (Join-Path $path 'AGENTS.md') -Value "# $([IO.Path]::GetFileName($path))`n" -Encoding UTF8
            git -C $path add AGENTS.md
            git -C $path commit -m init --quiet
        }
        Set-Content -LiteralPath (Join-Path $codex 'AGENTS.md') -Value "# global codex`n" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $claude 'CLAUDE.md') -Value "# global claude`n" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $reviewRoot 'repo-a.desired.md') -Value "# repo-a improved`n" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $reviewRoot 'global.desired.md') -Value "# global improved`n" -Encoding UTF8
        $review = [pscustomobject][ordered]@{
            schema_version = 1
            review_status = 'reviewed'
            reviewed_by = 'workspace-owner'
            reviewed_by_type = 'human'
            authorization_source = 'user_supplied'
            changes = @(
                [pscustomobject]@{ target_scope='repository'; repository='repo-a'; target_file='AGENTS.md'; desired_file='repo-a.desired.md'; allow_create=$false; risk='medium'; evidence_refs=@('fixture') },
                [pscustomobject]@{ target_scope='global_codex'; target_file='AGENTS.md'; desired_file='global.desired.md'; allow_create=$false; risk='high'; evidence_refs=@('fixture') }
            )
        }
        $reviewPath = Join-Path $reviewRoot 'review.json'
        $review | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reviewPath -Encoding UTF8
        return [pscustomobject]@{ workspace=$workspace; repo_a=$repoA; repo_b=$repoB; codex=$codex; claude=$claude; review=$reviewPath }
    }

    It 'rejects AI self-reviewed manifests and forbidden target surfaces' {
        $f = New-EstateMutationFixture
        $review = [IO.File]::ReadAllText($f.review) | ConvertFrom-Json
        $review.reviewed_by_type = 'ai'
        $validation = Test-RuleEstateReviewContract $review ([IO.Path]::GetDirectoryName($f.review))
        $validation.pass | Should Be $false
        @($validation.findings.code) | Should Contain 'review_authority_invalid'

        $review.reviewed_by_type = 'human'
        $review.changes[0].target_file = '.codex/config.toml'
        $validation = Test-RuleEstateReviewContract $review ([IO.Path]::GetDirectoryName($f.review))
        @($validation.findings.code) | Should Contain 'target_file_forbidden'
    }

    It 'plans exact global and discovered repository targets without mutation' {
        $f = New-EstateMutationFixture
        $beforeRepo = [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md'))
        $beforeGlobal = [IO.File]::ReadAllText((Join-Path $f.codex 'AGENTS.md'))
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        $plan.actions.Count | Should Be 2
        $plan.target_set.paths.Count | Should Be 2
        $plan.apply.required_token | Should Be 'APPLY_RULE_ESTATE_PATCH'
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should Be $beforeRepo
        [IO.File]::ReadAllText((Join-Path $f.codex 'AGENTS.md')) | Should Be $beforeGlobal
    }

    It 'allows unrelated dirty paths but fails closed on target drift, target-set drift, and locks' {
        $f = New-EstateMutationFixture
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        Set-Content -LiteralPath (Join-Path $f.repo_a 'unrelated.txt') -Value 'preserve me'
        $preflight = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        $preflight.pass | Should Be $true
        @($preflight.findings.code) | Should Not Contain 'repository_dirty'
        @($plan.actions | Where-Object repository -eq 'repo-a')[0].dirty_paths_at_plan | Should BeNullOrEmpty
        $observedPlan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        (@($observedPlan.actions | Where-Object repository -eq 'repo-a')[0].dirty_paths_at_plan -join "`n") | Should Match 'unrelated\.txt'

        Add-Content -LiteralPath (Join-Path $f.repo_a 'AGENTS.md') -Value 'dirty'
        $preflight = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        @($preflight.findings.code) | Should Contain 'target_hash_stale'

        git -C $f.repo_a checkout -- AGENTS.md
        New-Item -ItemType Directory -Path (Join-Path $f.workspace 'repo-c\.git') -Force | Out-Null
        $preflight = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        @($preflight.findings.code) | Should Contain 'target_set_drift'

        Remove-Item -LiteralPath (Join-Path $f.workspace 'repo-c') -Recurse -Force
        Set-Content -LiteralPath (Join-Path $f.repo_a '.skills-manager-rule-estate.lock') -Value 'held'
        $preflight = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        @($preflight.findings.code) | Should Contain 'target_locked'
    }

    It 'applies one by one, persists receipts, resumes, and rolls back one target' {
        $f = New-EstateMutationFixture
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $receiptPath = Join-Path $f.workspace 'estate-receipt.json'
        $result = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token 'APPLY_RULE_ESTATE_PATCH' -ReceiptPath $receiptPath

        if (-not $result.pass) { throw ($result | ConvertTo-Json -Depth 20) }
        $result.pass | Should Be $true
        $result.receipt.actions.Count | Should Be 2
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should Match 'improved'
        Test-Path -LiteralPath $receiptPath | Should Be $true

        $resumed = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token 'APPLY_RULE_ESTATE_PATCH' -ReceiptPath $receiptPath -ResumeReceiptPath $receiptPath
        $resumed.pass | Should Be $true
        $resumed.writes | Should Be 0

        $actionId = [string]$result.receipt.actions[0].action_id
        $rollback = Invoke-RuleEstateRollback -ReceiptPath $receiptPath -ActionId $actionId -Token 'ROLLBACK_RULE_ESTATE_PATCH' -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $rollback.pass | Should Be $true
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should Match '# repo-a'
    }

    It 'rejects drive-root authorization and tampered rollback targets' {
        $f = New-EstateMutationFixture
        { New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot ([IO.Path]::GetPathRoot($f.codex)) -ClaudeUserRoot $f.claude } | Should Throw

        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $receiptPath = Join-Path $f.workspace 'tampered-receipt.json'
        $result = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token 'APPLY_RULE_ESTATE_PATCH' -ReceiptPath $receiptPath
        $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
        $victim = Join-Path $f.repo_a 'victim.txt'; [IO.File]::WriteAllText($victim, 'keep')
        $receipt.actions[0].target_path = $victim
        $receipt.actions[0].operation = 'create'
        $receipt | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

        $rollback = Invoke-RuleEstateRollback -ReceiptPath $receiptPath -ActionId ([string]$receipt.actions[0].action_id) -Token 'ROLLBACK_RULE_ESTATE_PATCH' -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $rollback.pass | Should Be $false
        @($rollback.findings.code) | Should Contain 'rollback_target_out_of_scope'
        [IO.File]::ReadAllText($victim) | Should Be 'keep'
    }

    It 'fails fast without rolling back earlier targets and exposes a bounded CLI plan' {
        $f = New-EstateMutationFixture
        $planPath = Join-Path $f.workspace 'estate-plan.json'
        $command = Invoke-RuleEstatePlanCommand @('--review',$f.review,'--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$planPath,'--json')
        $document = $command.output | ConvertFrom-Json
        $document.command | Should Be 'rule-estate-plan'
        $document.plan.actions.Count | Should Be 2

        $receiptPath = Join-Path $f.workspace 'failed-receipt.json'
        $secondId = [string]$document.plan.actions[1].action_id
        $result = Invoke-RuleEstateApply -Plan $document.plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token 'APPLY_RULE_ESTATE_PATCH' -ReceiptPath $receiptPath -TestFailBeforeActionId $secondId

        $result.pass | Should Be $false
        $result.writes | Should Be 1
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should Match 'improved'
        [IO.File]::ReadAllText((Join-Path $f.codex 'AGENTS.md')) | Should Match 'global codex'
        @($result.receipt.actions).Count | Should Be 1
    }
}
