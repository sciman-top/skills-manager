param(
    [ValidateSet("observe", "enforce")]
    [string]$Mode = "observe",
    [string]$ConfigPath,
    [string]$SchemaPath,
    [string]$ReportPath
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $repoRoot "skills.json" }
if ([string]::IsNullOrWhiteSpace($SchemaPath)) { $SchemaPath = Join-Path $repoRoot "config\skills.schema.json" }

function New-SafeFinding([string]$code, [string]$path, [string]$message) {
    return [pscustomobject]@{ code = $code; path = $path; message = $message }
}
function ConvertTo-SafeContractFinding([string]$message) {
    $path = "$"
    $code = "runtime_contract_error"
    if ($message -match "schema_version") { $path = "$.schema_version"; $code = "schema_version_invalid" }
    elseif ($message -match "sync_mode") { $path = "$.sync_mode"; $code = "enum_invalid" }
    elseif ($message -match "mapping\.from") { $path = "$.mappings[].from"; $code = "unsafe_relative_path" }
    elseif ($message -match "mapping\.to") { $path = "$.mappings[].to"; $code = "unsafe_relative_path" }
    elseif ($message -match "import\.skill") { $path = "$.imports[].skill"; $code = "unsafe_relative_path" }
    elseif ($message -match "mcp_server\.transport") { $path = "$.mcp_servers[].transport"; $code = "enum_invalid" }
    elseif ($message -match "schema v1") {
        foreach ($fieldName in @("vendors", "targets", "mappings", "imports", "mcp_servers", "mcp_targets", "update_force", "skill_projection", "mcp_profiles")) {
            if ($message.Contains($fieldName)) { $path = "$.{0}" -f $fieldName; break }
        }
        $code = "type_mismatch"
    }
    return New-SafeFinding $code $path "Configuration violates the declared contract; values are redacted."
}

$findings = New-Object System.Collections.Generic.List[object]
$observations = New-Object System.Collections.Generic.List[object]
$beforeHash = $null
$afterHash = $null
$version = $null
$versionSource = $null

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    $findings.Add((New-SafeFinding "config_missing" "$" "Configuration file is missing.")) | Out-Null
}
elseif (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
    $findings.Add((New-SafeFinding "schema_missing" "$" "Configuration schema file is missing.")) | Out-Null
}
else {
    $beforeHash = (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
    try { $null = Get-Content -LiteralPath $SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { $findings.Add((New-SafeFinding "schema_invalid_json" "$" "Configuration schema is not valid JSON.")) | Out-Null }

    try {
        $coreSource = Get-Content -LiteralPath (Join-Path $repoRoot "src\Core.ps1") -Raw -Encoding UTF8
        $configSource = Get-Content -LiteralPath (Join-Path $repoRoot "src\Config.ps1") -Raw -Encoding UTF8
        . ([scriptblock]::Create($coreSource))
        . ([scriptblock]::Create($configSource))
        $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
        $clean = $raw -replace "(?m)^\s*//.*", ""
        $cfg = $clean | ConvertFrom-Json
        $contract = Get-CfgVersionedContractReport $cfg
        $version = $contract.schema.effective_version
        $versionSource = $contract.schema.source
        foreach ($observation in @($contract.observations)) { $observations.Add($observation) | Out-Null }
        foreach ($errorText in @($contract.errors)) { $findings.Add((ConvertTo-SafeContractFinding ([string]$errorText))) | Out-Null }
    }
    catch {
        $findings.Add((New-SafeFinding "config_invalid_json" "$" "Configuration is not valid JSON or could not be evaluated.")) | Out-Null
    }
    $afterHash = (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($beforeHash -ne $afterHash) {
        $findings.Add((New-SafeFinding "input_modified" "$" "Validator modified its input, which is forbidden.")) | Out-Null
    }
}

$valid = ($findings.Count -eq 0)
$result = [ordered]@{
    schema_version = 1
    mode = $Mode
    valid = $valid
    pass = ($valid -or $Mode -eq "observe")
    would_block = (-not $valid)
    config_version = $version
    version_source = $versionSource
    config_sha256_before = $beforeHash
    config_sha256_after = $afterHash
    finding_count = $findings.Count
    observation_count = $observations.Count
    findings = @($findings.ToArray())
    observations = @($observations.ToArray())
}
$json = $result | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $parent = Split-Path -Parent $ReportPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($ReportPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Output $json
if (-not $valid -and $Mode -eq "enforce") { exit 1 }
exit 0
