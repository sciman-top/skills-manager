BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
    . (Join-Path $repoRoot 'src\Application\RulePatchGuard.ps1')

}
Describe 'Rule patch apply guards' {
    BeforeAll {
function New-GuardFixture([string]$Name) {
        $root = Join-Path $TestDrive $Name; New-Item -ItemType Directory -Path $root -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $root '.skills-manager-fixture'), 'fixture')
        $path = Join-Path $root 'AGENTS.md'; [System.IO.File]::WriteAllText($path, 'before')
        $plan = New-RulePatchPlan -TargetPath $path -AuthorizedRoot $root -CurrentText before -DesiredText after -DesiredSource reviewed_file
        return [pscustomobject]@{ root = $root; path = $path; plan = $plan }
    }
}

    It 'accepts a fresh single target with explicit token inside fixture root' {
        $f = New-GuardFixture fresh; $result = Test-RulePatchApplyGuard $f.plan $f.root APPLY_RULE_PATCH
        $result.pass | Should -Be $true; $result.writes | Should -Be 0
    }

    It 'rejects stale content with zero writes' {
        $f = New-GuardFixture stale; [System.IO.File]::WriteAllText($f.path, 'changed'); $before = Get-FileHash $f.path
        $result = Test-RulePatchApplyGuard $f.plan $f.root APPLY_RULE_PATCH
        @($result.findings | Where-Object code -eq target_hash_stale).Count | Should -Be 1
        (Get-FileHash $f.path).Hash | Should -Be $before.Hash
    }

    It 'rejects invalid token and target outside explicit fixture root' {
        $f = New-GuardFixture outside; $other = Join-Path $TestDrive 'other'; New-Item -ItemType Directory $other -Force | Out-Null
        $result = Test-RulePatchApplyGuard $f.plan $other wrong
        @($result.findings | Where-Object code -eq apply_token_invalid).Count | Should -Be 1
        @($result.findings | Where-Object code -eq target_out_of_fixture_root).Count | Should -Be 1
    }

    It 'rejects drive root and missing target' {
        $f = New-GuardFixture missing; Remove-Item $f.path
        $drive = [System.IO.Path]::GetPathRoot($f.root)
        $result = Test-RulePatchApplyGuard $f.plan $drive APPLY_RULE_PATCH
        @($result.findings | Where-Object code -eq fixture_root_is_drive_root).Count | Should -Be 1
        @($result.findings | Where-Object code -eq target_missing).Count | Should -Be 1
    }

    It 'rejects tampered desired content' {
        $f = New-GuardFixture desired; $f.plan.desired_text = 'tampered'
        @((Test-RulePatchApplyGuard $f.plan $f.root APPLY_RULE_PATCH).findings | Where-Object code -eq desired_hash_mismatch).Count | Should -Be 1
    }

    It 'rejects an unmarked root even when every other guard passes' {
        $f = New-GuardFixture unmarked; Remove-Item -LiteralPath (Join-Path $f.root '.skills-manager-fixture')
        $result = Test-RulePatchApplyGuard $f.plan $f.root APPLY_RULE_PATCH
        @($result.findings | Where-Object code -eq fixture_marker_missing).Count | Should -Be 1
        $result.pass | Should -Be $false
    }
}
