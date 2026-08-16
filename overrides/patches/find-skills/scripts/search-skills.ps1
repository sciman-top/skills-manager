#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Query,

    [string]$Owner = '',
    [string]$NpmCacheRoot = '',
    [string]$NodeCommand = 'node.exe',
    [switch]$NoCacheHydration
)

$ErrorActionPreference = 'Stop'

function Test-PathWithinRoot([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path)
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return $full.Equals($boundary, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith(($boundary + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
}

function Test-ReparsePathWithinRoot([string]$Path, [string]$Root) {
    $boundary = [IO.Path]::GetFullPath($Root)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-PathWithinRoot $full $boundary)) { return $true }
    $relative = [IO.Path]::GetRelativePath($boundary, $full)
    $currentPath = $boundary
    foreach ($segment in @($relative -split '[\\/]+' | Where-Object { $_ -and $_ -ne '.' })) {
        $currentPath = Join-Path $currentPath $segment
        $item = Get-Item -LiteralPath $currentPath -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
    }
    return $false
}

function Get-ValidatedSkillsCli([string]$CacheRoot) {
    $npxRoot = Join-Path $CacheRoot '_npx'
    if (-not (Test-Path -LiteralPath $npxRoot -PathType Container)) { return $null }

    $valid = foreach ($runDir in @(Get-ChildItem -LiteralPath $npxRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        $packageRoot = Join-Path $runDir.FullName 'node_modules\skills'
        $manifestPath = Join-Path $packageRoot 'package.json'
        $cliPath = Join-Path $packageRoot 'bin\cli.mjs'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $cliPath -PathType Leaf)) { continue }
        if (-not (Test-PathWithinRoot $packageRoot $CacheRoot) -or
            -not (Test-PathWithinRoot $cliPath $packageRoot)) { continue }
        if ((Test-ReparsePathWithinRoot $packageRoot $CacheRoot) -or
            (Test-ReparsePathWithinRoot $cliPath $CacheRoot)) { continue }
        try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { continue }
        $skillsBin = if ($manifest.bin -is [string]) { [string]$manifest.bin }
        elseif ($null -ne $manifest.bin -and $manifest.bin.PSObject.Properties.Match('skills').Count -gt 0) {
            [string]$manifest.bin.skills
        }
        else { '' }
        $normalizedBin = $skillsBin.Trim().TrimStart('.', '/', '\').Replace('/', '\')
        if ([string]$manifest.name -cne 'skills' -or $normalizedBin -cne 'bin\cli.mjs') { continue }
        [pscustomobject]@{
            path = [IO.Path]::GetFullPath($cliPath)
            version = [string]$manifest.version
            last_write_utc = (Get-Item -LiteralPath $cliPath).LastWriteTimeUtc
        }
    }
    return @($valid | Sort-Object last_write_utc -Descending | Select-Object -First 1)[0]
}

if ([string]::IsNullOrWhiteSpace($NpmCacheRoot)) {
    $npm = Get-Command npm.cmd -ErrorAction Stop
    $NpmCacheRoot = [string](& $npm.Source config get cache)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($NpmCacheRoot)) {
        throw 'Unable to resolve the npm cache directory.'
    }
}
$cacheRoot = [IO.Path]::GetFullPath($NpmCacheRoot.Trim())
$cli = Get-ValidatedSkillsCli $cacheRoot

if ($null -eq $cli -and -not $NoCacheHydration) {
    $npx = Get-Command npx.cmd -ErrorAction Stop
    $global:LASTEXITCODE = 0
    & $npx.Source --yes skills --help *> $null
    $cli = Get-ValidatedSkillsCli $cacheRoot
}
if ($null -eq $cli) {
    throw 'No validated cached Skills CLI was found. Run npx skills once with network access, then retry.'
}

$node = Get-Command $NodeCommand -ErrorAction Stop
$nodePath = if ($node.Path) { [string]$node.Path } else { [string]$node.Source }
$arguments = @([string]$cli.path, 'find', $Query)
if (-not [string]::IsNullOrWhiteSpace($Owner)) { $arguments += @('--owner', $Owner.Trim()) }

$global:LASTEXITCODE = 0
& $nodePath @arguments
if ($LASTEXITCODE -ne 0) {
    throw ("Skills CLI search failed with exit code {0}." -f $LASTEXITCODE)
}
