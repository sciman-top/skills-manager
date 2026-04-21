[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [string]$SourceScript = (Join-Path $PSScriptRoot "git-acl-guard.ps1"),
    [string]$ScanRoot = "D:\CODE",
    [string[]]$RepoRoots,
    [switch]$IncludeSourceRepo,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "[sync-git-acl-guard] $Message"
}

function Get-RepositoriesUnderRoot {
    param([string]$RootPath)

    $root = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
    $repos = New-Object "System.Collections.Generic.List[string]"
    $pending = New-Object "System.Collections.Generic.Queue[string]"
    $pending.Enqueue($root)

    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        $children = $null

        try {
            $children = Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop
        }
        catch {
            continue
        }

        $hasGitMarker = @($children | Where-Object { $_.Name -eq ".git" }).Count -gt 0
        if ($hasGitMarker) {
            $repos.Add($current)
            continue
        }

        foreach ($child in $children) {
            if (-not $child.PSIsContainer) { continue }
            if ([bool]($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
            $pending.Enqueue($child.FullName)
        }
    }

    return @($repos | Sort-Object -Unique)
}

if (-not (Test-Path -LiteralPath $SourceScript -PathType Leaf)) {
    throw "Source script not found: $SourceScript"
}

$sourceResolved = (Resolve-Path -LiteralPath $SourceScript).Path
$sourceRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

$targets = @()
if ($RepoRoots -and $RepoRoots.Count -gt 0) {
    foreach ($repo in $RepoRoots) {
        $targets += (Resolve-Path -LiteralPath $repo -ErrorAction Stop).Path
    }
}
else {
    $targets = Get-RepositoriesUnderRoot -RootPath $ScanRoot
}

$targets = @($targets | Sort-Object -Unique)
if (-not $IncludeSourceRepo) {
    $targets = @($targets | Where-Object { $_ -ne $sourceRepoRoot })
}

if ($targets.Count -eq 0) {
    Write-Step "No target repositories found."
    exit 0
}

Write-Step ("Source script: {0}" -f $sourceResolved)
Write-Step ("Targets: {0}" -f $targets.Count)

$sourceHash = (Get-FileHash -LiteralPath $sourceResolved -Algorithm SHA256).Hash
$copied = 0
$skipped = 0
$pending = 0
foreach ($repoRoot in $targets) {
    $destDir = Join-Path $repoRoot "scripts"
    $destPath = Join-Path $destDir "git-acl-guard.ps1"

    if ($DryRun) {
        Write-Step ("DRY-RUN copy -> {0}" -f $destPath)
        continue
    }

    if (-not (Test-Path -LiteralPath $destDir)) {
        if ($PSCmdlet.ShouldProcess($destDir, "Create scripts directory")) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        else {
            Write-Step ("Skip directory creation by WhatIf/Confirm: {0}" -f $destDir)
        }
    }

    $destHash = if (Test-Path -LiteralPath $destPath -PathType Leaf) {
        (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash
    }
    else {
        ""
    }

    if ($sourceHash -eq $destHash) {
        Write-Step ("Skip unchanged: {0}" -f $destPath)
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($destPath, "Copy git-acl-guard.ps1")) {
        Copy-Item -LiteralPath $sourceResolved -Destination $destPath -Force
        Write-Step ("Copied: {0}" -f $destPath)
        $copied++
    }
    else {
        Write-Step ("Skip copy by WhatIf/Confirm: {0}" -f $destPath)
        $pending++
    }
}

if ($DryRun) {
    Write-Step "Dry-run completed."
    exit 0
}

Write-Step ("Done. copied={0}, skipped={1}, pending={2}" -f $copied, $skipped, $pending)
