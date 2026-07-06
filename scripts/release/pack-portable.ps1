[CmdletBinding()]
param(
    [string]$Root = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Out = "",
    [string]$Version = "",
    [switch]$SkipVerification,
    [switch]$AllowDirtyWorktree
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Path 不能为空。"
    }
    return [System.IO.Path]::GetFullPath($Path)
}

function ConvertTo-PortableRelativePath([string]$Base, [string]$Path) {
    $baseFull = Resolve-FullPath $Base
    $pathFull = Resolve-FullPath $Path
    $baseUri = [Uri]($baseFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri]$pathFull
    $relative = $baseUri.MakeRelativeUri($pathUri).ToString()
    return [Uri]::UnescapeDataString($relative).Replace("\", "/")
}

function Test-DeniedPortablePath([string]$RelativePath) {
    $rel = $RelativePath.Replace("\", "/").TrimStart("/")
    $deniedPrefixes = @(
        ".git/",
        ".claude/",
        ".codex/",
        ".gemini/",
        ".trae/",
        ".txn/",
        ".worktrees/",
        "worktrees/",
        ".playwright-mcp/",
        "agent/",
        "vendor/",
        "imports/",
        "reports/",
        "artifacts/"
    )
    foreach ($prefix in $deniedPrefixes) {
        if ($rel.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or $rel.Equals($prefix.TrimEnd("/"), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $deniedPatterns = @(
        "^build\.log(?:\.\d+)?$",
        "^acl-backup-git-.*\.txt$",
        "^\.build-cache\.json$",
        "^docs/change-evidence/\d{8}-audit-runtime-.*\.md$"
    )
    foreach ($pattern in $deniedPatterns) {
        if ($rel -match $pattern) {
            return $true
        }
    }
    return $false
}

function Add-PortableFile([System.Collections.Generic.HashSet[string]]$Files, [string]$RootPath, [string]$RelativePath) {
    $rel = $RelativePath.Replace("\", "/").TrimStart("/")
    if (Test-DeniedPortablePath $rel) {
        return
    }
    $fullPath = Join-Path $RootPath ($rel.Replace("/", [System.IO.Path]::DirectorySeparatorChar))
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        [void]$Files.Add($rel)
    }
}

function Add-PortableDirectory([System.Collections.Generic.HashSet[string]]$Files, [string]$RootPath, [string]$RelativePath) {
    $dir = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        return
    }
    Get-ChildItem -LiteralPath $dir -Recurse -Force -File | ForEach-Object {
        $rel = ConvertTo-PortableRelativePath $RootPath $_.FullName
        if (-not (Test-DeniedPortablePath $rel)) {
            [void]$Files.Add($rel)
        }
    }
}

function Get-PortableFileSet([string]$RootPath) {
    $files = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $rootFiles = @(
        ".editorconfig",
        ".geminiignore",
        ".gitignore",
        ".gitlab-ci.yml",
        ".ignore",
        "AGENTS.md",
        "CLAUDE.md",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "GEMINI.md",
        "Initialize-WindowsProcessEnvironment.ps1",
        "README.en.md",
        "README.md",
        "RELEASE_TEMPLATE.md",
        "SECURITY.md",
        "audit-targets.json",
        "azure-pipelines.yml",
        "build.ps1",
        "install.ps1",
        "skills.cmd",
        "skills.json",
        "skills.lock.json",
        "skills.ps1"
    )
    foreach ($file in $rootFiles) {
        Add-PortableFile $files $RootPath $file
    }

    foreach ($dir in @(".github", "src", "tests", "overrides", "scripts\quality", "scripts\release", "docs\governance", "docs\plans", "docs\runbooks", "docs\superpowers")) {
        Add-PortableDirectory $files $RootPath $dir
    }

    $scriptRoot = Join-Path $RootPath "scripts"
    if (Test-Path -LiteralPath $scriptRoot -PathType Container) {
        Get-ChildItem -LiteralPath $scriptRoot -File -Force | ForEach-Object {
            Add-PortableFile $files $RootPath (ConvertTo-PortableRelativePath $RootPath $_.FullName)
        }
    }

    foreach ($file in @(
        ".githooks\pre-commit",
        ".governed-ai\dependency-baseline.json",
        ".governed-ai\quick-test-slice.prompt.md",
        ".governed-ai\quick-test-slice.recommendation.json",
        "docs\governed-runtime-batch-validation.md",
        "docs\change-evidence\template.md",
        "references\README.md",
        "references\reference-shelf.manifest.json",
        "references\updates\README.md"
    )) {
        Add-PortableFile $files $RootPath $file
    }

    return @($files | Sort-Object)
}

function Get-GitDirtyPortablePaths([string]$RootPath, [string[]]$PortableFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $RootPath ".git"))) {
        return @()
    }

    $portableSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($PortableFiles)) {
        [void]$portableSet.Add($file.Replace("\", "/"))
    }

    Push-Location $RootPath
    try {
        $status = @(git status --porcelain --untracked-files=all 2>$null)
        if ($LASTEXITCODE -ne 0) {
            throw "git status failed; cannot prove portable package dirty state."
        }
    }
    finally {
        Pop-Location
    }

    $dirty = @()
    foreach ($line in $status) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) {
            continue
        }
        $pathText = $line.Substring(3).Trim().Trim('"')
        if ($pathText -match " -> ") {
            $pathText = ($pathText -split " -> ")[-1].Trim().Trim('"')
        }
        $rel = $pathText.Replace("\", "/")
        if ($portableSet.Contains($rel)) {
            $dirty += $rel
        }
    }
    return @($dirty | Sort-Object -Unique)
}

function Invoke-ReleaseVerification([string]$RootPath) {
    Push-Location $RootPath
    try {
        & .\build.ps1
        if ($LASTEXITCODE -ne 0) { throw "build.ps1 failed." }
        & .\skills.ps1 发现
        if ($LASTEXITCODE -ne 0) { throw "skills.ps1 发现 failed." }
        & .\skills.ps1 doctor --strict --threshold-ms 8000
        if ($LASTEXITCODE -ne 0) { throw "skills.ps1 doctor failed." }
        & .\skills.ps1 构建生效
        if ($LASTEXITCODE -ne 0) { throw "skills.ps1 构建生效 failed." }
    }
    finally {
        Pop-Location
    }
}

$rootPath = Resolve-FullPath $Root
if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    throw ("Root 不存在：{0}" -f $rootPath)
}

