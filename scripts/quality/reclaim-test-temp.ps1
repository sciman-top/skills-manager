#requires -Version 7.0
<#
Reclaims Pester TestDrive leftovers in the current user's temp directory.

Why this exists
---------------
Pester deletes a test file's TestDrive only when the run exits normally. A worker
that is killed or that hits the wall-clock bound never runs that cleanup, so the
entire TestDrive (one run can create thousands of directories) is leaked into
%TEMP% and is never reclaimed. Repeated interrupted runs therefore accumulate
unboundedly and make every later run slower.

Deleting those trees entry-by-entry is the expensive part of that cleanup, and in
a sandboxed host each delete is brokered per node. The win here is to do the
reclaim rarely and in bulk (once per run) instead of letting the backlog grow
without bound.

Strategy
--------
Deleting a leaked tree entry-by-entry is itself the expensive operation (measured
at ~0.15-0.63s per directory in a sandboxed host, up to several seconds when the
tree is nested and file-heavy), so the reclaim never puts deletion on the critical
path. It first *renames* every leftover out of the temp directory's active
namespace -- a metadata operation that is effectively free (measured 0.01s for a
420-entry tree) -- and only then deletes the parked trees inside a small,
hard-bounded budget.

Parking is the part that actually fixes the problem. Measured 2026-10-06: parking
35 leaked trees took well under a second, while deleting that same backlog removed
*zero* trees in 40s of sandboxed deletion. A parked tree no longer sits in `%TEMP%`
where a fresh Pester run enumerates and cleans around it, and `Pester_reclaim_*` is
excluded from the candidate set so it is never mistaken for an active TestDrive.
Deletion is therefore best-effort cleanup only; trees it cannot reach in time stay
parked and are retried by a later run.

Implementation note
-------------------
The delete phase is synchronous BCL (`[IO.Directory]::Delete`). Richer designs
were tried and rejected: an Add-Type C# worker is blocked by the agent sandbox
("compiles and loads .NET code at runtime"), and a background thread running a
PowerShell scriptblock fails with "There is no Runspace available to run scripts
in this thread". Since asynchronous deletion was measured to buy nothing, the
simple synchronous form is both correct and the only one that runs everywhere.

Deletion is bounded so the caller never waits on it indefinitely:

  * the parking loop is capped by `TimeoutSeconds`;
  * the delete loop is capped by `DeleteBudgetSeconds`.

Safety
------
Only sibling directories inside the current user's temp directory whose name
starts with 'Pester_' are considered, and parked trees live under a
'Pester_reclaim_' sibling so they can never be confused with an active TestDrive.
A candidate is skipped when it is too new to be a leftover (younger than
`MinAgeSeconds`) **or when it is still receiving writes** (see
`Test-TreeTouchedSince`): a concurrent run that has been executing for longer than
`MinAgeSeconds` is old but live, and parking it would silently destroy another
run's fixtures. The reclaim is best-effort: it never throws into the test run, and
it is skipped entirely on CI where a fresh temp directory needs no help.
#>
[CmdletBinding()]
param(
    # Leftovers younger than this are assumed to belong to a concurrently running
    # Pester invocation and are left alone.
    [int]$MinAgeSeconds = 120,
    # Bounds how long parking may take. On timeout, remaining items are skipped
    # and reported rather than blocking the caller.
    [int]$TimeoutSeconds = 60,
    # Bounds best-effort deletion of already-parked trees. Parking (rename) is
    # what clears the active namespace; deletion is opportunistic cleanup, so this
    # stays small on the test path. Trees not reached in time stay parked.
    [int]$DeleteBudgetSeconds = 5,
    # Diagnostic output path; empty writes nothing.
    [string]$LogPath = ''
)

$script:ParkPrefix = 'Pester_reclaim_'

$script:ReclaimLog = [System.Collections.Generic.List[string]]::new()
function Write-ReclaimLog([string]$Message) {
    $script:ReclaimLog.Add($Message) | Out-Null
}

