$skillCatalogCompilerRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) { . (Join-Path $skillCatalogCompilerRepoRoot 'src\Domain\OperationPlan.ps1') }
if ($null -eq (Get-Command New-SkillCatalog -ErrorAction SilentlyContinue)) { . (Join-Path $skillCatalogCompilerRepoRoot 'src\Domain\SkillCatalog.ps1') }
if ($null -eq (Get-Command Read-SkillMetadata -ErrorAction SilentlyContinue)) { . (Join-Path $skillCatalogCompilerRepoRoot 'src\Domain\SkillMetadata.ps1') }

function Test-SkillCatalogCompilerContained {
    param([string]$Path, [string]$Root)

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    if (Get-Command Test-OperationPathWithinRoot -ErrorAction SilentlyContinue) { return Test-OperationPathWithinRoot $Path $Root }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Get-SkillCatalogCompilerTextHash([string]$Text) {
    if (Get-Command Get-OperationSha256 -ErrorAction SilentlyContinue) { return Get-OperationSha256 $Text }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Read-SkillCatalogCompilerMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    $metadata = Read-SkillMetadata $Path -Observation
    $reason = @($metadata.findings | Where-Object severity -eq 'error' | Select-Object -First 1 -ExpandProperty code)
    return [pscustomobject]@{ valid = [bool]$metadata.valid; reason = if ($reason.Count) { [string]$reason[0] } else { '' }; name = [string]$metadata.name; description = [string]$metadata.description; text = [string]$metadata.text }
}

function ConvertTo-SkillCatalogCompilerEntry {
    param(
        [Parameter(Mandatory = $true)]$InputEntry,
        [string]$DefaultRoot = '',
        [System.Collections.Generic.List[object]]$Findings
    )

    $path = [string](Get-SkillCatalogProperty $InputEntry @('path', 'local_path'))
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Container)) { $path = Join-Path $path 'SKILL.md' }
    if (-not [string]::IsNullOrWhiteSpace($path)) { $path = [IO.Path]::GetFullPath($path) }
    $sourceRoot = [string](Get-SkillCatalogProperty $InputEntry @('source_root', 'root'))
    if ([string]::IsNullOrWhiteSpace($sourceRoot)) { $sourceRoot = $DefaultRoot }
    if (-not [string]::IsNullOrWhiteSpace($sourceRoot)) { $sourceRoot = [IO.Path]::GetFullPath($sourceRoot) }
    if (-not [string]::IsNullOrWhiteSpace($path) -and -not [string]::IsNullOrWhiteSpace($sourceRoot) -and -not (Test-SkillCatalogCompilerContained $path $sourceRoot)) {
        if ($null -ne $Findings) { $Findings.Add((New-OperationFinding 'path_outside_source_root' 'error' $path 'Skill entry is outside its declared source root.')) | Out-Null }
        return $null
    }

    $metadata = $null
    $text = ''
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
        $metadata = Read-SkillCatalogCompilerMetadata $path
        $text = [string]$metadata.text
        if (-not [bool]$metadata.valid) {
            if ($null -ne $Findings) { $Findings.Add((New-OperationFinding 'skill_metadata_invalid' 'error' $path ([string]$metadata.reason))) | Out-Null }
            return $null
        }
    }
    $name = [string](Get-SkillCatalogProperty $InputEntry @('name', 'declared_name'))
    $description = [string](Get-SkillCatalogProperty $InputEntry @('description'))
    if ($metadata -and [string]::IsNullOrWhiteSpace($name)) { $name = [string]$metadata.name }
    if ($metadata -and [string]::IsNullOrWhiteSpace($description)) { $description = [string]$metadata.description }
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($description)) {
        if ($null -ne $Findings) { $Findings.Add((New-OperationFinding 'skill_identity_missing' 'error' $path 'Skill name and description are required.')) | Out-Null }
        return $null
    }

    $enabledValue = Get-SkillCatalogProperty $InputEntry @('enabled')
    $enabled = if ($enabledValue -is [bool]) { [bool]$enabledValue } else { $true }
    $availability = [string](Get-SkillCatalogProperty $InputEntry @('availability'))
    if ([string]::IsNullOrWhiteSpace($availability)) { $availability = 'available' }
    $freshness = [string](Get-SkillCatalogProperty $InputEntry @('freshness'))
    if ([string]::IsNullOrWhiteSpace($freshness)) { $freshness = if ($text) { 'fresh' } else { 'unknown' } }
    if ($freshness -notin @('fresh', 'stale', 'unknown')) { $freshness = 'unknown' }
    $contentHash = [string](Get-SkillCatalogProperty $InputEntry @('content_hash', 'entrypoint_sha256'))
    if ([string]::IsNullOrWhiteSpace($contentHash) -and $text) { $contentHash = Get-SkillCatalogCompilerTextHash $text }
    $metadataHash = [string](Get-SkillCatalogProperty $InputEntry @('metadata_hash'))
    if ([string]::IsNullOrWhiteSpace($metadataHash)) { $metadataHash = Get-SkillCatalogCompilerTextHash ('{0}|{1}' -f $name.Trim(), $description.Trim()) }
    $provenance = Get-SkillCatalogProperty $InputEntry @('provenance', 'source')
    if ($null -eq $provenance) {
        $provenance = [pscustomobject][ordered]@{ type = 'skill_root'; path = $sourceRoot; revision = 'working-tree' }
    }
    return New-SkillCatalogEntry -Name $name -Description $description -Path $path -SourceRoot $sourceRoot -ContentHash $contentHash -MetadataHash $metadataHash -Enabled $enabled -Availability $availability -Freshness $freshness -LoadSideEffect ([string]$(if ([string]::IsNullOrWhiteSpace([string](Get-SkillCatalogProperty $InputEntry @('load_side_effect')))) { 'read_only' } else { Get-SkillCatalogProperty $InputEntry @('load_side_effect') })) -SideEffect ([string]$(if ([string]::IsNullOrWhiteSpace([string](Get-SkillCatalogProperty $InputEntry @('side_effect')))) { 'read_only' } else { Get-SkillCatalogProperty $InputEntry @('side_effect') })) -Dependencies @(Get-SkillCatalogProperty $InputEntry @('dependencies')) -Surfaces @(Get-SkillCatalogProperty $InputEntry @('surfaces')) -Provenance $provenance
}

