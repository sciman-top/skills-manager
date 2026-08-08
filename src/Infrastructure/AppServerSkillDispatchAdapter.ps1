$appServerSkillDispatchAdapterRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) {
    . (Join-Path $appServerSkillDispatchAdapterRepoRoot 'src\Domain\OperationPlan.ps1')
}

function Get-AppServerSkillDispatchProperty {
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

function Get-AppServerSkillDispatchStringArray {
    param($Value)

    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        $text = ([string]$item).Trim().ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($text) -and $seen.Add($text)) {
            $items.Add($text) | Out-Null
        }
    }
    return ,([string[]]@($items.ToArray()))
}

function New-AppServerSkillDispatchAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [string[]]$SupportedItemTypes = @(),
        [bool]$Available = $true,
        [string]$Surface = 'app_server'
    )

    $normalizedTypes = Get-AppServerSkillDispatchStringArray $SupportedItemTypes
    $supportsSkillInjection = $Available -and ($normalizedTypes -contains 'skill')
    $platformNa = -not $supportsSkillInjection
    return [pscustomobject][ordered]@{
        schema_version = 1
        adapter = 'app_server'
        surface = $Surface
        status = if ($platformNa) { 'platform_na' } else { 'complete' }
        platform_na = $platformNa
        available = $Available
        supported_item_types = $normalizedTypes
        supports_skill_injection = $supportsSkillInjection
        injection_contract = [pscustomobject][ordered]@{
            item_type = 'skill'
            supported = $supportsSkillInjection
            payload_shape = 'items[].type=skill'
        }
        captured_at = $CapturedAt
        freshness = if ($Available) { 'fresh' } else { 'unknown' }
        read_only = $true
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function Test-AppServerSkillDispatchAdapterContract {
    param($Adapter)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Adapter) {
        return New-OperationValidationResult @((New-OperationFinding 'adapter_missing' 'error' '$' 'App Server dispatch adapter is required.'))
    }
    if ((Get-AppServerSkillDispatchProperty $Adapter @('schema_version')) -ne 1) {
        $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only App Server skill dispatch adapter schema version 1 is supported.')) | Out-Null
    }
    if ([string](Get-AppServerSkillDispatchProperty $Adapter @('adapter')) -ne 'app_server') {
        $findings.Add((New-OperationFinding 'adapter_invalid' 'error' '$.adapter' 'Adapter must be app_server.')) | Out-Null
    }
    if (-not (Test-OperationRfc3339 (Get-AppServerSkillDispatchProperty $Adapter @('captured_at')))) {
        $findings.Add((New-OperationFinding 'captured_at_invalid' 'error' '$.captured_at' 'Adapter captured_at must be RFC3339.')) | Out-Null
    }
    $supportedTypes = Get-AppServerSkillDispatchStringArray (Get-AppServerSkillDispatchProperty $Adapter @('supported_item_types'))
    if (-not (Test-OperationArray (Get-AppServerSkillDispatchProperty $Adapter @('supported_item_types')))) {
        $findings.Add((New-OperationFinding 'supported_item_types_invalid' 'error' '$.supported_item_types' 'Supported App Server item types must be an array.')) | Out-Null
    }
    $supportsSkill = [bool](Get-AppServerSkillDispatchProperty $Adapter @('supports_skill_injection'))
    if ($supportsSkill -and $supportedTypes -notcontains 'skill') {
        $findings.Add((New-OperationFinding 'skill_support_mismatch' 'error' '$.supports_skill_injection' 'Skill injection support must be declared by the supported item types.')) | Out-Null
    }
    $contract = Get-AppServerSkillDispatchProperty $Adapter @('injection_contract')
    if ([string](Get-AppServerSkillDispatchProperty $contract @('item_type')) -ne 'skill') {
        $findings.Add((New-OperationFinding 'injection_type_invalid' 'error' '$.injection_contract.item_type' 'Strict dispatch only supports type=skill injection.')) | Out-Null
    }
    if ([bool](Get-AppServerSkillDispatchProperty $Adapter @('read_only')) -ne $true) {
        $findings.Add((New-OperationFinding 'read_only_required' 'error' '$.read_only' 'The adapter must remain read-only.')) | Out-Null
    }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) {
        if ([long](Get-AppServerSkillDispatchProperty $Adapter @($field)) -ne 0) {
            $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'App Server dispatch planning must remain zero-side-effect.')) | Out-Null
        }
    }
    $expectedPlatformNa = -not $supportsSkill
    if ([bool](Get-AppServerSkillDispatchProperty $Adapter @('platform_na')) -ne $expectedPlatformNa) {
        $findings.Add((New-OperationFinding 'platform_na_invalid' 'error' '$.platform_na' 'Unsupported skill injection must be marked platform_na.')) | Out-Null
    }
    return New-OperationValidationResult $findings.ToArray()
}

