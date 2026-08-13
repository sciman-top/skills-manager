#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$Version,
    [ValidateSet('Bootstrap', 'Portable', 'Both')]
    [string]$Package = 'Both',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\artifacts')
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$workRoot = Join-Path $outputRoot '.release-work'

function Assert-InsideOutput([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $outputRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Release working path escaped output directory: $full"
    }
}

function Copy-ReleaseFile([string]$RelativePath, [string]$DestinationRoot) {
    $source = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Release input is missing: $RelativePath"
    }
    $destination = Join-Path $DestinationRoot $RelativePath
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Get-TrackedReleaseFiles {
    $roots = @('config', 'overrides', 'src')
    $tracked = @(& git -C $repoRoot ls-files -- @roots)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed while collecting release inputs.' }
    return @($tracked | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function New-ReleasePackage([string]$Kind) {
    $slug = "skills-manager-$Version-$($Kind.ToLowerInvariant())"
    $packageRoot = Join-Path $workRoot $slug
    Assert-InsideOutput $packageRoot
    if (Test-Path -LiteralPath $packageRoot) { Remove-Item -LiteralPath $packageRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    $rootFiles = @(
        'README.md', 'README.en.md', 'LICENSE', 'CODE_OF_CONDUCT.md', 'CONTRIBUTING.md', 'SECURITY.md',
        'build.ps1', 'install.ps1', 'setup.cmd', 'skills.cmd', 'skills.json', 'skills.lock.json', 'skills.ps1',
        'docs\INSTALLATION_AND_MIGRATION.md', 'docs\RELEASING.md'
    )
    foreach ($file in @($rootFiles) + @(Get-TrackedReleaseFiles)) {
        Copy-ReleaseFile $file $packageRoot
    }

    $includesAgent = $Kind -eq 'Portable'
    if ($includesAgent) {
        $agentSource = Join-Path $repoRoot 'agent'
        if (-not (Test-Path -LiteralPath $agentSource -PathType Container)) {
            throw 'Portable package requires a built agent directory. Run build.ps1 first.'
        }
        Copy-Item -LiteralPath $agentSource -Destination (Join-Path $packageRoot 'agent') -Recurse -Force
    }

    $commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve the release commit.' }
    $fileEntries = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            path = [IO.Path]::GetRelativePath($packageRoot, $_.FullName).Replace('\', '/')
            size = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    $manifest = [ordered]@{
        schema_version = 1
        product = 'skills-manager'
        version = $Version
        package = $Kind.ToLowerInvariant()
        commit = $commit
        built_at = (Get-Date).ToUniversalTime().ToString('o')
        requires = [ordered]@{ os = 'Windows'; powershell = '7+'; git_for_install_or_update = $true }
        includes_prebuilt_agent = $includesAgent
        green_run = if ($includesAgent) { '.\skills.cmd' } else { $null }
        install = '.\setup.cmd'
        files = $fileEntries
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $packageRoot 'RELEASE-MANIFEST.json') -Encoding utf8

    $zipPath = Join-Path $outputRoot "$slug.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal
    return [pscustomobject]@{
        package = $Kind.ToLowerInvariant()
        path = $zipPath
        size = (Get-Item -LiteralPath $zipPath).Length
        sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required to build a release from tracked inputs.' }
if (-not (Test-Path -LiteralPath $outputRoot)) { New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null }
Assert-InsideOutput $workRoot
if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

try {
    $kinds = if ($Package -eq 'Both') { @('Bootstrap', 'Portable') } else { @($Package) }
    $results = @($kinds | ForEach-Object { New-ReleasePackage $_ })
    $checksumsPath = Join-Path $outputRoot "skills-manager-$Version-SHA256SUMS.txt"
    @($results | ForEach-Object { '{0} *{1}' -f $_.sha256, [IO.Path]::GetFileName($_.path) }) |
        Set-Content -LiteralPath $checksumsPath -Encoding ascii
    $results | Format-Table package, size, sha256, path -AutoSize
    Write-Host "Checksums: $checksumsPath" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
}