function Compile-SkillCatalog {
    [CmdletBinding()]
    param(
        [string[]]$Roots = @(),
        [object[]]$Entries = @(),
        [string]$GeneratedAt = ([DateTimeOffset]::UtcNow.ToString('o'))
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $candidates = New-Object System.Collections.Generic.List[object]
    $sourceRoots = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($Roots)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            $findings.Add((New-OperationFinding 'skill_root_missing' 'error' $root 'Skill root does not exist.')) | Out-Null
            continue
        }
        $fullRoot = [IO.Path]::GetFullPath($root)
        if (-not $sourceRoots.Contains($fullRoot)) { $sourceRoots.Add($fullRoot) | Out-Null }
        foreach ($file in @(Get-ChildItem -LiteralPath $fullRoot -Recurse -File -Filter 'SKILL.md' -Force -ErrorAction SilentlyContinue)) {
            if (-not (Test-SkillCatalogCompilerContained $file.FullName $fullRoot)) {
                $findings.Add((New-OperationFinding 'skill_path_outside_root' 'error' $file.FullName 'Discovered skill path is outside its root.')) | Out-Null
                continue
            }
            $entry = ConvertTo-SkillCatalogCompilerEntry -InputEntry ([pscustomobject]@{ path = $file.FullName; source_root = $fullRoot }) -DefaultRoot $fullRoot -Findings $findings
            if ($null -ne $entry) { $candidates.Add($entry) | Out-Null }
        }
    }
    foreach ($inputEntry in @($Entries)) {
        if ($null -eq $inputEntry) { continue }
        $entry = ConvertTo-SkillCatalogCompilerEntry -InputEntry $inputEntry -Findings $findings
        if ($null -ne $entry) { $candidates.Add($entry) | Out-Null }
    }

    $groups = @($candidates.ToArray() | Group-Object { ([string]$_.name).ToLowerInvariant() })
    $canonical = New-Object System.Collections.Generic.List[object]
    $decisions = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($groups | Sort-Object Name)) {
        $items = @($group.Group | Sort-Object path, source_root)
        $canonical.Add($items[0]) | Out-Null
        if ($items.Count -gt 1) {
            $decisions.Add([pscustomobject][ordered]@{
                    key = $group.Name
                    disposition = 'duplicate'
                    reason = 'canonical_identity_deduplicated'
                    kept_path = [string]$items[0].path
                    source_paths = @($items | ForEach-Object { [string]$_.path })
                }) | Out-Null
        }
    }
    $complete = @($findings | Where-Object { [string]$_.severity -eq 'error' }).Count -eq 0
    return New-SkillCatalog -Entries $canonical.ToArray() -Decisions $decisions.ToArray() -GeneratedAt $GeneratedAt -SourceRoots $sourceRoots.ToArray() -Complete $complete -Findings $findings.ToArray()
}
