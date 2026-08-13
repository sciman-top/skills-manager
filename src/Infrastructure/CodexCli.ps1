function Invoke-CodexCliJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $command = Get-Command codex -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw 'codex_cli_unavailable' }
    $output = @(& $command.Source @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('codex_cli_failed: {0}' -f ($output -join "`n")) }
    try { return (($output -join "`n") | ConvertFrom-Json -Depth 50) }
    catch { throw ('codex_cli_json_invalid: {0}' -f $_.Exception.Message) }
}

function Get-CodexPluginSkillInventory {
    [CmdletBinding()]
    param()

    $result = [ordered]@{ authority = 'codex_plugin_list_json'; freshness = 'unknown'; coverage = 'platform_na'; plugin_count = 0; skill_count = 0; metadata_chars = 0; enabled_plugin_ids = @(); skills = @(); warnings = @() }
    try { $payload = Invoke-CodexCliJson -Arguments @('plugin', 'list', '--json') }
    catch {
        $result.warnings = @([pscustomobject][ordered]@{ code = 'codex_plugin_inventory_unavailable'; subject = 'codex plugin list --json'; message = $_.Exception.Message })
        return [pscustomobject]$result
    }
    if ($null -eq $payload -or $null -eq $payload.PSObject.Properties['installed']) {
        $result.warnings = @([pscustomobject][ordered]@{ code = 'codex_plugin_inventory_contract_invalid'; subject = 'installed'; message = 'Codex plugin inventory JSON does not contain the installed collection.' })
        return [pscustomobject]$result
    }
    $skills = [Collections.Generic.List[object]]::new()
    $warnings = [Collections.Generic.List[object]]::new()
    $plugins = @($payload.installed | Where-Object { $_.installed -eq $true -and $_.enabled -eq $true } | Sort-Object pluginId)
    foreach ($plugin in $plugins) {
        $pluginId = [string]$plugin.pluginId
        $sourcePath = [string]$plugin.source.path
        if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
            $warnings.Add([pscustomobject][ordered]@{ code = 'enabled_plugin_source_missing'; subject = $pluginId; message = ('Enabled plugin source is unavailable: {0}' -f $sourcePath) }) | Out-Null
            continue
        }
        foreach ($skillFile in @(Get-ChildItem -LiteralPath (Join-Path $sourcePath 'skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $candidate = Join-Path $_.FullName 'SKILL.md'
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { Get-Item -LiteralPath $candidate }
                } | Sort-Object FullName)) {
            if ($null -eq (Get-Command Read-SkillMetadata -ErrorAction SilentlyContinue)) {
                $repoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json')) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
                . (Join-Path $repoRoot 'src\Domain\SkillMetadata.ps1')
            }
            $metadata = Read-SkillMetadata $skillFile.FullName -Observation
            $name = if ([string]::IsNullOrWhiteSpace([string]$metadata.name)) { $skillFile.Directory.Name } else { [string]$metadata.name }
            $description = [string]$metadata.description
            $skills.Add([pscustomobject][ordered]@{ plugin_id = $pluginId; plugin_name = [string]$plugin.name; marketplace = [string]$plugin.marketplaceName; version = [string]$plugin.version; name = $name; qualified_name = ('{0}::{1}' -f $pluginId, $name); description = $description; path = $skillFile.FullName }) | Out-Null
        }
    }
    $ordered = @($skills.ToArray() | Sort-Object plugin_id, name, path)
    $result.freshness = 'fresh'; $result.coverage = 'complete'; $result.plugin_count = $plugins.Count; $result.skill_count = $ordered.Count
    foreach ($skill in $ordered) { $result.metadata_chars += ([string]$skill.name).Length + ([string]$skill.description).Length }
    $result.enabled_plugin_ids = @($plugins | ForEach-Object { [string]$_.pluginId }); $result.skills = $ordered; $result.warnings = @($warnings.ToArray())
    return [pscustomobject]$result
}

