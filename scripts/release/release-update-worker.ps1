#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CurrentRoot,
    [Parameter(Mandatory)][string]$StagedRoot,
    [Parameter(Mandatory)][string]$BackupRoot,
    [Parameter(Mandatory)][string]$ExpectedVersion,
    [ValidateSet('bootstrap','portable')][string]$PackageType = 'bootstrap',
    [Parameter(Mandatory)][int]$ParentProcessId,
    [Parameter(Mandatory)][string]$ManifestSha256,
    [switch]$SyncMcp
)

$ErrorActionPreference = 'Stop'

function Write-UpdateWorkerReceipt([string]$Root, [string]$Status, [string]$Message) {
    $reports = Join-Path $Root 'reports\release-update'
    New-Item -ItemType Directory -Path $reports -Force | Out-Null
    [pscustomobject][ordered]@{
        schema_version = 1
        command = 'release-update-worker'
        status = $Status
        expected_version = $ExpectedVersion
        current_root = $CurrentRoot
        backup_root = $BackupRoot
        sync_mcp = [bool]$SyncMcp
        package = $PackageType
        completed_at = (Get-Date).ToUniversalTime().ToString('o')
        message = $Message
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reports 'last.json') -Encoding utf8
}

function Assert-SiblingPath([string]$Path, [string]$Parent) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $prefix = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Update path escaped installation parent: $full" }
    return $full
}

# Lexical sibling checks cannot see a junction above a root; reject a reparse
# anywhere in the physical ancestor chain of the swap roots.
function Assert-PhysicalChainHasNoReparse([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if ([IO.Directory]::Exists($cursor) -or [IO.File]::Exists($cursor)) {
            if (([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Update path resolves through a reparse point: $cursor" }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        $cursor = if ($null -ne $parent) { $parent.FullName } else { $null }
    }
}

# Re-verify the staged payload after the parent exits: the wait window is a
# TOCTOU gap in which a same-user process could mutate the staged files or
# swap the manifest. Compare against the manifest hash the parent validated.
function Assert-StagedPayloadIntegrity([string]$StagedRoot, [string]$ExpectedManifestSha) {
    $manifestPath = Join-Path $StagedRoot 'RELEASE-MANIFEST.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Staged RELEASE-MANIFEST.json is missing.' }
    $manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($manifestSha -ne $ExpectedManifestSha) { throw 'Staged RELEASE-MANIFEST.json changed after handoff.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($manifest.files)) {
        [void]$manifestPaths.Add(([string]$entry.path).Replace('\', '/'))
    }
    [void]$manifestPaths.Add('RELEASE-MANIFEST.json')
    $rootFull = [IO.Path]::GetFullPath($StagedRoot)
    $actual = @(Get-ChildItem -LiteralPath $StagedRoot -Recurse -File -Force)
    if ($actual.Count -ne $manifestPaths.Count) { throw 'Staged payload file set does not match the manifest.' }
    foreach ($file in $actual) {
        $relative = [IO.Path]::GetRelativePath($rootFull, $file.FullName).Replace('\', '/')
        if (-not $manifestPaths.Contains($relative)) { throw "Staged payload contains an unmanifested file: $relative" }
        $entry = @($manifest.files | Where-Object { (([string]$_.path).Replace('\', '/')) -eq $relative })[0]
        $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sha -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "Staged payload file was modified after handoff: $relative" }
    }
}

$current = [IO.Path]::GetFullPath($CurrentRoot).TrimEnd('\', '/')
$parent = Split-Path -Parent $current
$staged = Assert-SiblingPath $StagedRoot $parent
$backup = Assert-SiblingPath $BackupRoot $parent
$failed = $current + '.failed-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')

try {
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        if (-not (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Seconds 1
    }
    if (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue) { throw 'The initiating release-update process did not exit before timeout.' }
    Assert-PhysicalChainHasNoReparse $current
    Assert-PhysicalChainHasNoReparse $staged
    Assert-PhysicalChainHasNoReparse $backup
    if (-not (Test-Path -LiteralPath $current -PathType Container)) { throw "Current installation is missing: $current" }
    if (-not (Test-Path -LiteralPath $staged -PathType Container)) { throw "Staged release is missing: $staged" }
    if (Test-Path -LiteralPath $backup) { throw "Backup path already exists: $backup" }
    Assert-StagedPayloadIntegrity $staged $ManifestSha256

    $movedCurrent = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        try {
            Move-Item -LiteralPath $current -Destination $backup -ErrorAction Stop
            $movedCurrent = $true
            break
        }
        catch {
            if ($attempt -eq 59) { throw }
            Start-Sleep -Seconds 1
        }
    }
    if (-not $movedCurrent) { throw 'Current installation could not be released for replacement.' }
    try {
        Move-Item -LiteralPath $staged -Destination $current -ErrorAction Stop
    }
    catch {
        Move-Item -LiteralPath $backup -Destination $current -ErrorAction Stop
        throw
    }

    if ($PackageType -eq 'bootstrap') {
        $pwsh = (Get-Command pwsh -ErrorAction Stop | Select-Object -First 1).Source
        $installArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $current 'install.ps1'),'-Mode','CurrentUser')
        if ($SyncMcp) { $installArgs += '-SyncMcp' }
        & $pwsh @installArgs
        if ($LASTEXITCODE -ne 0) { throw "Updated release installation failed: exit=$LASTEXITCODE" }
        Write-UpdateWorkerReceipt $current 'updated' 'Release files were replaced and the new bootstrap installer completed.'
    }
    else {
        Write-UpdateWorkerReceipt $current 'updated' 'Portable Release files were replaced; no Git-based installer was invoked.'
    }
}
catch {
    $message = $_.Exception.Message
    try {
        if ((Test-Path -LiteralPath $backup -PathType Container) -and (Test-Path -LiteralPath $current -PathType Container)) {
            Move-Item -LiteralPath $current -Destination $failed -ErrorAction Stop
            Move-Item -LiteralPath $backup -Destination $current -ErrorAction Stop
        }
        $receiptRoot = if (Test-Path -LiteralPath $current -PathType Container) { $current } elseif (Test-Path -LiteralPath $backup -PathType Container) { $backup } else { $parent }
        Write-UpdateWorkerReceipt $receiptRoot 'rolled_back_or_not_started' $message
    }
    catch { Write-Error ("Release update failed and rollback receipt could not be written: {0}" -f $_.Exception.Message) }
    Write-Error ("Release update failed: {0}" -f $message)
    exit 1
}
