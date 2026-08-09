$hostCapabilityAdaptersRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }

if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) {
    . (Join-Path $hostCapabilityAdaptersRepoRoot 'src\Domain\OperationPlan.ps1')
}
if ($null -eq (Get-Command New-HostCapabilitySnapshot -ErrorAction SilentlyContinue)) {
    . (Join-Path $hostCapabilityAdaptersRepoRoot 'src\Domain\HostCapabilitySnapshot.ps1')
}
if ($null -eq (Get-Command Resolve-HostCapabilitySnapshot -ErrorAction SilentlyContinue)) {
    . (Join-Path $hostCapabilityAdaptersRepoRoot 'src\Application\HostCapabilityResolution.ps1')
}

function Get-HostCapabilityAdapterProperty {
    param(
        $Object,
        [string[]]$Names
    )

    foreach ($name in @($Names)) {
        if (Test-OperationObjectProperty $Object $name) {
            return Get-OperationObjectProperty $Object $name
        }
    }
    return $null
}

function Get-HostCapabilityAdapterResponseBody {
    param($Response)

    if ($null -eq $Response) { return $null }
    if (Test-OperationObjectProperty $Response 'result') {
        return Get-OperationObjectProperty $Response 'result'
    }
    return $Response
}

function Get-HostCapabilityAdapterResponseError {
    param(
        $Response,
        [Parameter(Mandatory = $true)][string]$Method
    )

    if ($null -eq $Response -or -not (Test-OperationObjectProperty $Response 'error')) { return $null }
    $error = Get-OperationObjectProperty $Response 'error'
    $message = if ($error -is [string]) { [string]$error } else { [string](Get-HostCapabilityAdapterProperty $error @('message', 'detail', 'code')) }
    if ([string]::IsNullOrWhiteSpace($message)) { $message = 'App Server returned an error without a diagnostic message.' }
    $message = Protect-OperationSensitiveString (($message -replace '\s+', ' ').Trim())
    if ($message.Length -gt 240) { $message = $message.Substring(0, 240) }
    return [pscustomobject][ordered]@{ method = $Method; message = $message }
}

function Get-HostCapabilityAdapterRows {
    param($Response, [string[]]$CollectionNames)

    $body = Get-HostCapabilityAdapterResponseBody $Response
    foreach ($name in @($CollectionNames)) {
        if (Test-OperationObjectProperty $body $name) {
            $value = Get-OperationObjectProperty $body $name
            if ($null -eq $value) { return @() }
            return @($value)
        }
    }
    if ($null -eq $body) { return @() }
    if (Test-OperationArray $body) { return @($body) }
    return @($body)
}

function New-HostCapabilityAdapterCandidate {
    param(
        $Value,
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [string]$UnknownReason
    )

    return [pscustomobject][ordered]@{
        value = $Value
        captured_at = $CapturedAt
        freshness = if ($null -eq $Value) { 'unknown' } else { 'fresh' }
        unknown_reason = if ($null -eq $Value) { $UnknownReason } else { $null }
    }
}

function Add-HostCapabilityAdapterMetadata {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$Adapter,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Status,
        $Coverage = [pscustomobject]@{},
        [object[]]$Errors = @()
    )

    $Snapshot | Add-Member -NotePropertyName adapter -NotePropertyValue $Adapter
    $Snapshot | Add-Member -NotePropertyName source -NotePropertyValue $Source
    $Snapshot | Add-Member -NotePropertyName adapter_source -NotePropertyValue $Source
    $Snapshot | Add-Member -NotePropertyName status -NotePropertyValue $Status
    $Snapshot | Add-Member -NotePropertyName coverage -NotePropertyValue $Coverage
    $Snapshot | Add-Member -NotePropertyName errors -NotePropertyValue @($Errors)
    $Snapshot | Add-Member -NotePropertyName read_only -NotePropertyValue $true
    $Snapshot | Add-Member -NotePropertyName provider_calls -NotePropertyValue 0
    $Snapshot | Add-Member -NotePropertyName writes -NotePropertyValue 0
    $Snapshot | Add-Member -NotePropertyName native_mutations -NotePropertyValue 0
    return $Snapshot
}

function New-HostCapabilityUnknownAdapterSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Adapter,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$UnknownReason,
        [switch]$PlatformNa
    )

    $fallback = [pscustomobject]@{
        model = [pscustomobject]@{ value = $null; freshness = 'unknown'; unknown_reason = if ($UnknownReason) { $UnknownReason } else { 'effective_model_unknown' } }
        context_window = [pscustomobject]@{ value = $null; freshness = 'unknown'; unknown_reason = 'context_window_unknown' }
        metadata_budget = [pscustomobject]@{ value = $null; freshness = 'unknown'; unknown_reason = 'metadata_budget_unknown' }
        skills_inventory = [pscustomobject]@{ value = $null; freshness = 'unknown'; unknown_reason = 'skills_inventory_unknown' }
    }
    $snapshot = Resolve-HostCapabilitySnapshot -Surface $Surface -CapturedAt $CapturedAt -UnknownFallback $fallback
    if (-not [string]::IsNullOrWhiteSpace($UnknownReason)) {
        $snapshot.unknown_reasons = @($snapshot.unknown_reasons + $UnknownReason | Sort-Object -Unique)
    }
    $result = Add-HostCapabilityAdapterMetadata -Snapshot $snapshot -Adapter $Adapter -Source $Source -Status $Status
    $result | Add-Member -NotePropertyName platform_na -NotePropertyValue ([bool]$PlatformNa)
    return $result
}

