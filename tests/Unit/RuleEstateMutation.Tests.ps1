BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleEstate.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleEstateMutation.ps1')
    . (Join-Path $repoRoot 'src\Commands\RuleEstate.ps1')

}
Describe 'Reviewed rule estate mutation' {
    BeforeAll {
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
}

    It 'rejects AI self-reviewed manifests and forbidden target surfaces' {
        $f = New-EstateMutationFixture
        $review = [IO.File]::ReadAllText($f.review) | ConvertFrom-Json
        $review.reviewed_by_type = 'ai'
        $validation = Test-RuleEstateReviewContract $review ([IO.Path]::GetDirectoryName($f.review))
        $validation.pass | Should -Be $false
        @($validation.findings.code) | Should -Contain 'review_authority_invalid'

        $review.reviewed_by_type = 'human'
        $review.changes[0].target_file = '.codex/config.toml'
        $validation = Test-RuleEstateReviewContract $review ([IO.Path]::GetDirectoryName($f.review))
        @($validation.findings.code) | Should -Contain 'target_file_forbidden'
    }

    It 'rejects desired files reached through a review-root junction' {
        $f = New-EstateMutationFixture
        $outside = Join-Path $TestDrive ('review-outside-' + [guid]::NewGuid().ToString('N'))
        $link = Join-Path ([IO.Path]::GetDirectoryName($f.review)) 'linked'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'desired.md') -Value '# outside'
        cmd /c "mklink /J `"$link`" `"$outside`"" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'junction fixture creation failed' }

        $review = [IO.File]::ReadAllText($f.review) | ConvertFrom-Json
        $review.changes[0].desired_file = 'linked/desired.md'
        $validation = Test-RuleEstateReviewContract $review ([IO.Path]::GetDirectoryName($f.review))

        $validation.pass | Should -Be $false
        @($validation.findings.code) | Should -Contain 'desired_file_reparse_forbidden'
    }

    It 'plans exact global and discovered repository targets without mutation' {
        $f = New-EstateMutationFixture
        $beforeRepo = [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md'))
        $beforeGlobal = [IO.File]::ReadAllText((Join-Path $f.codex 'AGENTS.md'))
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        $plan.actions.Count | Should -Be 2
        $plan.target_set.paths.Count | Should -Be 2
        $plan.apply.required_token | Should -Match '^APPLY_RULE_ESTATE_PATCH_[A-F0-9]{16}$'
        $plan.apply.confirmation | Should -Be 'plan_bound_explicit'
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should -Be $beforeRepo
        [IO.File]::ReadAllText((Join-Path $f.codex 'AGENTS.md')) | Should -Be $beforeGlobal
    }

    It 'allows unrelated dirty paths but fails closed on target drift, target-set drift, and locks' {
        $f = New-EstateMutationFixture
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        Set-Content -LiteralPath (Join-Path $f.repo_a 'unrelated.txt') -Value 'preserve me'
        $preflight = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        $preflight.pass | Should -Be $true
        @($preflight.findings.code) | Should -Not -Contain 'repository_dirty'
        @($plan.actions | Where-Object repository -eq 'repo-a')[0].dirty_paths_at_plan | Should -BeNullOrEmpty
        $observedPlan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        (@($observedPlan.actions | Where-Object repository -eq 'repo-a')[0].dirty_paths_at_plan -join "`n") | Should -Match 'unrelated\.txt'

        Add-Content -LiteralPath (Join-Path $f.repo_a 'AGENTS.md') -Value 'dirty'
        $preflight = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        @($preflight.findings.code) | Should -Contain 'target_hash_stale'

        git -C $f.repo_a checkout -- AGENTS.md
        New-Item -ItemType Directory -Path (Join-Path $f.workspace 'repo-c\.git') -Force | Out-Null
        $preflight = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        @($preflight.findings.code) | Should -Contain 'target_set_drift'

        Remove-Item -LiteralPath (Join-Path $f.workspace 'repo-c') -Recurse -Force
        Set-Content -LiteralPath (Join-Path $f.repo_a '.skills-manager-rule-estate.lock') -Value 'held'
        $preflight = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        @($preflight.findings.code) | Should -Contain 'target_locked'
    }

    It 'applies one by one, persists receipts, resumes, and rolls back one target' {
        $f = New-EstateMutationFixture
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $receiptPath = Join-Path $f.workspace 'estate-receipt.json'
        $result = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token $plan.apply.required_token -ReceiptPath $receiptPath

        if (-not $result.pass) { throw ($result | ConvertTo-Json -Depth 20) }
        $result.pass | Should -Be $true
        $result.receipt.actions.Count | Should -Be 2
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should -Match 'improved'
        Test-Path -LiteralPath $receiptPath | Should -Be $true

        $resumed = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token $plan.apply.required_token -ReceiptPath $receiptPath -ResumeReceiptPath $receiptPath
        $resumed.pass | Should -Be $true
        $resumed.writes | Should -Be 0

        $actionId = [string]$result.receipt.actions[0].action_id
        $rollback = Invoke-RuleEstateRollback -ReceiptPath $receiptPath -ActionId $actionId -Token 'ROLLBACK_RULE_ESTATE_PATCH' -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $rollback.pass | Should -Be $true
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should -Match '# repo-a'
    }

    It 'deduplicates locks for multiple actions under the same authorized root' {
        $f = New-EstateMutationFixture
        $review = [IO.File]::ReadAllText($f.review) | ConvertFrom-Json
        $reviewRoot = [IO.Path]::GetDirectoryName($f.review)
        Set-Content -LiteralPath (Join-Path $reviewRoot 'repo-a-claude.desired.md') -Value '# repo-a claude improved'
        $review.changes += [pscustomobject]@{ target_scope='repository'; repository='repo-a'; target_file='CLAUDE.md'; desired_file='repo-a-claude.desired.md'; allow_create=$true; risk='medium'; evidence_refs=@('fixture') }
        $review | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $f.review -Encoding UTF8
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        $result = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token $plan.apply.required_token -ReceiptPath (Join-Path $f.workspace 'same-root-receipt.json')

        if (-not $result.pass) { throw ($result | ConvertTo-Json -Depth 20) }
        $result.pass | Should -Be $true
        $result.writes | Should -Be 3
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'CLAUDE.md')) | Should -Match 'improved'
    }

    It 'rechecks target freshness after locks are acquired and before the first write' {
        $f = New-EstateMutationFixture
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $target = Join-Path $f.repo_a 'AGENTS.md'
        $hook = { Set-Content -LiteralPath $target -Value '# concurrent owner change' }.GetNewClosure()

        $result = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token $plan.apply.required_token -ReceiptPath (Join-Path $f.workspace 'toctou-receipt.json') -TestHookAfterLocksAcquired $hook

        $result.pass | Should -Be $false
        $result.writes | Should -Be 0
        [IO.File]::ReadAllText($target) | Should -Match 'concurrent owner change'
    }

    It 'rejects plan actions that no longer exactly project the authorized review' {
        $f = New-EstateMutationFixture
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $plan.actions[0].desired_text = '# unauthorized replacement'
        $plan.actions[0].desired_hash = Get-OperationSha256 ([string]$plan.actions[0].desired_text)
        $plan.actions[0].action_id = 'estate-' + (Get-OperationSha256 'tampered').Substring(0,16)

        $result = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token $plan.apply.required_token -ReceiptPath (Join-Path $f.workspace 'tampered-plan-receipt.json')

        $result.pass | Should -Be $false
        $result.writes | Should -Be 0
        @($result.findings.code) | Should -Contain 'plan_review_binding_mismatch'
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should -Match '# repo-a'
    }

    It 'rejects rollback when the recorded backup has been modified' {
        $f = New-EstateMutationFixture
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $receiptPath = Join-Path $f.workspace 'backup-integrity-receipt.json'
        $result = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token $plan.apply.required_token -ReceiptPath $receiptPath
        $action = @($result.receipt.actions)[0]
        Set-Content -LiteralPath ([string]$action.backup_path) -Value 'tampered backup'

        $rollback = Invoke-RuleEstateRollback -ReceiptPath $receiptPath -ActionId ([string]$action.action_id) -Token 'ROLLBACK_RULE_ESTATE_PATCH' -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        $rollback.pass | Should -Be $false
        @($rollback.findings.code) | Should -Contain 'rollback_backup_stale'
        [IO.File]::ReadAllText(([string]$action.target_path)) | Should -Match 'improved'
    }

    It 'rejects drive-root authorization and tampered rollback targets' {
        $f = New-EstateMutationFixture
        { New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot ([IO.Path]::GetPathRoot($f.codex)) -ClaudeUserRoot $f.claude } | Should -Throw

        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $receiptPath = Join-Path $f.workspace 'tampered-receipt.json'
        $result = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token $plan.apply.required_token -ReceiptPath $receiptPath
        $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
        $victim = Join-Path $f.repo_a 'victim.txt'; [IO.File]::WriteAllText($victim, 'keep')
        $receipt.actions[0].target_path = $victim
        $receipt.actions[0].operation = 'create'
        $receipt | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $receiptPath -Encoding UTF8

        $rollback = Invoke-RuleEstateRollback -ReceiptPath $receiptPath -ActionId ([string]$receipt.actions[0].action_id) -Token 'ROLLBACK_RULE_ESTATE_PATCH' -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $rollback.pass | Should -Be $false
        @($rollback.findings.code) | Should -Contain 'rollback_target_out_of_scope'
        [IO.File]::ReadAllText($victim) | Should -Be 'keep'
    }

    It 'fails fast without rolling back earlier targets and exposes a bounded CLI plan' {
        $f = New-EstateMutationFixture
        $planPath = Join-Path $f.workspace 'estate-plan.json'
        $command = Invoke-RuleEstatePlanCommand @('--review',$f.review,'--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$planPath,'--json')
        $document = $command.output | ConvertFrom-Json
        $document.command | Should -Be 'rule-estate-plan'
        $document.plan.actions.Count | Should -Be 2

        $receiptPath = Join-Path $f.workspace 'failed-receipt.json'
        $secondId = [string]$document.plan.actions[1].action_id
        $result = Invoke-RuleEstateApply -Plan $document.plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token $document.plan.apply.required_token -ReceiptPath $receiptPath -TestFailBeforeActionId $secondId

        $result.pass | Should -Be $false
        $result.writes | Should -Be 1
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should -Match 'improved'
        [IO.File]::ReadAllText((Join-Path $f.codex 'AGENTS.md')) | Should -Match 'global codex'
        @($result.receipt.actions).Count | Should -Be 1
    }

    It 'rejects plan and apply outputs reached through a workspace junction before mutation' {
        $f = New-EstateMutationFixture
        $outside = Join-Path $TestDrive ('control-outside-' + [guid]::NewGuid().ToString('N'))
        $link = Join-Path $f.workspace 'linked-output'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        cmd /c "mklink /J `"$link`" `"$outside`"" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'junction fixture creation failed' }

        $outsidePlan = Join-Path $link 'estate-plan.json'
        { Invoke-RuleEstatePlanCommand @('--review',$f.review,'--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$outsidePlan,'--json') } | Should -Throw
        Test-Path -LiteralPath (Join-Path $outside 'estate-plan.json') | Should -Be $false

        $planPath = Join-Path $f.workspace 'estate-plan.json'
        $planCommand = Invoke-RuleEstatePlanCommand @('--review',$f.review,'--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$planPath,'--json')
        $plan = ($planCommand.output | ConvertFrom-Json).plan
        $beforeRepo = [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md'))
        $outsideReceipt = Join-Path $link 'estate-receipt.json'

        { Invoke-RuleEstateApplyCommand @('--plan',$planPath,'--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--token',$plan.apply.required_token,'--out',$outsideReceipt,'--json') } | Should -Throw
        [IO.File]::ReadAllText((Join-Path $f.repo_a 'AGENTS.md')) | Should -Be $beforeRepo
        Test-Path -LiteralPath (Join-Path $outside 'estate-receipt.json') | Should -Be $false
        @($plan.actions).Count | Should -Be 2
    }

    It 'rejects plan and apply outputs that overwrite reviewed inputs or target rules' {
        $f = New-EstateMutationFixture
        $review = [IO.File]::ReadAllText($f.review) | ConvertFrom-Json
        $desiredPath = Join-Path ([IO.Path]::GetDirectoryName($f.review)) ([string]$review.changes[0].desired_file)
        $desiredBefore = [IO.File]::ReadAllText($desiredPath)
        { Invoke-RuleEstatePlanCommand @('--review',$f.review,'--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$desiredPath,'--json') } | Should -Throw
        [IO.File]::ReadAllText($desiredPath) | Should -Be $desiredBefore

        $f = New-EstateMutationFixture
        $planPath = Join-Path $f.workspace 'estate-plan.json'
        Invoke-RuleEstatePlanCommand @('--review',$f.review,'--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$planPath,'--json') | Out-Null
        $targetPath = Join-Path $f.repo_a 'AGENTS.md'
        $targetBefore = [IO.File]::ReadAllText($targetPath)
        $plan = [IO.File]::ReadAllText($planPath) | ConvertFrom-Json
        { Invoke-RuleEstateApplyCommand @('--plan',$planPath,'--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--token',$plan.apply.required_token,'--out',$targetPath,'--json') } | Should -Throw
        [IO.File]::ReadAllText($targetPath) | Should -Be $targetBefore
    }

    It 'binds confirmation to the exact reviewed plan and roots' {
        $f = New-EstateMutationFixture
        $plan = New-RuleEstatePlan -ReviewPath $f.review -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $wrong = Invoke-RuleEstateApply -Plan $plan -WorkspaceRoot $f.workspace -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude -Token 'APPLY_RULE_ESTATE_PATCH_0000000000000000' -ReceiptPath (Join-Path $f.workspace 'wrong-token.json')
        @($wrong.findings.code) | Should -Contain 'apply_token_invalid'

        Add-Content -LiteralPath $f.review -Value ' '
        $stale = Test-RuleEstateApplyPreflight $plan $f.workspace $f.codex $f.claude
        @($stale.findings.code) | Should -Contain 'review_stale'
    }
}
