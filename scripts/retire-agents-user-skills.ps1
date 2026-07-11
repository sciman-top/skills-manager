[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path $HOME ".agents\skills"),
    [string]$ArchiveRoot = (Join-Path $HOME ".agents\retired"),
    [string]$ReportRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) "reports\skill-retirement"),
    [string]$ManagedSourceRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) "agent"),
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd("\", "/")
}

function Assert-PathInside([string]$Path, [string]$Parent, [string]$Label) {
    $fullPath = Get-FullPath $Path
    $fullParent = Get-FullPath $Parent
    $prefix = $fullParent + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label 必须位于 $fullParent 内：$fullPath"
    }
    return $fullPath
}

function Get-StringSha256([string]$Value) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-ManagedProjectionLink([System.IO.DirectoryInfo]$Directory, [string]$ManagedRoot) {
    if (-not ($Directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { return $false }
    $targetValue = $Directory.PSObject.Properties["Target"].Value
    if ($targetValue -is [array]) { $targetValue = $targetValue[0] }
    if ([string]::IsNullOrWhiteSpace([string]$targetValue)) { return $false }
    $target = Get-FullPath ([string]$targetValue)
    $prefix = (Get-FullPath $ManagedRoot) + [System.IO.Path]::DirectorySeparatorChar
    return $target.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-DirectoryInventory([System.IO.DirectoryInfo]$Directory, [string]$Destination) {
    $base = $Directory.FullName.TrimEnd("\", "/")
    $parts = [System.Collections.Generic.List[string]]::new()
    $files = @(Get-ChildItem -LiteralPath $base -Recurse -File -Force | Sort-Object FullName)
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($base.Length).TrimStart("\", "/").Replace("\", "/")
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $parts.Add("$relative|$hash")
    }
    return [pscustomobject][ordered]@{
        name = $Directory.Name
        source_path = $Directory.FullName
        archive_path = $Destination
        file_count = $files.Count
        skill_md_count = @($files | Where-Object Name -eq "SKILL.md").Count
        total_bytes = [long](($files | Measure-Object Length -Sum).Sum)
        package_hash = Get-StringSha256 ($parts -join "`n")
    }
}

$agentsRoot = Get-FullPath (Join-Path $HOME ".agents")
$source = Assert-PathInside $SourceRoot $agentsRoot "SourceRoot"
$archive = Assert-PathInside $ArchiveRoot $agentsRoot "ArchiveRoot"
$reportBase = Get-FullPath $ReportRoot
$managedSource = Get-FullPath $ManagedSourceRoot

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "技能根不存在：$source"
}
$systemRoot = Join-Path $source ".system"
if (-not (Test-Path -LiteralPath $systemRoot -PathType Container)) {
    throw "缺少必须保留的系统技能目录：$systemRoot"
}

$allUserEntries = @(Get-ChildItem -LiteralPath $source -Directory -Force | Where-Object Name -ne ".system" | Sort-Object Name)
$managedLinks = @($allUserEntries | Where-Object { Test-ManagedProjectionLink $_ $managedSource })
$candidates = @($allUserEntries | Where-Object { -not (Test-ManagedProjectionLink $_ $managedSource) })
$runId = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$archivePath = Join-Path $archive "skills-user-$runId"
$reportPath = Join-Path (Join-Path $reportBase $runId) "manifest.json"

if (Test-Path -LiteralPath $archivePath) {
    throw "归档目标已存在：$archivePath"
}

$entries = @($candidates | ForEach-Object { Get-DirectoryInventory $_ (Join-Path $archivePath $_.Name) })
$manifest = [ordered]@{
    schema_version = 1
    run_id = $runId
    generated_at = (Get-Date).ToString("o")
    mode = if ($Apply) { "apply" } else { "dry_run" }
    status = if ($Apply) { "moving" } else { "planned" }
    source_root = $source
    archive_root = $archivePath
    preserved_paths = @($systemRoot)
    preserved_managed_link_count = $managedLinks.Count
    directory_count = $entries.Count
    file_count = [long](($entries | Measure-Object file_count -Sum).Sum)
    skill_md_count = [long](($entries | Measure-Object skill_md_count -Sum).Sum)
    total_bytes = [long](($entries | Measure-Object total_bytes -Sum).Sum)
    entries = $entries
    rollback = "Move every archive_path back to source_path after checking that no source_path exists."
}

New-Item -ItemType Directory -Path (Split-Path $reportPath -Parent) -Force | Out-Null
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8

if ($Apply) {
    New-Item -ItemType Directory -Path $archivePath -Force | Out-Null
    foreach ($entry in $entries) {
        if (Test-Path -LiteralPath $entry.archive_path) { throw "拒绝覆盖归档项：$($entry.archive_path)" }
        if (-not (Test-Path -LiteralPath $entry.source_path -PathType Container)) { throw "源目录已消失：$($entry.source_path)" }
        Move-Item -LiteralPath $entry.source_path -Destination $entry.archive_path
    }

    $remaining = @(Get-ChildItem -LiteralPath $source -Directory -Force | Where-Object Name -ne ".system")
    $moved = @(Get-ChildItem -LiteralPath $archivePath -Directory -Force)
    if ($remaining.Count -ne 0 -or $moved.Count -ne $entries.Count) {
        throw "退役后核验失败：remaining=$($remaining.Count), moved=$($moved.Count), expected=$($entries.Count)"
    }
    $manifest.status = "applied"
    $manifest.completed_at = (Get-Date).ToString("o")
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
}

[pscustomobject]@{
    success = $true
    applied = [bool]$Apply
    directory_count = $entries.Count
    file_count = $manifest.file_count
    skill_md_count = $manifest.skill_md_count
    total_bytes = $manifest.total_bytes
    archive_path = $archivePath
    report_path = $reportPath
}
