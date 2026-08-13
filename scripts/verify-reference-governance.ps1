[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root 'references\reference-shelf.manifest.json'
$provenancePath = Join-Path $root 'overrides\patches\provenance.json'
$findings = [Collections.Generic.List[string]]::new()

function Add-Finding([string]$Message) { $findings.Add($Message) | Out-Null }

function Test-ContainedReferenceRelativePath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or [IO.Path]::IsPathRooted($Value)) { return $false }
    $segments = @($Value.Replace('\', '/').Split('/', [StringSplitOptions]::RemoveEmptyEntries))
    return $segments.Count -gt 0 -and @($segments | Where-Object { $_ -in @('.', '..') }).Count -eq 0
}

function Test-ReferenceLifecycleState([string]$Tier, [string]$Status) {
    return ($Tier -eq 'core-mainline' -or $Tier -eq 'secondary') -and $Status -eq 'active'
}

try { $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json }
catch { throw "reference shelf manifest cannot be parsed: $($_.Exception.Message)" }

if ([int]$manifest.schema_version -ne 1) { Add-Finding 'reference manifest schema_version must be 1' }
$expectedRoot = 'D:\CODE\external\skills-manager-references'
if ([string]$manifest.references_root -ne $expectedRoot) { Add-Finding "reference manifest must use $expectedRoot" }

$names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$byName = @{}
foreach ($repo in @($manifest.repos)) {
    $name = ([string]$repo.name).Trim()
    $relativePath = ([string]$repo.relative_path).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { Add-Finding 'reference repo name is required'; continue }
    if (-not $names.Add($name)) { Add-Finding "duplicate reference repo name: $name" }
    if (-not (Test-ContainedReferenceRelativePath $relativePath)) { Add-Finding "invalid reference path: $name" }
    elseif (-not $paths.Add($relativePath.Replace('\', '/').TrimEnd('/'))) { Add-Finding "duplicate reference path: $relativePath" }
    if (-not (Test-ReferenceLifecycleState ([string]$repo.tier) ([string]$repo.status))) { Add-Finding "invalid reference lifecycle: $name" }
    if ([string]$repo.tier -eq 'core-mainline' -and -not $relativePath.Replace('\', '/').StartsWith('core/', [StringComparison]::OrdinalIgnoreCase)) { Add-Finding "core repo must use core/: $name" }
    if ([string]$repo.tier -eq 'secondary' -and -not $relativePath.Replace('\', '/').StartsWith('secondary/', [StringComparison]::OrdinalIgnoreCase)) { Add-Finding "secondary repo must use secondary/: $name" }
    if ([string]::IsNullOrWhiteSpace([string]$repo.upstream_url)) { Add-Finding "reference upstream_url is required: $name" }
    $byName[$name] = $repo
}

$defaults = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @($manifest.default_refresh_set)) {
    if (-not $defaults.Add([string]$name)) { Add-Finding "duplicate default reference: $name"; continue }
    if (-not $byName.ContainsKey([string]$name)) { Add-Finding "unknown default reference: $name"; continue }
    if ([string]$byName[[string]$name].tier -ne 'core-mainline') { Add-Finding "default reference must be core-mainline: $name" }
}

try { $provenance = Get-Content -Raw -LiteralPath $provenancePath -Encoding UTF8 | ConvertFrom-Json }
catch { throw "patch provenance cannot be parsed: $($_.Exception.Message)" }
if ([int]$provenance.schema_version -ne 1) { Add-Finding 'patch provenance schema_version must be 1' }
$patchNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($patch in @($provenance.patches)) {
    $name = [string]$patch.name
    if (-not $patchNames.Add($name)) { Add-Finding "duplicate patch provenance: $name" }
    foreach ($field in @('upstream_repo', 'upstream_path', 'license', 'local_delta_reason')) {
        if ([string]::IsNullOrWhiteSpace([string]$patch.$field)) { Add-Finding "patch provenance missing ${field}: $name" }
    }
    foreach ($field in @('base_revision', 'reviewed_revision')) {
        if ([string]$patch.$field -notmatch '^[0-9a-fA-F]{40}$') { Add-Finding "patch ${field} must be a full commit: $name" }
    }
}
foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $root 'overrides\patches') -Directory)) {
    if (-not $patchNames.Contains($directory.Name)) { Add-Finding "patch directory lacks provenance: $($directory.Name)" }
}
foreach ($name in $patchNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $root "overrides\patches\$name\SKILL.md") -PathType Leaf)) { Add-Finding "patch provenance points to a missing skill: $name" }
}

if ($findings.Count -gt 0) {
    $findings | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    throw "reference governance verification failed with $($findings.Count) finding(s)"
}

Write-Host "Reference governance OK: repos=$($names.Count), default=$($defaults.Count), patches=$($patchNames.Count)" -ForegroundColor Green
