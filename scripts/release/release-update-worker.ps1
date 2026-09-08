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
        # The manifest itself is not an entry of its own files list; its
        # integrity is already pinned by the parent-supplied manifest hash.
        if ($relative -eq 'RELEASE-MANIFEST.json') { continue }
        $entry = @($manifest.files | Where-Object { (([string]$_.path).Replace('\', '/')) -eq $relative })[0]
        $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sha -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "Staged payload file was modified after handoff: $relative" }
    }
}

function Get-ReleaseManifestSha256([string]$Root) {
    $manifestPath = Join-Path $Root 'RELEASE-MANIFEST.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-ReleaseUpdateRollback([string]$Current, [string]$Backup, [string]$Failed, [string]$ExpectedManifestSha256) {
    if (-not (Test-Path -LiteralPath $Backup -PathType Container)) {
        return [pscustomobject]@{ status = 'not_started'; message = '' }
    }

    try {
        if (Test-Path -LiteralPath $Current -PathType Container) {
            Move-Item -LiteralPath $Current -Destination $Failed -ErrorAction Stop
        }
        Move-Item -LiteralPath $Backup -Destination $Current -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $Current -PathType Container)) {
            throw 'Rollback completed without restoring the current installation directory.'
        }
        # 恢复成功但交接时没记录到清单哈希（如 current 清单被提前移除的 TOCTOU）：
        # 无法证明恢复内容等于先前安装，必须 fail closed 如实报 rollback_failed。
        if ([string]::IsNullOrWhiteSpace($ExpectedManifestSha256)) {
            throw 'Rollback restored the current installation but no RELEASE-MANIFEST.json hash was recorded to verify it against.'
        }
        $actualManifestSha256 = Get-ReleaseManifestSha256 $Current
        if ($actualManifestSha256 -ne $ExpectedManifestSha256) {
            throw 'Rollback restored a directory whose RELEASE-MANIFEST.json does not match the previous installation.'
        }
        return [pscustomobject]@{ status = 'rolled_back'; message = '' }
    }
    catch {
        return [pscustomobject]@{ status = 'rollback_failed'; message = $_.Exception.Message }
    }
}

$current = [IO.Path]::GetFullPath($CurrentRoot).TrimEnd('\', '/')
$parent = Split-Path -Parent $current
$staged = Assert-SiblingPath $StagedRoot $parent
$backup = Assert-SiblingPath $BackupRoot $parent
$failed = $current + '.failed-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
$previousManifestSha256 = ''

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
    $previousManifestSha256 = Get-ReleaseManifestSha256 $current

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
        # 内联恢复与正式回滚同标准：manifest 比对不可跳过，否则恢复内容未经验证。
        if (-not [string]::IsNullOrWhiteSpace($previousManifestSha256)) {
            $inlineRestoredSha = Get-ReleaseManifestSha256 $current
            if ($inlineRestoredSha -ne $previousManifestSha256) {
                throw ('Inline recovery restored a directory whose RELEASE-MANIFEST.json does not match the previous installation (original failure: {0}).' -f $_.Exception.Message)
            }
        }
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
        $rollback = Invoke-ReleaseUpdateRollback $current $backup $failed $previousManifestSha256
        $receiptMessage = if ([string]$rollback.status -eq 'rollback_failed') {
            "{0}; rollback={1}" -f $message, [string]$rollback.message
        }
        elseif ([string]$rollback.status -eq 'rolled_back') {
            "{0}; rollback completed and previous manifest verified." -f $message
        }
        else { $message }
        $receiptRoot = if (Test-Path -LiteralPath $current -PathType Container) { $current } elseif (Test-Path -LiteralPath $backup -PathType Container) { $backup } else { $parent }
        Write-UpdateWorkerReceipt $receiptRoot ([string]$rollback.status) $receiptMessage
        if ([string]$rollback.status -eq 'rollback_failed') {
            # EAP=Stop 下 Write-Error 会变成终止错误并被外层 catch 误归因为
            # "receipt could not be written"；临时降级让它只作为 stderr 记录。
            $previousEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { Write-Error ("Release update rollback failed; recovery material was preserved: {0}" -f [string]$rollback.message) }
            finally { $ErrorActionPreference = $previousEap }
        }
    }
    catch { Write-Error ("Release update failed and rollback receipt could not be written: {0}" -f $_.Exception.Message) }
    Write-Error ("Release update failed: {0}" -f $message)
    exit 1
}
finally {
    $workerScriptPath = $MyInvocation.MyCommand.Path
    if (-not [string]::IsNullOrWhiteSpace($workerScriptPath) -and (Test-Path -LiteralPath $workerScriptPath -PathType Leaf)) {
        try { Remove-Item -LiteralPath $workerScriptPath -Force -ErrorAction Stop } catch { }
    }
}
