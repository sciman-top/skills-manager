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
$moduleBase = Join-Path ([IO.Path]::GetFullPath($CacheRoot)) 'modules'
$packagePath = Join-Path ([IO.Path]::GetFullPath($CacheRoot)) "Pester.$version.nupkg"

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($packagePath)) -Force
    Invoke-WebRequest -Uri $packageUri -OutFile $packagePath -UseBasicParsing
}
$actualSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -cne $expectedSha256) {
    Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
    throw "Pester package hash mismatch: expected=$expectedSha256 actual=$actualSha256"
}

$moduleRoot = Join-Path $moduleBase ("Pester\{0}-{1}" -f $version, ([guid]::NewGuid().ToString('N')))
$extractRoot = "$moduleRoot.extracting"
$null = New-Item -ItemType Directory -Path $extractRoot -Force
[IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $extractRoot)
$extractedManifest = Join-Path $extractRoot 'Pester.psd1'
if (-not (Test-Path -LiteralPath $extractedManifest -PathType Leaf)) {
    throw 'Verified Pester package does not contain Pester.psd1.'
}
$null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($moduleRoot)) -Force
Move-Item -LiteralPath $extractRoot -Destination $moduleRoot
$manifest = Join-Path $moduleRoot 'Pester.psd1'

Import-Module -Name $manifest -Force
if ((Get-Module Pester).Version -ne [version]$version) {
    throw "Verified Pester $version did not load."
}
if ($ExportToGitHubEnv) {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) { throw 'GITHUB_ENV is required with -ExportToGitHubEnv.' }
    "PESTER_610_MANIFEST=$manifest" | Out-File -LiteralPath $env:GITHUB_ENV -Encoding utf8 -Append
}

$manifest