function Test-IsCi {
    foreach ($name in 'CI', 'GITHUB_ACTIONS', 'TF_BUILD', 'BUILDKITE', 'TEAMCITY_VERSION') {
        if (-not [string]::IsNullOrWhiteSpace([string][Environment]::GetEnvironmentVariable($name))) { return $true }
    }
    return $false
}

# Recursive Directory.Delete fails on any read-only file inside the tree, and the
# leaked trees are mostly git fixtures whose loose object files are read-only on
# Windows. Clear the read-only attribute across the tree first (best effort: a
# file that cannot be inspected is simply left for the delete to report).
function Clear-TreeReadOnly([string]$Path) {
    $readOnly = [IO.FileAttributes]::ReadOnly
    try {
        $dirs = [IO.Directory]::GetDirectories($Path, '*', [IO.SearchOption]::AllDirectories)
    }
    catch { $dirs = @() }
    foreach ($dir in $dirs) {
        try {
            $attrs = [IO.File]::GetAttributes($dir)
            if ($attrs -band $readOnly) { [IO.File]::SetAttributes($dir, ($attrs -band (-bnot $readOnly))) }
        }
        catch { }
    }
    try {
        $files = [IO.Directory]::GetFiles($Path, '*', [IO.SearchOption]::AllDirectories)
    }
    catch { $files = @() }
    foreach ($file in $files) {
        try {
            $attrs = [IO.File]::GetAttributes($file)
            if ($attrs -band $readOnly) { [IO.File]::SetAttributes($file, ($attrs -band (-bnot $readOnly))) }
        }
        catch { }
    }
}

# A leftover tree is completely static; a tree owned by a concurrently running
# Pester invocation keeps receiving writes (fixtures, receipts, logs) while its
# tests execute. Creation age alone cannot tell them apart: a run that has been
# going for longer than MinAgeSeconds looks "old" even though it is still live.
# `[IO.Directory]::Move` cannot tell them apart either -- Pester holds no handle
# on the TestDrive directory itself, only on the files inside it, so parking a
# live tree succeeds and silently destroys another run's fixtures.
#
# Enumerate only (never delete) and treat "cannot inspect" as "possibly live",
# so the failure mode is a skipped reclaim rather than a broken concurrent run.
function Test-TreeTouchedSince([string]$Path, [datetime]$Since) {
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
            try {
                if ([IO.File]::GetLastWriteTimeUtc($file) -ge $Since) { return $true }
            }
            catch { return $true }
        }
    }
    catch { return $true }
    return $false
}