function Get-CodexMcpObservation {
    [CmdletBinding()]
    param()

    $result = [ordered]@{ authority = 'codex_mcp_list_json'; freshness = 'unknown'; coverage = 'platform_na'; servers = @(); warnings = @() }
    try { $payload = Invoke-CodexCliJson -Arguments @('mcp', 'list', '--json') }
    catch {
        $result.warnings = @([pscustomobject][ordered]@{ code = 'codex_mcp_observation_unavailable'; subject = 'codex mcp list --json'; message = $_.Exception.Message })
        return [pscustomobject]$result
    }
    $servers = @($payload)
    if ($null -eq $payload -or @($servers | Where-Object { $null -eq $_.PSObject.Properties['name'] -or $null -eq $_.PSObject.Properties['enabled'] }).Count -gt 0) {
        $result.warnings = @([pscustomobject][ordered]@{ code = 'codex_mcp_observation_contract_invalid'; subject = 'root'; message = 'Codex MCP inventory JSON must contain server objects with name and enabled fields.' })
        return [pscustomobject]$result
    }
    $result.freshness = 'fresh'; $result.coverage = 'complete'
    $result.servers = @($servers | Sort-Object name | ForEach-Object {
            [pscustomobject][ordered]@{
                name = [string]$_.name
                enabled = [bool]$_.enabled
                disabled_reason = [string]$_.disabled_reason
                auth_status = [string]$_.auth_status
                transport_type = [string]$_.transport.type
            }
        })
    return [pscustomobject]$result
}

function Get-CodexDoctorObservation {
    [CmdletBinding()]
    param()

    $result = [ordered]@{ authority = 'codex_doctor_json'; freshness = 'unknown'; coverage = 'platform_na'; schema_version = 0; codex_version = ''; overall_status = 'unknown'; checks = @(); warnings = @() }
    try { $payload = Invoke-CodexCliJson -Arguments @('doctor', '--json') }
    catch {
        $result.warnings = @([pscustomobject][ordered]@{ code = 'codex_doctor_observation_unavailable'; subject = 'codex doctor --json'; message = $_.Exception.Message })
        return [pscustomobject]$result
    }
    if ($null -eq $payload -or $null -eq $payload.PSObject.Properties['schemaVersion'] -or $null -eq $payload.PSObject.Properties['checks']) {
        $result.warnings = @([pscustomobject][ordered]@{ code = 'codex_doctor_observation_contract_invalid'; subject = 'schemaVersion/checks'; message = 'Codex doctor JSON is missing required fields.' })
        return [pscustomobject]$result
    }
    $result.freshness = 'fresh'; $result.coverage = 'complete'; $result.schema_version = [int]$payload.schemaVersion
    $result.codex_version = [string]$payload.codexVersion; $result.overall_status = [string]$payload.overallStatus
    $checks = if ($payload.checks -is [array]) { @($payload.checks) } else { @($payload.checks.PSObject.Properties | ForEach-Object Value) }
    $result.checks = @($checks | Sort-Object id | ForEach-Object {
            $check = $_
            [pscustomobject][ordered]@{ id = [string]$check.id; category = [string]$check.category; status = [string]$check.status; summary = [string]$check.summary }
        })
    return [pscustomobject]$result
}

function Get-CodexHostObservation {
    [CmdletBinding()]
    param($PluginInventory = $null, [object[]]$ExpectedMcpServers = @())

    if ($null -eq $PluginInventory) { $PluginInventory = Get-CodexPluginSkillInventory }
    $mcp = Get-CodexMcpObservation
    $doctor = Get-CodexDoctorObservation
    $expected = @($ExpectedMcpServers | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $observed = @($mcp.servers | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
    return [pscustomobject][ordered]@{
        schema_version = 1
        truth_boundary = 'read_only_cli_observation_not_host_loaded'
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        plugins = [pscustomobject][ordered]@{ authority = [string]$PluginInventory.authority; freshness = [string]$PluginInventory.freshness; coverage = [string]$PluginInventory.coverage; enabled_plugin_ids = @($PluginInventory.enabled_plugin_ids); skill_count = [int]$PluginInventory.skill_count; warnings = @($PluginInventory.warnings) }
        mcp = $mcp
        doctor = $doctor
        configured_mcp_names = $expected
        observed_mcp_names = $observed
        configured_not_observed = @($expected | Where-Object { $_ -notin $observed })
        observed_not_configured = @($observed | Where-Object { $_ -notin $expected })
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}
