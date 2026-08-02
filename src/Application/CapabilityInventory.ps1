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
    $source = [pscustomobject]@{ type = 'repo_config'; path_or_url = $SourcePath; revision = $SourceRevision; checksum = $null; license = $null; trust_tier = 'runtime' }
    $vendors = Get-OperationObjectProperty $Config 'vendors'
    if ($vendors -is [System.Collections.IDictionary] -or $vendors -is [pscustomobject]) {
        $properties = if ($vendors -is [System.Collections.IDictionary]) { @($vendors.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $vendors[$_] } }) } else { @($vendors.PSObject.Properties) }
        foreach ($property in $properties) {
            $items.Add((New-CapabilityDescriptor -Kind skill -Name ([string]$property.Name) -TruthOrigin runtime -Source $source -Lifecycle active -Components @([pscustomobject]@{ kind = 'vendor'; config = $property.Value }) -VerificationState static_validated)) | Out-Null
        }
    }
    $servers = Get-OperationObjectProperty $Config 'mcp_servers'
    if ($servers -is [System.Collections.IDictionary] -or $servers -is [pscustomobject]) {
        $properties = if ($servers -is [System.Collections.IDictionary]) { @($servers.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $servers[$_] } }) } else { @($servers.PSObject.Properties) }
        foreach ($property in $properties) {
            $items.Add((New-CapabilityDescriptor -Kind mcp -Name ([string]$property.Name) -TruthOrigin runtime -Source $source -Lifecycle active -Components @([pscustomobject]@{ kind = 'mcp_server'; config = Protect-OperationSensitiveValue $property.Value 'config' }) -VerificationState static_validated)) | Out-Null
        }
    }
    return $items.ToArray()
}
