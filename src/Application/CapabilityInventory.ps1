function New-CapabilityInventory {
    param([object[]]$Descriptors = @(), [string]$GeneratedAt = 'not_recorded')
    $valid = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($descriptor in @($Descriptors)) {
        $validation = Test-CapabilityDescriptorContract $descriptor
        if ($validation.pass) { $valid.Add($descriptor) | Out-Null }
        else { foreach ($finding in @($validation.findings)) { $findings.Add($finding) | Out-Null } }
    }
    $decisions = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($valid.ToArray() | Group-Object { '{0}|{1}' -f ([string]$_.kind).ToLowerInvariant(), ([string]$_.name).ToLowerInvariant() })) {
        $items = @($group.Group | Sort-Object id)
        if ($items.Count -eq 1) {
            $decisions.Add([pscustomobject][ordered]@{ key = $group.Name; descriptor_ids = @($items.id); disposition = 'canonical'; reason = 'single_descriptor' }) | Out-Null
            continue
        }
        $sourceKeys = @($items | ForEach-Object { '{0}|{1}|{2}' -f $_.truth_origin, $_.source.type, $_.source.path_or_url } | Sort-Object -Unique)
        $activeCount = @($items | Where-Object lifecycle -eq 'active').Count
        $inactiveCount = @($items | Where-Object { $_.lifecycle -in @('deprecated', 'historical') }).Count
        $disposition = if ($sourceKeys.Count -eq 1) { 'duplicate' } elseif ($activeCount -gt 0 -and $inactiveCount -gt 0) { 'conflict' } else { 'alternative' }
        $reason = if ($disposition -eq 'conflict') { 'lifecycle_truth_must_remain_separate' } else { 'multiple_truth_origins_or_sources' }
        $decisions.Add([pscustomobject][ordered]@{ key = $group.Name; descriptor_ids = @($items.id); disposition = $disposition; reason = $reason }) | Out-Null
    }
    return [pscustomobject][ordered]@{
        schema_version = 1; read_only = $true; generated_at = $GeneratedAt
        descriptors = @($valid.ToArray() | Sort-Object kind, name, truth_origin, id)
        decisions = @($decisions.ToArray() | Sort-Object key)
        findings = @($findings.ToArray()); provider_calls = 0; native_mutations = 0; writes = 0; profile_changed = $false
    }
}

function ConvertTo-CapabilityDescriptorsFromSkillsConfig {
    param($Config, [string]$SourcePath = 'skills.json', [string]$SourceRevision = 'working-tree')
    $items = New-Object System.Collections.Generic.List[object]

    $domains = @(
        [pscustomobject]@{ field = 'vendors'; kind = 'skill'; component = 'vendor'; name_fields = @('name') },
        [pscustomobject]@{ field = 'imports'; kind = 'skill'; component = 'import'; name_fields = @('name', 'skill') },
        [pscustomobject]@{ field = 'mappings'; kind = 'skill'; component = 'mapping'; name_fields = @('to', 'from') },
        [pscustomobject]@{ field = 'mcp_servers'; kind = 'mcp'; component = 'mcp_server'; name_fields = @('name') }
    )

    foreach ($domain in $domains) {
        $value = Get-OperationObjectProperty $Config $domain.field
        $entries = New-Object System.Collections.Generic.List[object]
        if ($value -is [System.Collections.IDictionary]) {
            foreach ($key in @($value.Keys)) { $entries.Add([pscustomobject]@{ name = [string]$key; value = $value[$key] }) | Out-Null }
        }
        elseif ($value -is [array] -or $value -is [System.Collections.IList]) {
            $index = 0
            foreach ($entry in @($value)) {
                $name = $null
                foreach ($field in @($domain.name_fields)) {
                    $candidate = [string](Get-OperationObjectProperty $entry $field)
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) { $name = $candidate; break }
                }
                if ([string]::IsNullOrWhiteSpace($name)) { $name = '{0}-{1}' -f $domain.component, $index }
                if ($domain.field -eq 'imports') {
                    $skillPath = [string](Get-OperationObjectProperty $entry 'skill')
                    if (-not [string]::IsNullOrWhiteSpace($skillPath)) { $name = '{0}/{1}' -f $name, $skillPath.Replace('\', '/') }
                }
                $entries.Add([pscustomobject]@{ name = $name; value = $entry }) | Out-Null
                $index++
            }
        }
        elseif ($value -is [pscustomobject]) {
            $explicitName = $null
            foreach ($field in @($domain.name_fields)) {
                $candidate = [string](Get-OperationObjectProperty $value $field)
                if (-not [string]::IsNullOrWhiteSpace($candidate)) { $explicitName = $candidate; break }
            }
            if (-not [string]::IsNullOrWhiteSpace($explicitName)) {
                $entries.Add([pscustomobject]@{ name = $explicitName; value = $value }) | Out-Null
            }
            else {
                foreach ($property in @($value.PSObject.Properties)) { $entries.Add([pscustomobject]@{ name = [string]$property.Name; value = $property.Value }) | Out-Null }
            }
        }

        foreach ($entry in @($entries.ToArray())) {
            $source = [pscustomobject]@{ type = 'repo_config'; path_or_url = ('{0}#{1}' -f $SourcePath, $domain.field); revision = $SourceRevision; checksum = $null; license = $null; trust_tier = 'runtime' }
            $component = [pscustomobject]@{ kind = $domain.component; config = Protect-OperationSensitiveValue $entry.value 'config' }
            $items.Add((New-CapabilityDescriptor -Kind $domain.kind -Name $entry.name -TruthOrigin runtime -Source $source -Lifecycle active -Components @($component) -VerificationState static_validated)) | Out-Null
        }
    }
    return $items.ToArray()
}