function Invoke-PesterTempReclaim {
    param(
        [int]$MinAgeSeconds = 120,
        [int]$TimeoutSeconds = 60,
        [int]$DeleteBudgetSeconds = 5
    )
    $result = [ordered]@{
        scanned         = 0
        live_skipped    = 0
        parked          = 0
        parked_skipped  = 0
        deleted         = 0
        delete_skipped  = 0
        delete_deferred = 0
        timed_out       = $false
        seconds         = 0.0
    }

    $tempRoot = [IO.Path]::GetTempPath()
    if ([string]::IsNullOrWhiteSpace($tempRoot) -or -not [IO.Directory]::Exists($tempRoot)) {
        return [pscustomobject]$result
    }

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $parkRoot = Join-Path $tempRoot ($script:ParkPrefix + 'bin')
    if (-not [IO.Directory]::Exists($parkRoot)) {
        try { $null = [IO.Directory]::CreateDirectory($parkRoot) } catch { }
    }

    $cutoff = (Get-Date).AddSeconds(-1 * [Math]::Max(0, $MinAgeSeconds))
    $cutoffUtc = $cutoff.ToUniversalTime()
    $candidates = @()
    try {
        $candidates = @(
            [IO.Directory]::GetDirectories($tempRoot, 'Pester_*', [IO.SearchOption]::TopDirectoryOnly) |
                ForEach-Object { [IO.DirectoryInfo]::new($_) } |
                Where-Object { $_.CreationTime -lt $cutoff -and $_.Name -notlike ($script:ParkPrefix + '*') }
        )
    }
    catch {
        Write-ReclaimLog("enumerate failed: $($_.Exception.Message)")
        return [pscustomobject]$result
    }
    $result.scanned = $candidates.Count

    # Age alone is not enough: a concurrent run that has been executing for longer
    # than MinAgeSeconds is old but still live. Drop any tree that is still being
    # written to, so a long-running sibling run never has its fixtures parked away.
    $candidates = @($candidates | Where-Object { -not (Test-TreeTouchedSince $_.FullName $cutoffUtc) })
    $result.live_skipped = $result.scanned - $candidates.Count
    if ($result.live_skipped -gt 0) {
        Write-ReclaimLog("skipped $($result.live_skipped) tree(s) still receiving writes (concurrent run)")
    }

    # Phase 1: park leftovers out of the active temp namespace. Rename is a pure
    # metadata operation and does not depend on the tree's size, so this is where
    # the backlog is actually cleared from the caller's point of view.
    foreach ($dir in $candidates) {
        if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            $result.timed_out = $true
            break
        }
        $parked = Join-Path $parkRoot $dir.Name
        try {
            if ([IO.Directory]::Exists($parked)) { $parked = "$parked-$([guid]::NewGuid().ToString('N').Substring(0, 8))" }
            [IO.Directory]::Move($dir.FullName, $parked)
            $result.parked++
        }
        catch {
            # A running Pester process holds this tree open; leave it alone.
            $result.parked_skipped++
        }
    }

    # Phase 2: best-effort, hard-bounded deletion of what is parked. Parking
    # already removed the backlog from the active temp namespace, so this phase is
    # opportunistic and must never delay the test run: it stops at
    # DeleteBudgetSeconds and leaves the rest parked for a later run. Deletion is
    # the sandbox-expensive step (measured ~0.15-0.63s per directory), so the
    # budget is small by default and the phase is expected to remove zero or a few
    # trees when the backlog is large -- that is the intended outcome, not a bug.
    #
    # Read-only attribute: the leaked trees are largely git fixtures, and git
    # marks loose object files read-only on Windows, which makes a recursive
    # Directory.Delete fail with "Access to the path ... is denied". Clearing the
    # attribute first is required for the delete to succeed at all.
    $deadline = (Get-Date).AddSeconds([Math]::Max(0, $DeleteBudgetSeconds))
    $parkedDirs = @()
    try { $parkedDirs = @([IO.Directory]::GetDirectories($parkRoot, 'Pester_*', [IO.SearchOption]::TopDirectoryOnly)) } catch { }
    foreach ($path in $parkedDirs) {
        if ((Get-Date) -ge $deadline) { $result.delete_deferred++; continue }
        try {
            Clear-TreeReadOnly -Path $path
            [IO.Directory]::Delete($path, $true)
            $result.deleted++
        }
        catch { $result.delete_skipped++ }
    }

    $timer.Stop()
    $result.seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
    return [pscustomobject]$result
}

$effectiveTimeout = [Math]::Max(1, $TimeoutSeconds)
$summary = $null
if (Test-IsCi) {
    Write-ReclaimLog('ci detected; reclaim skipped (fresh temp needs no help)')
    $summary = [pscustomobject][ordered]@{ scanned = 0; parked = 0; parked_skipped = 0; deleted = 0; delete_skipped = 0; delete_deferred = 0; timed_out = $false; seconds = 0.0 }
}
else {
    $summary = Invoke-PesterTempReclaim -MinAgeSeconds $MinAgeSeconds -TimeoutSeconds $effectiveTimeout -DeleteBudgetSeconds $DeleteBudgetSeconds
    Write-ReclaimLog(("scanned={0} parked={1} parked_skipped={2} deleted={3} delete_skipped={4} delete_deferred={5} timed_out={6} seconds={7}" -f `
                $summary.scanned, $summary.parked, $summary.parked_skipped, $summary.deleted, $summary.delete_skipped, $summary.delete_deferred, $summary.timed_out, $summary.seconds))
}

if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    try {
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($LogPath), ($script:ReclaimLog -join [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    }
    catch { }
}

$summary
