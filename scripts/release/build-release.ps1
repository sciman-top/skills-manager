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
    return @($tracked | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            (Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf)
        })
}

function Get-SkillFrontmatterLicense([string]$SkillPath) {
    $entrypoint = Join-Path $SkillPath 'SKILL.md'
    if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) { return '' }
    $text = Get-Content -LiteralPath $entrypoint -Raw -Encoding utf8
    $frontmatter = [regex]::Match($text, '(?s)\A---\s*\r?\n(?<yaml>.*?)\r?\n---')
    if (-not $frontmatter.Success) { return '' }
    $match = [regex]::Match($frontmatter.Groups['yaml'].Value, '(?m)^license:\s*["'']?(?<value>[^\r\n"'']+)')
    return $(if ($match.Success) { $match.Groups['value'].Value.Trim() } else { '' })
}

function Get-PortableThirdPartyNotices([string]$AgentRoot) {
    $config = Get-Content -LiteralPath (Join-Path $repoRoot 'skills.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $lock = Get-Content -LiteralPath (Join-Path $repoRoot 'skills.lock.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $mappings = @{}
    foreach ($mapping in @($config.mappings)) { $mappings[[string]$mapping.to] = $mapping }
    $vendors = @{}
    foreach ($vendor in @($lock.vendors)) { $vendors[[string]$vendor.name] = $vendor }
    $imports = @{}
    foreach ($import in @($lock.imports)) { $imports[[string]$import.name] = $import }

    $entries = New-Object Collections.Generic.List[object]
    foreach ($directory in @(Get-ChildItem -LiteralPath $AgentRoot -Directory -Force | Sort-Object Name)) {
        if (-not (Test-Path -LiteralPath (Join-Path $directory.FullName 'SKILL.md') -PathType Leaf)) { continue }
        $mapping = if ($mappings.ContainsKey($directory.Name)) { $mappings[$directory.Name] } else { $null }
        $source = $null
        $overrideRelativePath = @(
            ('overrides/custom/{0}' -f $directory.Name),
            ('overrides/patches/{0}' -f $directory.Name),
            ('overrides/resources/{0}' -f $directory.Name),
            ('overrides/{0}' -f $directory.Name)
        ) | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Container } | Select-Object -First 1
        $sourceKind = if ($overrideRelativePath) { 'repository_local' } else { 'unknown_unmapped' }
        $sourcePath = if ($overrideRelativePath) { [string]$overrideRelativePath } else { $null }
        if ($null -ne $mapping -and [string]$mapping.vendor -eq 'manual') {
            $source = $imports[[string]$mapping.from]
            $sourceKind = 'import'
            $sourcePath = [string]$source.skill
        }
        elseif ($null -ne $mapping -and [string]$mapping.vendor -ne 'overrides') {
            $source = $vendors[[string]$mapping.vendor]
            $sourceKind = 'vendor'
            $sourcePath = [string]$mapping.from
        }
        $licenseFiles = @(Get-ChildItem -LiteralPath $directory.FullName -Recurse -File | Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE)(\..*)?$' } | Sort-Object FullName | ForEach-Object {
                [IO.Path]::GetRelativePath($directory.FullName, $_.FullName).Replace('\', '/')
            })
        $declaredLicense = Get-SkillFrontmatterLicense $directory.FullName
        $files = @(Get-ChildItem -LiteralPath $directory.FullName -Recurse -File | Sort-Object FullName | ForEach-Object {
                '{0}:{1}' -f [IO.Path]::GetRelativePath($directory.FullName, $_.FullName).Replace('\', '/'), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        $contentHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($files -join "`n")))).ToLowerInvariant()
        $entries.Add([ordered]@{
                skill = $directory.Name
                source_kind = $sourceKind
                upstream_repo = if ($null -eq $source) { $null } else { [string]$source.repo }
                upstream_commit = if ($null -eq $source) { $null } else { [string]$source.commit }
                source_path = if ($null -eq $sourcePath) { $null } else { $sourcePath.Replace('\', '/') }
                declared_license = if ([string]::IsNullOrWhiteSpace($declaredLicense)) { $null } else { $declaredLicense }
                license_files = $licenseFiles
                license_status = if (-not [string]::IsNullOrWhiteSpace($declaredLicense) -or $licenseFiles.Count -gt 0) { 'observed' } else { 'unknown_review_required' }
                content_sha256 = $contentHash
            }) | Out-Null
    }
    return [ordered]@{
        schema_version = 1
        scope = 'portable_agent_skills'
        policy = 'unknown licenses are explicit review findings and do not block the initial provenance migration'
        skills = @($entries.ToArray())
        summary = [ordered]@{
            total = $entries.Count
            observed_license = @($entries | Where-Object license_status -eq 'observed').Count
            unknown_license = @($entries | Where-Object license_status -eq 'unknown_review_required').Count
        }
    }
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
        Get-PortableThirdPartyNotices (Join-Path $packageRoot 'agent') |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $packageRoot 'THIRD-PARTY-NOTICES.json') -Encoding utf8
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
