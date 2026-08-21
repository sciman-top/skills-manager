function ConvertFrom-SkillMetadataScalar {
    param([string]$Value)
    $valueText = $Value.Trim()
    if ($valueText.Length -ge 2 -and (($valueText.StartsWith('"') -and $valueText.EndsWith('"')) -or ($valueText.StartsWith("'") -and $valueText.EndsWith("'")))) {
        return $valueText.Substring(1, $valueText.Length - 2)
    }
    return $valueText
}

function Test-SkillMetadataStringScalar {
    param([string]$Value)
    $valueText = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($valueText)) { return $false }
    if ($valueText.Length -ge 2 -and (($valueText.StartsWith('"') -and $valueText.EndsWith('"')) -or ($valueText.StartsWith("'") -and $valueText.EndsWith("'")))) { return $true }
    if ($valueText -match '^(?i:null|true|false|yes|no|on|off|~)$') { return $false }
    if ($valueText -match '^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?$') { return $false }
    if ($valueText.StartsWith('[') -or $valueText.StartsWith('{')) { return $false }
    return $true
}

function Read-SkillMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$Observation)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $text = if (Test-Path -LiteralPath $fullPath -PathType Leaf) { [IO.File]::ReadAllText($fullPath) } else { '' }
    $result = [ordered]@{
        valid = $false
        path = $fullPath
        text = $text
        name = ''
        declared_name = ''
        description = ''
        trigger_summary = ''
        fields = [ordered]@{}
        field_classes = [ordered]@{ standard = @(); host_extension = @(); vendor_extension = @(); unknown = @() }
        findings = @()
    }
    $frontmatter = [regex]::Match($text, '\A(?:\uFEFF)?---[ \t]*\r?\n(?<body>.*?)(?:\r?\n)---[ \t]*(?:\r?\n|\z)', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $frontmatter.Success) {
        $result.findings = @([pscustomobject]@{ code='frontmatter_missing'; severity='error'; field=''; message='SKILL.md requires YAML frontmatter.' })
        return [pscustomobject]$result
    }

    $lines = @($frontmatter.Groups['body'].Value -split '\r?\n')
    $fields = [ordered]@{}
    $fieldKinds = [ordered]@{}
    $findings = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        if ($line -notmatch '^(?<key>[A-Za-z][A-Za-z0-9-]*):(?:[ \t]*(?<value>.*))?$') { continue }
        $key = [string]$Matches.key
        $raw = [string]$Matches.value
        if ($fields.Contains($key)) {
            $findings.Add([pscustomobject]@{ code='field_duplicate'; severity='error'; field=$key; message=('Duplicate top-level skill metadata field: {0}' -f $key) }) | Out-Null
            continue
        }

        if ([string]::Equals($key, 'metadata', [StringComparison]::Ordinal) -and [string]::IsNullOrWhiteSpace($raw)) {
            $metadataMap = [ordered]@{}
            $metadataIndent = -1
            while ($index + 1 -lt $lines.Count) {
                $candidate = [string]$lines[$index + 1]
                if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate -notmatch '^[ \t]+') { break }
                $index++
                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                $match = [regex]::Match($candidate, '^(?<indent>[ \t]+)(?<key>[A-Za-z][A-Za-z0-9_.-]*):(?:[ \t]*(?<value>.*))?$')
                if (-not $match.Success) {
                    $findings.Add([pscustomobject]@{ code='metadata_value_invalid'; severity='error'; field='metadata'; message='Skill metadata must be a one-level map from string keys to string values.' }) | Out-Null
                    continue
                }
                $indent = $match.Groups['indent'].Value.Length
                if ($metadataIndent -lt 0) { $metadataIndent = $indent }
                if ($indent -ne $metadataIndent) {
                    $findings.Add([pscustomobject]@{ code='metadata_value_invalid'; severity='error'; field='metadata'; message='Skill metadata values must be strings, not nested mappings.' }) | Out-Null
                    continue
                }
                $metadataKey = [string]$match.Groups['key'].Value
                $metadataRaw = [string]$match.Groups['value'].Value
                if ($metadataMap.Contains($metadataKey)) {
                    $findings.Add([pscustomobject]@{ code='metadata_key_duplicate'; severity='error'; field='metadata'; message=('Duplicate skill metadata key: {0}' -f $metadataKey) }) | Out-Null
                    continue
                }
                if (-not (Test-SkillMetadataStringScalar $metadataRaw)) {
                    $findings.Add([pscustomobject]@{ code='metadata_value_invalid'; severity='error'; field='metadata'; message=('Skill metadata value must be a string: {0}' -f $metadataKey) }) | Out-Null
                    continue
                }
                $metadataMap[$metadataKey] = ConvertFrom-SkillMetadataScalar $metadataRaw
            }
            $fields[$key] = [pscustomobject]$metadataMap
            $fieldKinds[$key] = 'map'
            continue
        }

        if ($raw -in @('|','>','|-','>-','|+','>+')) {
            $rawParts = [Collections.Generic.List[string]]::new()
            $contentIndent = [int]::MaxValue
            while ($index + 1 -lt $lines.Count) {
                $candidate = [string]$lines[$index + 1]
                if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate -notmatch '^[ \t]+') { break }
                $index++
                $rawParts.Add($candidate) | Out-Null
                if (-not [string]::IsNullOrWhiteSpace($candidate)) { $contentIndent = [Math]::Min($contentIndent, ([regex]::Match($candidate, '^[ \t]+')).Value.Length) }
            }
            $parts = @($rawParts | ForEach-Object { if ([string]::IsNullOrWhiteSpace([string]$_)) { '' } else { ([string]$_).Substring([Math]::Min($contentIndent, ([string]$_).Length)) } })
            $value = $parts -join "`n"
            if ($raw.StartsWith('>')) { $value = [regex]::Replace($value, '(?<!\n)\n(?!\n)', ' ') }
            $fields[$key] = $value.TrimEnd("`r", "`n")
            $fieldKinds[$key] = 'string'
        }
        else {
            $fields[$key] = ConvertFrom-SkillMetadataScalar $raw
            $fieldKinds[$key] = if (Test-SkillMetadataStringScalar $raw) { 'string' } else { 'non_string_scalar' }
        }
    }

    $name = [string]$fields['name']
    $description = [string]$fields['description']
    if ($fields.Contains('name') -and [string]$fieldKinds['name'] -ne 'string') { $findings.Add([pscustomobject]@{ code='name_type_invalid'; severity='error'; field='name'; message='Skill name must be a string.' }) | Out-Null }
    elseif ([string]::IsNullOrWhiteSpace($name)) { $findings.Add([pscustomobject]@{ code='name_required'; severity='error'; field='name'; message='Skill name is required.' }) | Out-Null }
    elseif ($name.Length -gt 64 -or $name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $findings.Add([pscustomobject]@{ code='name_invalid'; severity='error'; field='name'; message='Skill name must be at most 64 lowercase alphanumeric/hyphen characters without edge or repeated hyphens.' }) | Out-Null }
    if ($fields.Contains('description') -and [string]$fieldKinds['description'] -ne 'string') { $findings.Add([pscustomobject]@{ code='description_type_invalid'; severity='error'; field='description'; message='Skill description must be a string.' }) | Out-Null }
    elseif ([string]::IsNullOrWhiteSpace($description)) { $findings.Add([pscustomobject]@{ code='description_required'; severity='error'; field='description'; message='Skill description is required.' }) | Out-Null }
    elseif ($description.Length -gt 1024) { $findings.Add([pscustomobject]@{ code='description_too_long'; severity='error'; field='description'; message='Skill description exceeds 1024 characters.' }) | Out-Null }

    if ($fields.Contains('license')) {
        if ([string]$fieldKinds['license'] -ne 'string' -or [string]::IsNullOrWhiteSpace([string]$fields['license'])) {
            $findings.Add([pscustomobject]@{ code='license_invalid'; severity='error'; field='license'; message='Skill license must be a non-empty string when provided.' }) | Out-Null
        }
    }
    if ($fields.Contains('compatibility')) {
        $compatibility = [string]$fields['compatibility']
        if ([string]$fieldKinds['compatibility'] -ne 'string' -or [string]::IsNullOrWhiteSpace($compatibility)) { $findings.Add([pscustomobject]@{ code='compatibility_invalid'; severity='error'; field='compatibility'; message='Skill compatibility must be a non-empty string when provided.' }) | Out-Null }
        elseif ($compatibility.Length -gt 500) { $findings.Add([pscustomobject]@{ code='compatibility_too_long'; severity='error'; field='compatibility'; message='Skill compatibility exceeds 500 characters.' }) | Out-Null }
    }
    if ($fields.Contains('allowed-tools')) {
        if ([string]$fieldKinds['allowed-tools'] -ne 'string' -or [string]::IsNullOrWhiteSpace([string]$fields['allowed-tools'])) {
            $findings.Add([pscustomobject]@{ code='allowed_tools_invalid'; severity='error'; field='allowed-tools'; message='Skill allowed-tools must be a non-empty space-separated string when provided.' }) | Out-Null
        }
    }
    if ($fields.Contains('metadata') -and [string]$fieldKinds['metadata'] -ne 'map') {
        $findings.Add([pscustomobject]@{ code='metadata_invalid'; severity='error'; field='metadata'; message='Skill metadata must be a map from string keys to string values.' }) | Out-Null
    }

    $standardFields = @('name','description','license','allowed-tools','metadata','compatibility')
    $hostExtensionFields = @('agent','argument-hint','context','disable-model-invocation','hidden','hooks','model','user-invocable')
    $vendorExtensionFields = @('version')
    $fieldClasses = [ordered]@{ standard = @(); host_extension = @(); vendor_extension = @(); unknown = @() }
    foreach ($key in $fields.Keys) {
        if ($key -in $standardFields) { $fieldClasses.standard += $key; continue }
        if ($key -in $hostExtensionFields) {
            $fieldClasses.host_extension += $key
            $findings.Add([pscustomobject]@{ code='field_host_extension'; severity='warning'; field=$key; message=('Known host-specific skill metadata field: {0}' -f $key) }) | Out-Null
            continue
        }
        if ($key -in $vendorExtensionFields) {
            $fieldClasses.vendor_extension += $key
            $findings.Add([pscustomobject]@{ code='field_vendor_extension'; severity='warning'; field=$key; message=('Known vendor skill metadata field: {0}' -f $key) }) | Out-Null
            continue
        }
        $fieldClasses.unknown += $key
        $severity = if ($Observation) { 'warning' } else { 'error' }
        $findings.Add([pscustomobject]@{ code='field_unknown'; severity=$severity; field=$key; message=('Unknown top-level skill metadata field: {0}' -f $key) }) | Out-Null
    }

    if ($Observation) {
        foreach ($finding in $findings) {
            if ([string]$finding.severity -eq 'error' -and [string]$finding.code -notin @('frontmatter_missing','name_required','description_required','name_type_invalid','description_type_invalid')) { $finding.severity = 'warning' }
        }
    }
    $result.valid = @($findings | Where-Object severity -eq 'error').Count -eq 0
    $triggerLine = @($text -split '\r?\n' | Where-Object { $_ -match '(?i)trigger|use when|when to use|使用场景' } | Select-Object -First 1)
    $result.name = $name
    $result.declared_name = $name
    $result.description = $description
    $result.trigger_summary = if ($triggerLine.Count) { ([string]$triggerLine[0]).Trim() } else { $description }
    $result.fields = $fields
    $result.field_classes = $fieldClasses
    $result.findings = @($findings.ToArray())
    return [pscustomobject]$result
}
