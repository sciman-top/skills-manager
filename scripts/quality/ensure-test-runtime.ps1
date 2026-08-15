#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$CacheRoot = (Join-Path (Join-Path $PSScriptRoot '..\..') 'reports\test-runtime'),
    [switch]$ExportToGitHubEnv
)

$ErrorActionPreference = 'Stop'
$version = '6.1.0'
$expectedSha256 = '0207a75ea09f81b27c1ded44898b2bb3c845bafa02045bd64a39e26a53ca41b4'
$packageUri = "https://www.powershellgallery.com/api/v2/package/Pester/$version"
$cacheRootPath = [IO.Path]::GetFullPath($CacheRoot)
$moduleBase = Join-Path $cacheRootPath 'modules'
$packagePath = Join-Path $cacheRootPath "Pester.$version.nupkg"

function Remove-TestRuntimeTemporaryDirectory([string]$Path, [string]$ExpectedParent) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedParent = [IO.Path]::GetFullPath($ExpectedParent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedPath.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove test-runtime directory outside cache root: $resolvedPath"
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    $null = New-Item -ItemType Directory -Path $cacheRootPath -Force
    $downloadPath = "$packagePath.$([guid]::NewGuid().ToString('N')).downloading"
    try {
        Invoke-WebRequest -Uri $packageUri -OutFile $downloadPath -UseBasicParsing
        $downloadSha256 = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($downloadSha256 -cne $expectedSha256) {
            throw "Pester package hash mismatch: expected=$expectedSha256 actual=$downloadSha256"
        }
        try {
            [IO.File]::Move($downloadPath, $packagePath, $false)
        }
        catch {
            if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw }
        }
    }
    finally {
        if (Test-Path -LiteralPath $downloadPath -PathType Leaf) {
            Remove-Item -LiteralPath $downloadPath -Force
        }
    }
}
$actualSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -cne $expectedSha256) {
    Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
    throw "Pester package hash mismatch: expected=$expectedSha256 actual=$actualSha256"
}

$moduleParent = Join-Path $moduleBase 'Pester'
$moduleRoot = Join-Path $moduleParent ("{0}-{1}" -f $version, $expectedSha256)
$manifest = Join-Path $moduleRoot 'Pester.psd1'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    if (Test-Path -LiteralPath $moduleRoot) {
        throw "Pester cache is incomplete: $moduleRoot"
    }

    $null = New-Item -ItemType Directory -Path $moduleParent -Force
    $extractRoot = Join-Path $moduleParent (".{0}-{1}.extracting" -f $version, ([guid]::NewGuid().ToString('N')))
    try {
        $null = New-Item -ItemType Directory -Path $extractRoot
        [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractRoot)
        $extractedManifest = Join-Path $extractRoot 'Pester.psd1'
        if (-not (Test-Path -LiteralPath $extractedManifest -PathType Leaf)) {
            throw 'Verified Pester package does not contain Pester.psd1.'
        }
        try {
            [IO.Directory]::Move($extractRoot, $moduleRoot)
        }
        catch {
            if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw }
        }
    }
    finally {
        Remove-TestRuntimeTemporaryDirectory $extractRoot $moduleParent
    }
}

Import-Module -Name $manifest -Force
if ((Get-Module Pester).Version -ne [version]$version) {
    throw "Verified Pester $version did not load."
}
if ($ExportToGitHubEnv) {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) { throw 'GITHUB_ENV is required with -ExportToGitHubEnv.' }
    "PESTER_610_MANIFEST=$manifest" | Out-File -LiteralPath $env:GITHUB_ENV -Encoding utf8 -Append
}

$manifest