function New-AppServerSkillInjectionRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][object[]]$Skills
    )

    $adapterContract = Test-AppServerSkillDispatchAdapterContract $Adapter
    if (-not [bool]$adapterContract.pass -or -not [bool]$Adapter.supports_skill_injection) {
        return [pscustomobject][ordered]@{
            schema_version = 1
            status = 'platform_na'
            platform_na = $true
            items = [object[]]@()
            reason = 'app_server_skill_injection_unsupported'
            findings = [object[]]@($adapterContract.findings)
            provider_calls = 0
            native_mutations = 0
            writes = 0
        }
    }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($skill in @($Skills)) {
        $name = ([string](Get-AppServerSkillDispatchProperty $skill @('name', 'skill_name'))).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $items.Add([pscustomobject][ordered]@{
                type = 'skill'
                name = $name
                path = [string](Get-AppServerSkillDispatchProperty $skill @('path'))
                content_hash = [string](Get-AppServerSkillDispatchProperty $skill @('content_hash'))
            }) | Out-Null
    }
    return [pscustomobject][ordered]@{
        schema_version = 1
        status = 'ready'
        platform_na = $false
        items = [object[]]@($items.ToArray())
        item_type = 'skill'
        host_mutation = $false
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function Test-AppServerSkillInjectionRequestContract {
    param($Request)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Request) {
        return New-OperationValidationResult @((New-OperationFinding 'injection_request_missing' 'error' '$' 'App Server skill injection request is required.'))
    }
    if ((Get-AppServerSkillDispatchProperty $Request @('schema_version')) -ne 1) {
        $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only injection request schema version 1 is supported.')) | Out-Null
    }
    if ([string](Get-AppServerSkillDispatchProperty $Request @('item_type')) -ne 'skill' -and [string](Get-AppServerSkillDispatchProperty $Request @('status')) -eq 'ready') {
        $findings.Add((New-OperationFinding 'item_type_invalid' 'error' '$.item_type' 'Ready injection requests must use item_type=skill.')) | Out-Null
    }
    if (-not (Test-OperationArray (Get-AppServerSkillDispatchProperty $Request @('items')))) {
        $findings.Add((New-OperationFinding 'items_invalid' 'error' '$.items' 'Injection request items must be an array.')) | Out-Null
    }
    $items = Get-AppServerSkillDispatchProperty $Request @('items')
    foreach ($item in $items) {
        if ([string](Get-AppServerSkillDispatchProperty $item @('type')) -ne 'skill') {
            $findings.Add((New-OperationFinding 'item_type_invalid' 'error' '$.items[].type' 'Only type=skill items can be injected.')) | Out-Null
        }
    }
    if ([bool](Get-AppServerSkillDispatchProperty $Request @('host_mutation')) -ne $false) {
        $findings.Add((New-OperationFinding 'host_mutation_forbidden' 'error' '$.host_mutation' 'The fixture adapter cannot perform a live host mutation.')) | Out-Null
    }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) {
        if ([long](Get-AppServerSkillDispatchProperty $Request @($field)) -ne 0) {
            $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Injection request construction must remain zero-side-effect.')) | Out-Null
        }
    }
    return New-OperationValidationResult $findings.ToArray()
}
