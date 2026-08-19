#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BackupRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\skill-projection\host-backups')
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$backupRootFull = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\', '/')
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'reports\skill-projection\host-backups')).TrimEnd('\', '/')
$agentRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'agent')).TrimEnd('\', '/')

if (-not [string]::Equals($backupRootFull, $expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "BackupRoot must equal the managed backup root: $expectedRoot"
}
if (-not (Test-Path -LiteralPath $backupRootFull -PathType Container)) {
    [pscustomobject]@{ schema_version=1; command='cleanup-stale-projection-backups'; removed=0; remaining_stale=0; changed=$false } | ConvertTo-Json
    return
}

$backupPrefix = $backupRootFull + [IO.Path]::DirectorySeparatorChar
$agentPrefix = $agentRoot + [IO.Path]::DirectorySeparatorChar
$stale = [Collections.Generic.List[object]]::new()

foreach ($item in @(Get-ChildItem -LiteralPath $backupRootFull -Recurse -Force -ErrorAction SilentlyContinue)) {
    if ($item.LinkType -ne 'Junction') { continue }
    $targetText = [string]@($item.Target)[0]
    if ([string]::IsNullOrWhiteSpace($targetText) -or (Test-Path -LiteralPath $targetText)) { continue }

    $fullPath = [IO.Path]::GetFullPath($item.FullName)
    $targetPath = [IO.Path]::GetFullPath($targetText)
    if (-not $fullPath.StartsWith($backupPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Stale junction escaped the managed backup root: $fullPath"
    }
    if (-not $targetPath.StartsWith($agentPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Stale junction has an unexpected target: $targetPath"
    }
    $stale.Add([pscustomobject]@{ path=$fullPath; target=$targetPath }) | Out-Null
}

$removed = 0
foreach ($entry in @($stale.ToArray() | Sort-Object path -Descending)) {
    if ($PSCmdlet.ShouldProcess([string]$entry.path, 'Remove stale projection-backup junction')) {
        $junction = Get-Item -LiteralPath ([string]$entry.path) -Force
        if (($junction.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
            $junction.Attributes = ($junction.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly))
        }
        [IO.Directory]::Delete([string]$entry.path, $false)
        $removed++
    }
}

$remaining = 0
foreach ($item in @(Get-ChildItem -LiteralPath $backupRootFull -Recurse -Force -ErrorAction SilentlyContinue)) {
    if ($item.LinkType -eq 'Junction') {
        $targetText = [string]@($item.Target)[0]
        if (-not [string]::IsNullOrWhiteSpace($targetText) -and -not (Test-Path -LiteralPath $targetText)) { $remaining++ }
    }
}

[pscustomobject][ordered]@{
    schema_version = 1
    command = 'cleanup-stale-projection-backups'
    discovered = $stale.Count
    removed = $removed
    remaining_stale = $remaining
    changed = ($removed -gt 0)
} | ConvertTo-Json
