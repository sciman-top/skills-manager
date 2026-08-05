function Parse-AgentWorkflowCommandOptions([object[]]$Tokens) {
    $result = [ordered]@{ input_path = $null; json = $false }
    for ($i = 0; $i -lt @($Tokens).Count; $i++) {
        $token = ([string]$Tokens[$i]).ToLowerInvariant()
        switch ($token) {
            '--input' { if ($i + 1 -ge @($Tokens).Count) { throw '--input requires a JSON file path.' }; $i++; $result.input_path = [string]$Tokens[$i] }
            '--json' { $result.json = $true }
            default { throw ('Unknown agent workflow option: {0}' -f [string]$Tokens[$i]) }
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$result.input_path)) { throw '--input is required.' }
    return [pscustomobject]$result
}

function Read-AgentWorkflowRequest([string]$InputPath) {
    $fullPath = [IO.Path]::GetFullPath($InputPath)
    if (-not (Test-OperationPathWithinRoot $fullPath $Root)) { throw 'Agent workflow input must remain inside the repository root.' }
    if (-not [IO.File]::Exists($fullPath)) { throw ('Agent workflow input does not exist: {0}' -f $fullPath) }
    return [IO.File]::ReadAllText($fullPath) | ConvertFrom-Json
}

function New-AgentWorkflowCommandResult([string]$Command, [bool]$Json, $Data, [bool]$Pass) {
    $envelope = [pscustomobject][ordered]@{
        schema_version = 1; command = $Command; pass = $Pass; truth_boundary = 'repo_advisory_only'; decision_owner = 'host_ai'; executor = 'host_native_runtime'
        provider_calls = 0; native_mutations = 0; writes = 0; data = $Data
    }
    $output = if ($Json) { $envelope | ConvertTo-Json -Depth 50 -Compress } else { '{0}: pass={1}; findings={2}; writes=0; provider_calls=0' -f $Command, $Pass, @((Get-OperationObjectProperty $Data 'findings')).Count }
    return [pscustomobject]@{ exit_code = $(if ($Pass) { 0 } else { 2 }); output = $output; json = $Json; envelope = $envelope }
}

function Invoke-AgentValidateCommand([object[]]$Tokens = @()) {
    $options = Parse-AgentWorkflowCommandOptions $Tokens
    $request = Read-AgentWorkflowRequest $options.input_path
    $validation = Test-AgentWorkflowRequest $request
    return New-AgentWorkflowCommandResult 'agent-validate' ([bool]$options.json) $validation ([bool]$validation.pass)
}

function Invoke-AgentPlanCommand([object[]]$Tokens = @()) {
    $options = Parse-AgentWorkflowCommandOptions $Tokens
    $request = Read-AgentWorkflowRequest $options.input_path
    $plan = New-AgentWorkflowAdvisoryPlan $request
    return New-AgentWorkflowCommandResult 'agent-plan' ([bool]$options.json) $plan ([bool]$plan.pass)
}