if ([string]::IsNullOrWhiteSpace($Out)) {
    $Out = Join-Path $rootPath "artifacts\release"
}
$outPath = Resolve-FullPath $Out

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = "snapshot-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")
}
if ($Version -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]*$") {
    throw ("Version 只能包含字母、数字、点、下划线和连字符：{0}" -f $Version)
}

$portableFiles = @(Get-PortableFileSet $rootPath)
if ($portableFiles.Count -eq 0) {
    throw "未找到可打包文件。"
}

$dirtyPortablePaths = @(Get-GitDirtyPortablePaths $rootPath $portableFiles)
if ($dirtyPortablePaths.Count -gt 0 -and -not $AllowDirtyWorktree) {
    throw ("可迁移包白名单内存在未提交改动，请先提交或传入 -AllowDirtyWorktree：{0}" -f ($dirtyPortablePaths -join ", "))
}

if (-not $SkipVerification) {
    Invoke-ReleaseVerification $rootPath
}

$packageName = "skills-manager-{0}-portable" -f $Version
$stagingParent = Join-Path $outPath "_staging"
$stagingRoot = Join-Path $stagingParent $packageName
$zipPath = Join-Path $outPath ("{0}.zip" -f $packageName)
$manifestPath = Join-Path $outPath ("{0}.manifest.json" -f $packageName)
$checksumPath = Join-Path $outPath "SHA256SUMS.txt"

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
New-Item -ItemType Directory -Path $outPath -Force | Out-Null

foreach ($rel in $portableFiles) {
    if (Test-DeniedPortablePath $rel) {
        throw ("内部错误：禁止路径进入可迁移包：{0}" -f $rel)
    }
    $source = Join-Path $rootPath ($rel.Replace("/", [System.IO.Path]::DirectorySeparatorChar))
    $dest = Join-Path $stagingRoot ($rel.Replace("/", [System.IO.Path]::DirectorySeparatorChar))
    $destParent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($dest))
    if (-not (Test-Path -LiteralPath $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $dest -Force
}

$manifest = [pscustomobject]@{
    package_name = $packageName
    version = $Version
    generated_at = (Get-Date).ToString("o")
    root = $rootPath
    included_files = $portableFiles
    excluded_roots = @("agent", "vendor", "imports", "reports", ".codex", ".claude", ".gemini", ".trae", ".txn", ".worktrees", "artifacts")
    install_entry = "install.ps1"
    portable_entry = "skills.cmd"
}
$manifestJson = $manifest | ConvertTo-Json -Depth 8
Set-Content -LiteralPath (Join-Path $stagingRoot "PORTABLE-MANIFEST.json") -Value $manifestJson -Encoding UTF8
Set-Content -LiteralPath $manifestPath -Value $manifestJson -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagingRoot, $zipPath)

$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
Set-Content -LiteralPath $checksumPath -Value ("{0}  {1}" -f $hash.Hash.ToLowerInvariant(), (Split-Path -Leaf $zipPath)) -Encoding UTF8

Remove-Item -LiteralPath $stagingParent -Recurse -Force

Write-Host ("Portable package: {0}" -f $zipPath)
Write-Host ("Manifest: {0}" -f $manifestPath)
Write-Host ("SHA256: {0}" -f $hash.Hash.ToLowerInvariant())
