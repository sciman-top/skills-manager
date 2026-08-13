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
