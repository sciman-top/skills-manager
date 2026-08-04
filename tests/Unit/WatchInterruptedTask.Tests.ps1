Describe "watch-interrupted-task contract" {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        $skillPath = Join-Path $repoRoot "overrides\watch-interrupted-task\SKILL.md"
        $script:skill = Get-Content -Raw -LiteralPath $skillPath
    }

    It "classifies an unfinished context compaction as a continuation gap" {
        $script:skill | Should Match "continuation_gap"
        $script:skill | Should Match "contextCompaction"
        $script:skill | Should Match "no final"
        $script:skill | Should Match "continuous recovery session"
    }

    It "continues all remaining safe work instead of yielding after one slice" {
        $script:skill | Should Match "continue all remaining authorized safe work"
        $script:skill | Should Match "sequential bounded, verifiable slices"
        $script:skill | Should Match "Do not yield merely because"
        $script:skill | Should -Not -Match "Continue only one bounded"
        $script:skill | Should -Not -Match "Resume one bounded safe slice"
    }

    It "does not let an agent manufacture a natural pause during recovery" {
        $script:skill | Should Match "natural_pause only as a pre-existing explicit user handoff"
        $script:skill | Should Match "standing instructions to continue autonomously through completion"
        $script:skill | Should Match "do not yield or emit a final answer merely because one slice"
        $script:skill | Should Match "Once recovery starts, stop only at completion"
    }

    It "does not let an in-flight heartbeat overwrite a newer durable prompt" {
        $script:skill | Should Match "in-flight heartbeat must never overwrite a newer durable prompt"
        $script:skill | Should Match "Before self-pausing or resuming, re-read host automation metadata"
        $script:skill | Should Match "preserve any newer prompt"
    }

    It "keeps every shared-checkout heartbeat armed and deterministically serializes writers" {
        $script:skill | Should Match "peer_busy"
        $script:skill | Should Match "keep the heartbeat ACTIVE"
        $script:skill | Should Match "updatedAt.*thread id"
        $script:skill | Should Match "arm every eligible thread"
    }

    It "permits parallel recovery for isolated worktrees and evidenced read-only tasks" {
        $script:skill | Should Match "isolated worktrees"
        $script:skill | Should Match "read-only"
        $script:skill | Should Match "parallel"
    }

    It "keeps unknown fail-closed and external side effects outside automatic retry" {
        $script:skill | Should Match "unknown"
        $script:skill | Should Match "external side effects"
        $script:skill | Should Match "never replay"
    }
}
