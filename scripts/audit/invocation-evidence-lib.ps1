# Parses structured tool-call records out of parsed model-io JSON lines.
# JSON object field order carries no contract, so these helpers read values by
# name — resilient to field reordering, optional fields, and nested inputs.

function Find-InvocationToolCalls {
    param(
        $Node,
        [System.Collections.Generic.List[object]]$Found
    )
    if ($null -eq $Node) { return }
    if ($Node -is [System.Collections.IList]) {
        foreach ($item in $Node) { Find-InvocationToolCalls -Node $item -Found $Found }
        return
    }
    if ($Node -is [pscustomobject]) {
        $typeProp = $Node.PSObject.Properties['type']
        if ($null -ne $typeProp -and [string]$typeProp.Value -eq 'tool-call') {
            $Found.Add($Node) | Out-Null
            return
        }
        foreach ($prop in @($Node.PSObject.Properties)) {
            Find-InvocationToolCalls -Node $prop.Value -Found $Found
        }
    }
}

function Get-InvocationServerFromToolName([string]$ToolName) {
    if ([string]$ToolName -like 'mcp__*') {
        $parts = ([string]$ToolName).Split('__')
        if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) { return [string]$parts[1] }
    }
    return ""
}

function Get-InvocationSkillName($Record) {
    $inputProp = $Record.PSObject.Properties['input']
    if ($null -eq $inputProp) { $inputProp = $Record.PSObject.Properties['arguments'] }
    if ($null -eq $inputProp -or $null -eq $inputProp.Value) { return "" }
    $inputValue = $inputProp.Value
    if ($inputValue -is [string]) {
        try { $inputValue = $inputValue | ConvertFrom-Json } catch { return "" }
    }
    if ($null -eq $inputValue -or -not ($inputValue -is [pscustomobject])) { return "" }
    $skillProp = $inputValue.PSObject.Properties['skill']
    if ($null -eq $skillProp) { return "" }
    return [string]$skillProp.Value
}
