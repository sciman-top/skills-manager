# Guards the TestDrive-leak reclaim contract.
#
# Root cause (2026-10-06): Pester deletes a test file's TestDrive only on a
# normal exit. A worker that is killed or that hits its wall-clock bound never
# runs that cleanup, so the whole TestDrive (one run can create thousands of
# directories) is leaked into %TEMP% forever. In a sandboxed host deletion is
# charged per directory node, so every leaked tree makes later runs slower --
# which is why "tests are slow" kept coming back after being "fixed".
#
# Two properties are load-bearing and are pinned here:
#
#   * tests/run.ps1 reclaims before it does any real work, in the parent process
#     only (workers must not re-reclaim), and a reclaim failure must never fail
#     the run;
#   * the reclaim script only ever touches '%TEMP%\Pester_*' entries, so it can
#     never delete unrelated user or tool files, and it uses no construct the
#     agent sandbox blocks (Add-Type) or that needs a runspace on a worker thread.
BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $runnerPath = Join-Path $repoRoot 'tests\run.ps1'
    $reclaimPath = Join-Path $repoRoot 'scripts\quality\reclaim-test-temp.ps1'
    $runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
    $reclaimText = Get-Content -LiteralPath $reclaimPath -Raw -Encoding UTF8
}

Describe 'TestDrive leak reclaim' {
    It 'ships the reclaim script the runner invokes' {
        Test-Path -LiteralPath $reclaimPath -PathType Leaf | Should -BeTrue
    }

    It 'is invoked by the runner before sharding or targeting work' {
        $runnerText | Should -Match 'reclaim-test-temp\.ps1'
        # The reclaim call must appear before the shard/targeted dispatch so the
        # backlog is cleared before any worker starts.
        $reclaimIndex = $runnerText.IndexOf('reclaim-test-temp.ps1')
        $shardIndex = $runnerText.IndexOf('ShardJobPath`)) {')
        $reclaimIndex | Should -BeGreaterThan -1
        if ($shardIndex -gt 0) { $reclaimIndex | Should -BeLessThan $shardIndex }
    }

    It 'skips the reclaim inside worker processes' {
        # Workers are spawned with -ShardJobPath / -TargetedJobPath; the guard
        # must be keyed on both so workers never re-reclaim concurrently.
        $runnerText | Should -Match 'IsNullOrWhiteSpace\(\$ShardJobPath\)'
        $runnerText | Should -Match 'IsNullOrWhiteSpace\(\$TargetedJobPath\)'
    }

    It 'never lets a reclaim failure fail the run' {
        # The reclaim call must sit inside a try/catch that only writes a message.
        $block = [regex]::Match($runnerText, '(?s)reclaim-test-temp\.ps1.*?catch \{.*?\}\s*\}')
        $block.Success | Should -BeTrue
        $block.Value | Should -Match 'catch'
        $block.Value | Should -Not -Match 'throw'
    }

    It 'only targets Pester_-prefixed entries in the user temp directory' {
        # The candidate filter must require the Pester_ prefix and exclude the
        # parking bin, so no unrelated file can ever be moved or deleted.
        $reclaimText | Should -Match "GetDirectories\(\`$tempRoot, 'Pester_\*'"
        $reclaimText | Should -Match '\$script:ParkPrefix'
        $reclaimText | Should -Match 'TopDirectoryOnly'
    }

    It 'parks by rename before deleting, and never blocks the caller unbounded' {
        # Parking (a rename) is what clears the active namespace; deletion is
        # bounded best-effort cleanup.
        $reclaimText | Should -Match '\[IO\.Directory\]::Move\('
        $reclaimText | Should -Match 'DeleteBudgetSeconds'
        $reclaimText | Should -Match 'TimeoutSeconds'
    }

    It 'does not depend on sandbox-blocked or runspace-bound constructs' {
        # Add-Type is blocked by the agent sandbox; a PowerShell scriptblock on a
        # background thread needs a runspace. The reclaim must use neither. Strip
        # comments first so the explanatory note that *names* these constructs
        # does not trip the check.
        $code = $reclaimText -replace '(?s)<#.*?#>', '' -replace '(?m)^\s*#.*$', ''
        $code | Should -Not -Match 'Add-Type'
        $code | Should -Not -Match 'Task\]::Run'
        $code | Should -Not -Match 'Start-ThreadJob|ForEach-Object -Parallel'
    }

    It 'clears read-only attributes before deleting a parked tree' {
        # Leaked trees are largely git fixtures whose loose object files are
        # read-only on Windows, which makes a recursive delete fail with
        # "Access to the path ... is denied".
        $reclaimText | Should -Match 'Clear-TreeReadOnly'
        $reclaimText | Should -Match 'ReadOnly'
    }

    It 'skips the reclaim on CI' {
        $reclaimText | Should -Match 'GITHUB_ACTIONS'
        $reclaimText | Should -Match 'Test-IsCi'
    }
}
