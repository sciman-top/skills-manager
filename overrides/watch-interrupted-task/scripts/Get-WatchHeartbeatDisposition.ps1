[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'running',
        'resume_eligible',
        'continuation_gap',
        'peer_busy',
        'natural_pause',
        'needs_input',
        'complete',
        'non_transient_failure',
        'unknown',
        'stale_policy_running',
        'soft_guard_only'
    )]
    [string]$State
)

$result = [ordered]@{
    state = $State
    task_action = 'observe_only'
    automation_action = 'keep_active'
    mutation_owner = 'fleet_supervisor'
}

switch ($State) {
    'resume_eligible' {
        $result.task_action = 'recover'
        $result.mutation_owner = 'none'
    }
    'continuation_gap' {
        $result.task_action = 'recover'
        $result.mutation_owner = 'none'
    }
    'complete' {
        $result.automation_action = 'supervisor_cleanup'
    }
}

[pscustomobject]$result