function Test-HostCapabilityAdapterContract {
    param($Snapshot)

    $findings = New-Object System.Collections.Generic.List[object]
    $baseResult = Test-HostCapabilitySnapshotContract $Snapshot
    foreach ($finding in @($baseResult.findings)) { $findings.Add($finding) | Out-Null }
    if ($null -eq $Snapshot) { return New-OperationValidationResult $findings.ToArray() }

    $adapter = [string](Get-OperationObjectProperty $Snapshot 'adapter')
    $source = [string](Get-OperationObjectProperty $Snapshot 'source')
    $status = [string](Get-OperationObjectProperty $Snapshot 'status')
    if ($adapter -notin @('app_server', 'cli', 'offline_config')) { $findings.Add((New-OperationFinding 'adapter_invalid' 'error' '$.adapter' 'Adapter must be app_server, cli or offline_config.')) | Out-Null }
    if ($source -notin @('app_server', 'cli', 'config_fallback')) { $findings.Add((New-OperationFinding 'adapter_source_invalid' 'error' '$.source' 'Adapter source is not supported.')) | Out-Null }
    if ($status -notin @('complete', 'partial', 'platform_na', 'unknown')) { $findings.Add((New-OperationFinding 'adapter_status_invalid' 'error' '$.status' 'Adapter status is not supported.')) | Out-Null }
    if ($null -eq (Get-OperationObjectProperty $Snapshot 'coverage')) { $findings.Add((New-OperationFinding 'adapter_coverage_missing' 'error' '$.coverage' 'Adapter coverage is required.')) | Out-Null }
    if ((Get-OperationObjectProperty $Snapshot 'read_only') -ne $true) { $findings.Add((New-OperationFinding 'adapter_read_only_required' 'error' '$.read_only' 'Adapters must declare read_only=true.')) | Out-Null }
    foreach ($field in @('provider_calls', 'writes', 'native_mutations')) {
        $value = Get-OperationObjectProperty $Snapshot $field
        $number = 0L
        if ($null -eq $value -or -not [long]::TryParse([string]$value, [ref]$number) -or $number -ne 0) {
            $code = 'adapter_{0}_forbidden' -f $field
            $findings.Add((New-OperationFinding $code 'error' ('$.{0}' -f $field) ('Adapter {0} must remain zero.' -f $field))) | Out-Null
        }
    }
    if ($source -eq 'config_fallback') {
        foreach ($name in Get-HostCapabilitySnapshotCapabilityNames) {
            $fact = Get-OperationObjectProperty (Get-OperationObjectProperty $Snapshot 'capabilities') $name
            if ([string](Get-OperationObjectProperty $fact 'source') -eq 'config_fallback') {
                $findings.Add((New-OperationFinding 'adapter_fallback_fact_source_invalid' 'error' ('$.capabilities.{0}.source' -f $name) 'Config fallback must remain visible at adapter level and cannot become a runtime fact source.')) | Out-Null
            }
        }
    }
    $serialized = $Snapshot | ConvertTo-Json -Depth 40 -Compress
    if (Test-OperationSerializedSensitiveValue $serialized) { $findings.Add((New-OperationFinding 'adapter_sensitive_value_present' 'error' '$' 'Adapter output contains an unredacted sensitive value.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}

function New-HostCapabilitySnapshotFromCli {
    [CmdletBinding()]
    param(
        $PromptInput,
        [string]$Surface = 'cli',
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [string]$ThreadId,
        [string]$TurnId,
        [bool]$ExecutableAvailable = $true,
        [string]$UnavailableReason = 'cli_unavailable_platform_na'
    )

    if (-not $ExecutableAvailable) {
        return New-HostCapabilityUnknownAdapterSnapshot -Adapter 'cli' -Source 'cli' -Surface $Surface -CapturedAt $CapturedAt -Status 'platform_na' -UnknownReason $UnavailableReason -PlatformNa
    }

    $inputValue = $PromptInput
    $errors = New-Object System.Collections.Generic.List[object]
    if ($inputValue -is [string]) {
        try { $inputValue = $inputValue | ConvertFrom-Json -ErrorAction Stop }
        catch { $errors.Add([pscustomobject]@{ code = 'cli_prompt_input_invalid_json'; message = 'CLI prompt-input was not valid JSON; text parsing continued.' }) | Out-Null }
    }

    $model = Get-HostCapabilityAdapterProperty $inputValue @('model', 'model_id', 'modelId')
    $contextWindow = Get-HostCapabilityAdapterProperty $inputValue @('context_window', 'model_context_window', 'contextWindow', 'modelContextWindow')
    $metadataBudget = Get-HostCapabilityAdapterProperty $inputValue @('metadata_budget', 'metadataBudget', 'skill_metadata_budget', 'skillMetadataBudget')
    $directSkills = Get-HostCapabilityAdapterProperty $inputValue @('skills_inventory', 'skills')
    $skillRows = @()
    if ($null -ne $directSkills) {
        $skillRows = @(Get-HostCapabilityAdapterRows $directSkills @('data', 'skills'))
    }

    $texts = New-Object System.Collections.Generic.List[string]
    function Add-HostCapabilityCliText($Value) {
        if ($null -eq $Value) { return }
        if ($Value -is [string]) { $texts.Add([string]$Value) | Out-Null; return }
        if (Test-OperationArray $Value) {
            foreach ($item in @($Value)) { Add-HostCapabilityCliText $item }
            return
        }
        $content = Get-HostCapabilityAdapterProperty $Value @('content')
        if ($null -ne $content) { Add-HostCapabilityCliText $content }
        $text = Get-HostCapabilityAdapterProperty $Value @('text')
        if ($null -ne $text) { Add-HostCapabilityCliText $text }
    }
    Add-HostCapabilityCliText $inputValue
    $combinedText = $texts -join "`n"
    if ($skillRows.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($combinedText)) {
        $sectionMatch = [regex]::Match($combinedText, '(?ms)###\s*Available skills\s*(?<section>.*?)(?:\r?\n###|\z)')
        if ($sectionMatch.Success) {
            foreach ($line in ($sectionMatch.Groups['section'].Value -split "`r?`n")) {
                $itemMatch = [regex]::Match($line, '^\s*-\s+(?<name>[A-Za-z0-9][A-Za-z0-9_.:-]*):\s*(?<description>.+?)\s*$')
                if ($itemMatch.Success) {
                    $skillRows += [pscustomobject][ordered]@{
                        name = $itemMatch.Groups['name'].Value
                        description = $itemMatch.Groups['description'].Value.Trim()
                        enabled = $true
                        availability = 'available'
                    }
                }
            }
        }
    }

    $inventory = @($skillRows | ForEach-Object {
        $name = [string](Get-HostCapabilityAdapterProperty $_ @('name', 'id', 'skill'))
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        [pscustomobject][ordered]@{
            name = $name
            description = [string](Get-HostCapabilityAdapterProperty $_ @('description', 'summary'))
            enabled = if (Test-OperationObjectProperty $_ 'enabled') { [bool](Get-OperationObjectProperty $_ 'enabled') } else { $true }
            availability = if (Test-OperationObjectProperty $_ 'availability') { [string](Get-OperationObjectProperty $_ 'availability') } else { 'available' }
        }
    })
    $runtime = [pscustomobject]@{
        model = New-HostCapabilityAdapterCandidate $model $CapturedAt 'cli_model_unknown'
        context_window = New-HostCapabilityAdapterCandidate $contextWindow $CapturedAt 'cli_context_window_unknown'
        metadata_budget = New-HostCapabilityAdapterCandidate $metadataBudget $CapturedAt 'cli_metadata_budget_unknown'
        skills_inventory = New-HostCapabilityAdapterCandidate $inventory $CapturedAt 'cli_skills_inventory_unknown'
    }
    $snapshot = Resolve-HostCapabilitySnapshot -Surface $Surface -ThreadId $ThreadId -TurnId $TurnId -CapturedAt $CapturedAt -ThreadRuntime $runtime
    if ($inventory.Count -gt 0) { $snapshot.capabilities.skills_inventory.value = @($inventory) }
    $coverage = [pscustomobject][ordered]@{
        prompt_input = $null -ne $PromptInput
        model = $null -ne $model
        context_window = $null -ne $contextWindow
        metadata_budget = $null -ne $metadataBudget
        skills_inventory = $inventory.Count -gt 0
    }
    $known = @($snapshot.capabilities.PSObject.Properties | Where-Object { $_.Value.freshness -ne 'fresh' }).Count -eq 0
    $status = if ($known) { 'complete' } else { 'partial' }
    $result = Add-HostCapabilityAdapterMetadata -Snapshot $snapshot -Adapter 'cli' -Source 'cli' -Status $status -Coverage $coverage -Errors $errors.ToArray()
    $result | Add-Member -NotePropertyName platform_na -NotePropertyValue $false
    return $result
}

function ConvertFrom-HostCapabilityConfigScalar {
    param([string]$RawValue)

    $value = ([string]$RawValue).Trim()
    if ($value -match '^"(?<quoted>.*)"$' -or $value -match "^'(?<quoted>.*)'$") { return $Matches['quoted'] }
    if ($value -match '^(?<number>\d+)$') { return [long]$Matches['number'] }
    if ($value -match '^(?i:true|false)$') { return [bool]::Parse($value) }
    return $value
}

function New-HostCapabilitySnapshotFromConfigFallback {
    [CmdletBinding()]
    param(
        [string]$ConfigText = '',
        [string]$ConfigPath = '',
        [string]$Surface = 'offline',
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [string]$ThreadId,
        [string]$TurnId
    )

    if ([string]::IsNullOrWhiteSpace($ConfigText) -and -not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
            $ConfigText = [IO.File]::ReadAllText([IO.Path]::GetFullPath($ConfigPath))
        }
    }

    $values = [ordered]@{}
    $secretCount = 0
    foreach ($line in @(([string]$ConfigText) -split "`r?`n")) {
        $match = [regex]::Match($line, '^\s*(?<key>[A-Za-z0-9_.-]+)\s*=\s*(?<value>.*?)\s*(?:#.*)?$')
        if (-not $match.Success) { continue }
        $key = $match.Groups['key'].Value
        $rawValue = $match.Groups['value'].Value.Trim()
        if (Test-OperationSensitiveKey $key -or $key -match '(?i)(token|secret|password|api[-_]?key|authorization)') {
            $secretCount++
            continue
        }
        if ($key -in @('model', 'model_id', 'model_context_window', 'context_window', 'metadata_budget', 'skill_metadata_budget')) {
            $values[$key] = ConvertFrom-HostCapabilityConfigScalar $rawValue
        }
    }

    $model = if ($values.Contains('model')) { $values['model'] } elseif ($values.Contains('model_id')) { $values['model_id'] } else { $null }
    $contextWindow = if ($values.Contains('model_context_window')) { $values['model_context_window'] } elseif ($values.Contains('context_window')) { $values['context_window'] } else { $null }
    $metadataBudget = if ($values.Contains('metadata_budget')) { $values['metadata_budget'] } elseif ($values.Contains('skill_metadata_budget')) { $values['skill_metadata_budget'] } else { $null }
    $configPayload = [pscustomobject]@{
        model = New-HostCapabilityAdapterCandidate $model $CapturedAt 'config_fallback_model_unknown'
        context_window = New-HostCapabilityAdapterCandidate $contextWindow $CapturedAt 'config_fallback_context_window_unknown'
        metadata_budget = New-HostCapabilityAdapterCandidate $metadataBudget $CapturedAt 'config_fallback_metadata_budget_unknown'
        skills_inventory = New-HostCapabilityAdapterCandidate $null $CapturedAt 'config_fallback_skills_inventory_unknown'
    }
    $snapshot = Resolve-HostCapabilitySnapshot -Surface $Surface -ThreadId $ThreadId -TurnId $TurnId -CapturedAt $CapturedAt -ConfigLayered $configPayload
    $known = @($snapshot.capabilities.PSObject.Properties | Where-Object { $_.Value.freshness -ne 'fresh' }).Count -eq 0
    $status = if ($known) { 'complete' } else { 'partial' }
    $coverage = [pscustomobject][ordered]@{
        config_text = -not [string]::IsNullOrWhiteSpace($ConfigText)
        config_path = -not [string]::IsNullOrWhiteSpace($ConfigPath)
        model = $null -ne $model
        context_window = $null -ne $contextWindow
        metadata_budget = $null -ne $metadataBudget
        skills_inventory = $false
    }
    $result = Add-HostCapabilityAdapterMetadata -Snapshot $snapshot -Adapter 'offline_config' -Source 'config_fallback' -Status $status -Coverage $coverage
    $result | Add-Member -NotePropertyName platform_na -NotePropertyValue $false
    $result | Add-Member -NotePropertyName redaction -NotePropertyValue ([pscustomobject][ordered]@{ applied = $secretCount -gt 0; secret_count = $secretCount; marker = '<redacted>' })
    return $result
}

function New-HostCapabilitySnapshotFromAppServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Responses,
        [string]$Surface = 'app_server',
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [string]$ThreadId,
        [string]$TurnId
    )

    $configResponse = Get-HostCapabilityAdapterProperty $Responses @('config_read', 'config/read')
    $modelResponse = Get-HostCapabilityAdapterProperty $Responses @('model_list', 'model/list')
    $providerResponse = Get-HostCapabilityAdapterProperty $Responses @('model_provider_capabilities_read', 'modelProvider/capabilities/read')
    $skillsResponse = Get-HostCapabilityAdapterProperty $Responses @('skills_list', 'skills/list')

    $config = Get-HostCapabilityAdapterResponseBody $configResponse
    if ($null -ne $config -and (Test-OperationObjectProperty $config 'config')) {
        $config = Get-OperationObjectProperty $config 'config'
    }
    $modelRows = Get-HostCapabilityAdapterRows $modelResponse @('data', 'models')
    $provider = Get-HostCapabilityAdapterResponseBody $providerResponse
    if ($null -ne $provider -and (Test-OperationObjectProperty $provider 'capabilities')) {
        $provider = Get-OperationObjectProperty $provider 'capabilities'
    }
    $skillEntries = Get-HostCapabilityAdapterRows $skillsResponse @('data', 'skills')
    $skillsRows = @($skillEntries | ForEach-Object {
        if (Test-OperationObjectProperty $_ 'skills') {
            foreach ($skill in @((Get-OperationObjectProperty $_ 'skills'))) { $skill }
        }
        else { $_ }
    })
    $errors = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(
        [pscustomobject]@{ method = 'config/read'; response = $configResponse },
        [pscustomobject]@{ method = 'model/list'; response = $modelResponse },
        [pscustomobject]@{ method = 'modelProvider/capabilities/read'; response = $providerResponse },
        [pscustomobject]@{ method = 'skills/list'; response = $skillsResponse }
    )) {
        $error = Get-HostCapabilityAdapterResponseError $entry.response $entry.method
        if ($null -ne $error) { $errors.Add($error) | Out-Null }
    }

    $model = Get-HostCapabilityAdapterProperty $config @('model', 'model_id', 'modelId')
    $effectiveModelRow = $null
    if ($null -ne $model) {
        $matchingModels = @($modelRows | Where-Object {
                $catalogModel = Get-HostCapabilityAdapterProperty $_ @('id', 'name', 'model', 'model_id', 'modelId')
                -not [string]::IsNullOrWhiteSpace([string]$catalogModel) -and [string]::Equals([string]$catalogModel, [string]$model, [StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1)
        if ($matchingModels.Count -gt 0) { $effectiveModelRow = $matchingModels[0] }
    }
    $contextWindow = Get-HostCapabilityAdapterProperty $config @('context_window', 'model_context_window', 'modelContextWindow')
    if ($null -eq $contextWindow -and $null -ne $effectiveModelRow) { $contextWindow = Get-HostCapabilityAdapterProperty $effectiveModelRow @('context_window', 'model_context_window', 'contextWindow', 'modelContextWindow') }
    $metadataBudget = Get-HostCapabilityAdapterProperty $provider @('metadata_budget', 'metadataBudget', 'skill_metadata_budget', 'skillMetadataBudget')

    $inventory = @($skillsRows | ForEach-Object {
        $name = [string](Get-HostCapabilityAdapterProperty $_ @('name', 'id', 'skill'))
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        [pscustomobject][ordered]@{
            name = $name
            description = [string](Get-HostCapabilityAdapterProperty $_ @('description', 'summary'))
            enabled = if (Test-OperationObjectProperty $_ 'enabled') { [bool](Get-OperationObjectProperty $_ 'enabled') } else { $true }
            availability = if (Test-OperationObjectProperty $_ 'availability') { [string](Get-OperationObjectProperty $_ 'availability') } else { 'available' }
        }
    })

    $runtime = [pscustomobject]@{
        model = New-HostCapabilityAdapterCandidate $model $CapturedAt 'app_server_model_unknown'
        context_window = New-HostCapabilityAdapterCandidate $contextWindow $CapturedAt 'app_server_context_window_unknown'
        metadata_budget = New-HostCapabilityAdapterCandidate $metadataBudget $CapturedAt 'app_server_metadata_budget_unknown'
        skills_inventory = New-HostCapabilityAdapterCandidate $inventory $CapturedAt 'app_server_skills_inventory_unknown'
    }
    $snapshot = Resolve-HostCapabilitySnapshot -Surface $Surface -ThreadId $ThreadId -TurnId $TurnId -CapturedAt $CapturedAt -ThreadRuntime $runtime
    $coverage = [pscustomobject][ordered]@{
        config_read = ($null -ne $configResponse -and $null -eq (Get-HostCapabilityAdapterResponseError $configResponse 'config/read'))
        model_list = ($null -ne $modelResponse -and $null -eq (Get-HostCapabilityAdapterResponseError $modelResponse 'model/list'))
        model_provider_capabilities_read = ($null -ne $providerResponse -and $null -eq (Get-HostCapabilityAdapterResponseError $providerResponse 'modelProvider/capabilities/read'))
        skills_list = ($null -ne $skillsResponse -and $null -eq (Get-HostCapabilityAdapterResponseError $skillsResponse 'skills/list'))
    }
    $complete = @($coverage.PSObject.Properties | Where-Object { -not [bool]$_.Value }).Count -eq 0
    $known = @($snapshot.capabilities.PSObject.Properties | Where-Object { $_.Value.freshness -ne 'fresh' }).Count -eq 0
    $status = if ($complete -and $known -and $errors.Count -eq 0) { 'complete' } else { 'partial' }
    if ($inventory.Count -gt 0) { $snapshot.capabilities.skills_inventory.value = @($inventory) }
    return Add-HostCapabilityAdapterMetadata -Snapshot $snapshot -Adapter 'app_server' -Source 'app_server' -Status $status -Coverage $coverage -Errors $errors.ToArray()
}
