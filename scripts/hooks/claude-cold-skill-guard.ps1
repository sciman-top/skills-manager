#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-SessionStatePath {
    param([string]$SessionId)
    $root = if (-not [string]::IsNullOrWhiteSpace($env:SKILLS_MANAGER_COLD_ROUTER_STATE_ROOT)) {
        $env:SKILLS_MANAGER_COLD_ROUTER_STATE_ROOT
    } else {
        Join-Path ([IO.Path]::GetTempPath()) 'skills-manager-cold-router'
    }
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $safe = if ([string]::IsNullOrWhiteSpace($SessionId)) { 'unknown' } else { $SessionId -replace '[^A-Za-z0-9_.-]', '_' }
    return (Join-Path $root ($safe + '.json'))
}

function Get-TextDigest {
    param([string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Text)
    return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Get-ToolText {
    param([object]$InputObject)
    $toolInput = Get-PropertyValue $InputObject 'tool_input'
    $command = [string](Get-PropertyValue $toolInput 'command')
    $filePath = [string](Get-PropertyValue $toolInput 'file_path')
    $path = [string](Get-PropertyValue $toolInput 'path')
    $pattern = [string](Get-PropertyValue $toolInput 'pattern')
    $glob = [string](Get-PropertyValue $toolInput 'glob')
    return @($command, $filePath, $path, $pattern, $glob) -join "`n"
}

function Get-ColdPathReferences {
    param([string]$Text)
    $result = @()
    $pattern = '(?i)(?:^|[\\/\s"''`])(?<root>imports|vendor|agent)[\\/](?<name>[^\\/\s"''`]+)'
    foreach ($match in [regex]::Matches([string]$Text, $pattern)) {
        $result += [pscustomobject]@{
            root = $match.Groups['root'].Value.ToLowerInvariant()
            name = $match.Groups['name'].Value
        }
    }
    return @($result)
}

function Get-PropertyValuesRecursive {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return @() }
    $values = @()
    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
        foreach ($item in $Object) { $values += @(Get-PropertyValuesRecursive $item $Name) }
        return @($values)
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { $values += ,$property.Value }
    foreach ($child in $Object.PSObject.Properties) {
        if ($child.Name -ne $Name -and $null -ne $child.Value -and $child.Value -isnot [string]) {
            $values += @(Get-PropertyValuesRecursive $child.Value $Name)
        }
    }
    return @($values)
}

function Get-JsonObjectsRecursive {
    param([object]$Object)
    if ($null -eq $Object) { return @() }
    $objects = @()
    if ($Object -is [string]) {
        try { $objects += ,($Object | ConvertFrom-Json -Depth 60) } catch { }
        return @($objects)
    }
    if ($Object -is [System.Collections.IEnumerable]) {
        foreach ($item in $Object) { $objects += @(Get-JsonObjectsRecursive $item) }
        return @($objects)
    }
    $objects += ,$Object
    foreach ($property in $Object.PSObject.Properties) {
        if ($null -ne $property.Value) { $objects += @(Get-JsonObjectsRecursive $property.Value) }
    }
    return @($objects)
}

function Get-ValidatedSkillNames {
    param([object]$HookInput)
    $rawCandidates = @()
    foreach ($field in @('tool_response', 'tool_result', 'result', 'response')) {
        $value = Get-PropertyValue $HookInput $field
        if ($null -ne $value) { $rawCandidates += ,$value }
    }
    $rawCandidates += ,(Get-PropertyValue $HookInput 'tool_input')
    $objects = @()
    foreach ($candidate in $rawCandidates) {
        $objects += @(Get-JsonObjectsRecursive $candidate)
    }
    $names = @()
    foreach ($object in $objects) {
        $validation = @(Get-PropertyValuesRecursive $object 'load_validation')
        $pass = $false
        foreach ($item in $validation) {
            if ([bool](Get-PropertyValue $item 'pass')) { $pass = $true }
        }
        if (-not $pass) { continue }
        foreach ($closure in @(Get-PropertyValuesRecursive $object 'validated_closure')) {
            if ($closure -is [string]) { $names += [string]$closure; continue }
            foreach ($entry in @($closure)) {
                $name = [string](Get-PropertyValue $entry 'name')
                if (-not [string]::IsNullOrWhiteSpace($name)) { $names += $name }
            }
        }
    }
    return @($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Write-HookDecision {
    param([ValidateSet('allow', 'deny', 'ask')][string]$Decision, [string]$Message)
    $payload = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName = 'PreToolUse'
            permissionDecision = $Decision
        }
        systemMessage = $Message
    }
    $payload | ConvertTo-Json -Compress -Depth 10
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $inputObject = $raw | ConvertFrom-Json -Depth 60
    $eventName = [string](Get-PropertyValue $inputObject 'hook_event_name')
    $sessionId = [string](Get-PropertyValue $inputObject 'session_id')
    $toolName = [string](Get-PropertyValue $inputObject 'tool_name')
    $toolText = Get-ToolText $inputObject
    $statePath = Get-SessionStatePath $sessionId

    if ($eventName -eq 'PostToolUse' -and $toolName -in @('Bash', 'PowerShell')) {
        $command = [string](Get-PropertyValue (Get-PropertyValue $inputObject 'tool_input') 'command')
        if ($command -match '(?i)(?:route-capability\.ps1|capability-router[\\/].*\.ps1)\b') {
            $names = @(Get-ValidatedSkillNames $inputObject)
            if ($names.Count -gt 0) {
                $now = [DateTimeOffset]::UtcNow
                $state = [ordered]@{
                    schema_version = 1
                    session_id = $sessionId
                    created_at = $now.ToString('o')
                    expires_at = $now.AddMinutes(15).ToString('o')
                    validated_skill_names = $names
                    router_command_sha256 = Get-TextDigest $command
                }
                $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
            }
        }
        exit 0
    }

    if ($eventName -ne 'PreToolUse' -or $toolName -notin @('Bash', 'PowerShell', 'Read', 'Glob', 'Grep', 'mcp__filesystem__read_text_file')) { exit 0 }
    $references = @(Get-ColdPathReferences $toolText)
    if ($references.Count -eq 0) { exit 0 }

    $importsOrVendor = @($references | Where-Object { $_.root -in @('imports', 'vendor') })
    if ($importsOrVendor.Count -gt 0) {
        Write-HookDecision deny '直接读取 imports/vendor 中的冷技能源码已阻断。请先执行一次 capability-router 校验，再仅读取其 validated closure 对应的 agent/<skill> 投影。'
        exit 0
    }

    $state = $null
    if (Test-Path -LiteralPath $statePath) {
        try { $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json -Depth 20 } catch { $state = $null }
    }
    $validState = $false
    if ($null -ne $state -and [string](Get-PropertyValue $state 'session_id') -eq $sessionId) {
        $expiry = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string](Get-PropertyValue $state 'expires_at'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$expiry)) {
            $validState = $expiry -gt [DateTimeOffset]::UtcNow -and @((Get-PropertyValue $state 'validated_skill_names')).Count -gt 0
        }
    }
    foreach ($reference in @($references | Where-Object { $_.root -eq 'agent' })) {
        $allowed = if ($validState) { @((Get-PropertyValue $state 'validated_skill_names') | ForEach-Object { [string]$_ }) -contains [string]$reference.name } else { $false }
        if (-not $allowed) {
            Write-HookDecision deny '直接读取 agent/<skill> 已阻断：当前会话缺少有效且未过期的 capability-router validated closure。请先路由并由父代理完成 admission。'
            exit 0
        }
    }
    exit 0
} catch {
    # A malformed hook input or state must fail closed for a cold-source reference.
    if ($toolName -in @('Bash', 'PowerShell', 'Read', 'Glob', 'Grep', 'mcp__filesystem__read_text_file') -and (Get-ColdPathReferences $toolText).Count -gt 0) {
        Write-HookDecision deny '冷技能来源 guard 输入或状态无效，已 fail closed；请重新执行 capability-router 校验。'
    }
    exit 0
}
