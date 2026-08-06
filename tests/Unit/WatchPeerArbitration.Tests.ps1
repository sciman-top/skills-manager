Describe 'watch shared-checkout peer arbitration' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:helper = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\Get-WatchPeerBusyDisposition.ps1'
    }

    It 'does not block on read-only external-wait or isolated-worktree peers' {
        Test-Path -LiteralPath $script:helper | Should Be $true
        $current = [ordered]@{ task_id='current'; repository_identity='repo-a'; checkout_identity='checkout-a'; operation_state='write_planning'; write_domain='working_tree' } | ConvertTo-Json -Compress
        $peers = @(
            [ordered]@{ task_id='reader'; repository_identity='repo-a'; checkout_identity='checkout-a'; operation_state='read_only'; write_domain='working_tree' },
            [ordered]@{ task_id='ci-wait'; repository_identity='repo-a'; checkout_identity='checkout-a'; operation_state='external_wait'; write_domain='external_effect' },
            [ordered]@{ task_id='isolated-writer'; repository_identity='repo-a'; checkout_identity='checkout-b'; operation_state='writing'; write_domain='working_tree' }
        ) | ConvertTo-Json -Compress

        $result = & $script:helper -CurrentOperationJson $current -PeerOperationsJson $peers
        $result.peer_busy | Should Be $false
        $result.reason_code | Should Be 'no_overlapping_writer'
        @($result.blocking_peer_ids).Count | Should Be 0
    }

    It 'blocks only overlapping write-capable work in the same checkout' {
        $current = [ordered]@{ task_id='current'; repository_identity='repo-a'; checkout_identity='checkout-a'; operation_state='write_planning'; write_domain='working_tree' } | ConvertTo-Json -Compress
        $peers = @(
            [ordered]@{ task_id='writer'; repository_identity='repo-a'; checkout_identity='checkout-a'; operation_state='writing'; write_domain='working_tree' },
            [ordered]@{ task_id='other-domain'; repository_identity='repo-a'; checkout_identity='checkout-a'; operation_state='writing'; write_domain='host_config' }
        ) | ConvertTo-Json -Compress

        $result = & $script:helper -CurrentOperationJson $current -PeerOperationsJson $peers
        $result.peer_busy | Should Be $true
        $result.reason_code | Should Be 'overlapping_writer'
        @($result.blocking_peer_ids) | Should Be @('writer')
    }

    It 'serializes common Git ref mutation across isolated worktrees of one repository' {
        $current = [ordered]@{ task_id='current'; repository_identity='repo-a'; checkout_identity='checkout-a'; operation_state='git_ref_mutation'; write_domain='git_refs' } | ConvertTo-Json -Compress
        $peers = @([ordered]@{ task_id='other-worktree'; repository_identity='repo-a'; checkout_identity='checkout-b'; operation_state='git_ref_mutation'; write_domain='git_refs' }) | ConvertTo-Json -Compress

        $result = & $script:helper -CurrentOperationJson $current -PeerOperationsJson $peers
        $result.peer_busy | Should Be $true
        @($result.blocking_peer_ids) | Should Be @('other-worktree')
    }

    It 'fails closed when checkout identity or operation schema is missing' {
        $current = [ordered]@{ task_id='current'; repository_identity='repo-a'; checkout_identity=''; operation_state='writing'; write_domain='working_tree' } | ConvertTo-Json -Compress
        $result = & $script:helper -CurrentOperationJson $current -PeerOperationsJson '[]'
        $result.peer_busy | Should Be $false
        $result.reason_code | Should Be 'identity_unproved'
        $result.classification | Should Be 'unknown'
    }
}
