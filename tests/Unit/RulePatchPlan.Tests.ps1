$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1')

Describe 'RulePatchPlan v1 contract' {
    It 'constructs stable single-target plan and unified diff' {
        $path = Join-Path $TestDrive 'fixture\AGENTS.md'; $root = Split-Path $path -Parent
        $a = New-RulePatchPlan -TargetPath $path -AuthorizedRoot $root -CurrentText 'before' -DesiredText 'after' -DesiredSource reviewed_file -FindingIds @('b', 'a')
        $b = New-RulePatchPlan -TargetPath $path -AuthorizedRoot $root -CurrentText 'before' -DesiredText 'after' -DesiredSource reviewed_file -FindingIds @('a', 'b')
        (Test-RulePatchPlanContract $a).pass | Should Be $true
        $a.patch_id | Should Be $b.patch_id
        ($a | ConvertTo-Json -Depth 20 -Compress) | Should Be ($b | ConvertTo-Json -Depth 20 -Compress)
        $a.diff.content | Should Match '^--- a/AGENTS\.md'
    }

    It 'represents no-change without a misleading diff' {
        $plan = New-RulePatchPlan -TargetPath (Join-Path $TestDrive 'a.md') -AuthorizedRoot $TestDrive -CurrentText same -DesiredText same -DesiredSource explicit_user_input
        $plan.diff.has_changes | Should Be $false
        $plan.diff.content | Should Be ''
    }

    It 'rejects semantic recommendation as desired source' {
        $plan = New-RulePatchPlan -TargetPath (Join-Path $TestDrive 'a.md') -AuthorizedRoot $TestDrive -CurrentText a -DesiredText b -DesiredSource semantic_recommendation
        $result = Test-RulePatchPlanContract $plan
        @($result.findings | Where-Object code -eq desired_source_not_authorized).Count | Should Be 1
    }

    It 'rejects sensitive desired content before serialization' {
        $plan = New-RulePatchPlan -TargetPath (Join-Path $TestDrive 'a.md') -AuthorizedRoot $TestDrive -CurrentText a -DesiredText 'Authorization: Bearer fixture-secret' -DesiredSource reviewed_file
        @((Test-RulePatchPlanContract $plan).findings | Where-Object code -eq sensitive_content_present).Count | Should Be 1
    }

    It 'fails closed when bounded diff size is exceeded' {
        { New-RulePatchPlan -TargetPath (Join-Path $TestDrive 'a.md') -AuthorizedRoot $TestDrive -CurrentText ('a' * 20) -DesiredText ('b' * 20) -DesiredSource reviewed_file -MaxDiffChars 10 } | Should Throw
    }

    It 'keeps planner free of file IO and parses in Windows PowerShell 5.1' {
        $source = Get-Content (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1') -Raw
        $source | Should Not Match '(?im)^\s*(Get-Content|Set-Content|Remove-Item|Copy-Item|Move-Item|Write-Host|Invoke-WebRequest)\b'
        $op = (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1').Replace("'", "''"); $patch = (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1').Replace("'", "''")
        $output = @(& powershell.exe -NoProfile -Command ". '$op'; . '$patch'; (New-RulePatchPlan -TargetPath 'C:\fixture\a.md' -AuthorizedRoot 'C:\fixture' -CurrentText a -DesiredText b -DesiredSource reviewed_file).schema_version" 2>&1)
        $LASTEXITCODE | Should Be 0; ($output -join '').Trim() | Should Be '1'
    }
}
