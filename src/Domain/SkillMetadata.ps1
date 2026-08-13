function ConvertFrom-SkillMetadataScalar {
    param([string]$Value)
    $valueText = $Value.Trim()
    if ($valueText.Length -ge 2 -and (($valueText.StartsWith('"') -and $valueText.EndsWith('"')) -or ($valueText.StartsWith("'") -and $valueText.EndsWith("'")))) {
        return $valueText.Substring(1, $valueText.Length - 2)
    }
    return $valueText
}

function Read-SkillMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$Observation)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $text = if (Test-Path -LiteralPath $fullPath -PathType Leaf) { [IO.File]::ReadAllText($fullPath) } else { '' }
    $result = [ordered]@{ valid = $false; path = $fullPath; text = $text; name = ''; declared_name = ''; description = ''; fields = [ordered]@{}; findings = @() }
    $frontmatter = [regex]::Match($text, '\A(?:\uFEFF)?---[ \t]*\r?\n(?<body>.*?)(?:\r?\n)---[ \t]*(?:\r?\n|\z)', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $frontmatter.Success) {
        $result.findings = @([pscustomobject]@{ code='frontmatter_missing'; severity='error'; field=''; message='SKILL.md requires YAML frontmatter.' })
        return [pscustomobject]$result
    }
    $lines = @($frontmatter.Groups['body'].Value -split '\r?\n')
    $fields = [ordered]@{}
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        if ($line -notmatch '^(?<key>[A-Za-z][A-Za-z0-9-]*):(?:[ \t]*(?<value>.*))?$') { continue }
        $key = [string]$Matches.key; $raw = [string]$Matches.value
        if ($raw -in @('|','>','|-','>-','|+','>+')) {
            $parts = [Collections.Generic.List[string]]::new()
            while ($index + 1 -lt $lines.Count -and [string]$lines[$index + 1] -match '^[ \t]+') { $index++; $parts.Add(([string]$lines[$index]).Trim()) | Out-Null }
            $fields[$key] = if ($raw.StartsWith('>')) { ($parts -join ' ') } else { ($parts -join "`n") }
        }
        else { $fields[$key] = ConvertFrom-SkillMetadataScalar $raw }
    }
    $name = [string]$fields['name']; $description = [string]$fields['description']
    $findings = [Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($name)) { $findings.Add([pscustomobject]@{ code='name_required'; severity='error'; field='name'; message='Skill name is required.' }) | Out-Null }
    elseif ($name.Length -gt 64 -or $name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $findings.Add([pscustomobject]@{ code='name_invalid'; severity='error'; field='name'; message='Skill name must be at most 64 lowercase alphanumeric/hyphen characters without edge or repeated hyphens.' }) | Out-Null }
    if ([string]::IsNullOrWhiteSpace($description)) { $findings.Add([pscustomobject]@{ code='description_required'; severity='error'; field='description'; message='Skill description is required.' }) | Out-Null }
    elseif ($description.Length -gt 1024) { $findings.Add([pscustomobject]@{ code='description_too_long'; severity='error'; field='description'; message='Skill description exceeds 1024 characters.' }) | Out-Null }
    if ($fields.Contains('compatibility') -and ([string]$fields['compatibility']).Length -gt 500) { $findings.Add([pscustomobject]@{ code='compatibility_too_long'; severity='error'; field='compatibility'; message='Skill compatibility exceeds 500 characters.' }) | Out-Null }
    $allowed = @('name','description','license','allowed-tools','metadata','compatibility')
    foreach ($key in $fields.Keys) { if ($key -notin $allowed) { $findings.Add([pscustomobject]@{ code='field_unknown'; severity='warning'; field=$key; message=('Unknown top-level skill metadata field: {0}' -f $key) }) | Out-Null } }
    if ($Observation) { foreach ($finding in $findings) { if ([string]$finding.severity -eq 'error' -and [string]$finding.code -notin @('name_required','description_required')) { $finding.severity = 'warning' } } }
    $result.valid = @($findings | Where-Object severity -eq 'error').Count -eq 0
    $result.name = $name; $result.declared_name = $name; $result.description = $description; $result.fields = $fields; $result.findings = @($findings.ToArray())
    return [pscustomobject]$result
}
