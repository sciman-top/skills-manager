function Parse-PluginCliOptions([object[]]$Tokens, [string[]]$ValueOptions) {
    $result = [ordered]@{ json = $false }
    for ($i = 0; $i -lt @($Tokens).Count; $i++) {
        $token = [string]$Tokens[$i]
        if ($token -eq '--json') { $result.json = $true; continue }
        if ($ValueOptions -contains $token) {
            if ($i + 1 -ge @($Tokens).Count) { throw ('{0} requires a value.' -f $token) }
            $i++; $result[$token.TrimStart('-').Replace('-', '_')] = [string]$Tokens[$i]; continue
        }
        throw ('Unknown plugin option: {0}' -f $token)
    }
    return [pscustomobject]$result
}
function New-PluginCommandResult([string]$Command, $Data, [bool]$Json) {
    $pass = [bool](Get-OperationObjectProperty $Data 'pass')
    $envelope = [pscustomobject][ordered]@{ schema_version = 1; command = $Command; pass = $pass; truth_boundary = 'repo_or_fixture_only'; data = $Data }
    $text = if ($Json) { $envelope | ConvertTo-Json -Depth 40 -Compress } else { '{0}: pass={1}' -f $Command, $pass }
    return [pscustomobject]@{ exit_code = $(if ($pass) { 0 } else { 2 }); output = $text; json = $Json; envelope = $envelope }
}

function Invoke-PluginInventoryCommand([object[]]$Tokens = @()) {
    $options = Parse-PluginCliOptions $Tokens @('--official', '--personal', '--workspace')
    if ([string]::IsNullOrWhiteSpace([string]$options.official)) { throw '--official snapshot is required.' }
    $official = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($options.official)) | ConvertFrom-Json
    $personal = if ([string]::IsNullOrWhiteSpace([string]$options.personal)) { $null } else { [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($options.personal)) | ConvertFrom-Json }
    $workspace = if ([string]::IsNullOrWhiteSpace([string]$options.workspace)) { $null } else { [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($options.workspace)) | ConvertFrom-Json }
    return New-PluginCommandResult 'plugin-inventory' (New-PluginInventoryFromSnapshots $official $personal $workspace) ([bool]$options.json)
}

function Invoke-PluginLintCommand([object[]]$Tokens = @()) {
    $options = Parse-PluginCliOptions $Tokens @('--path')
    $root = [System.IO.Path]::GetFullPath([string]$options.path)
    $manifestPath = Join-Path $root '.codex-plugin\plugin.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Plugin manifest does not exist.' }
    $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    return New-PluginCommandResult 'plugin-lint' (Test-PluginManifestContract $manifest $root $true) ([bool]$options.json)
}

function Invoke-PluginExportCommand([object[]]$Tokens = @()) {
    $options = Parse-PluginCliOptions $Tokens @('--candidate', '--fixture-root', '--out', '--token')
    $candidate = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath([string]$options.candidate)) | ConvertFrom-Json
    $data = Export-PluginFixture $candidate ([string]$options.fixture_root) ([string]$options.out) ([string]$options.token)
    return New-PluginCommandResult 'plugin-export' $data ([bool]$options.json)
}

function Invoke-PluginEvalCommand([object[]]$Tokens = @()) {
    $options = Parse-PluginCliOptions $Tokens @('--path', '--model-snapshot')
    $model = if ([string]::IsNullOrWhiteSpace([string]$options.model_snapshot)) { $null } else { [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($options.model_snapshot)) | ConvertFrom-Json }
    return New-PluginCommandResult 'plugin-eval' (New-PluginEvaluationReport ([System.IO.Path]::GetFullPath([string]$options.path)) $model) ([bool]$options.json)
}
