#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CurrentRoot,
    [Parameter(Mandatory)][string]$StagedRoot,
    [Parameter(Mandatory)][string]$BackupRoot,
    [Parameter(Mandatory)][string]$ExpectedVersion,
    [Parameter(Mandatory)][int]$ParentProcessId,
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
    if (-not (Test-Path -LiteralPath $current -PathType Container)) { throw "Current installation is missing: $current" }
    if (-not (Test-Path -LiteralPath $staged -PathType Container)) { throw "Staged release is missing: $staged" }
    if (Test-Path -LiteralPath $backup) { throw "Backup path already exists: $backup" }

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

    $pwsh = (Get-Command pwsh -ErrorAction Stop | Select-Object -First 1).Source
    $installArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $current 'install.ps1'),'-Mode','CurrentUser')
    if ($SyncMcp) { $installArgs += '-SyncMcp' }
    & $pwsh @installArgs
    if ($LASTEXITCODE -ne 0) { throw "Updated release installation failed: exit=$LASTEXITCODE" }
    Write-UpdateWorkerReceipt $current 'updated' 'Release files were replaced and the new installer completed.'
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
