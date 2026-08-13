#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)][string]$Query,
    [string]$CatalogPath = '',
    [string[]]$DomainHint = @(),
    [Alias('SelectedCapability')][string[]]$Candidate = @(),
    [string[]]$ExcludeCapability = @(),
    [ValidateRange(1,256)][int]$MaxCandidates = 128,
    [switch]$AutoDiscover
)

$ErrorActionPreference = 'Stop'

function Resolve-Catalog([string]$Explicit) {
    if (-not [string]::IsNullOrWhiteSpace($Explicit) -and (Test-Path -LiteralPath $Explicit -PathType Leaf)) { return [IO.Path]::GetFullPath($Explicit) }
    if (-not [string]::IsNullOrWhiteSpace($env:SKILLS_MANAGER_CAPABILITY_CATALOG) -and (Test-Path -LiteralPath $env:SKILLS_MANAGER_CAPABILITY_CATALOG -PathType Leaf)) { return [IO.Path]::GetFullPath($env:SKILLS_MANAGER_CAPABILITY_CATALOG) }
    $routerRoot = Split-Path $PSScriptRoot -Parent
    $managedRoot = Split-Path $routerRoot -Parent
    $routerItem = Get-Item -LiteralPath $routerRoot -Force
    $portableRouterRoot = if (($routerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and $routerItem.Target) { [IO.Path]::GetFullPath([string]$routerItem.Target) } else { $routerRoot }
    foreach ($path in @((Join-Path $managedRoot '.skills-manager\catalog.json'), (Join-Path $portableRouterRoot 'catalog.json'), (Join-Path $routerRoot 'catalog.json'))) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return [IO.Path]::GetFullPath($path) }
    }
    throw 'No capability catalog is available.'
}

function Test-Within([string]$Path,[string]$Root) {
    $full=[IO.Path]::GetFullPath($Path);$boundary=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    return $full.Equals($boundary,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith(($boundary+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)
}

function Get-Names([string[]]$Values) {
    @($Values | ForEach-Object { ([string]$_ -split '\|')[-1].Trim() } | Where-Object { $_ } | Sort-Object -Unique)
}

$catalogFile = Resolve-Catalog $CatalogPath
$catalog = Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json
$catalogRoot = Split-Path $catalogFile -Parent
$managedRoot = if ((Split-Path $catalogRoot -Leaf) -eq '.skills-manager') { Split-Path $catalogRoot -Parent } else { Split-Path $catalogRoot -Parent }
$domainNames = @($DomainHint | ForEach-Object { $_ -split ',' } | ForEach-Object Trim | Where-Object { $_ } | Sort-Object -Unique)
$allowedByDomain = @()
if ($domainNames.Count -gt 0) {
    $allowedByDomain = @($catalog.domains | Where-Object { $_.name -in $domainNames } | ForEach-Object skill_names | Sort-Object -Unique)
}
$excludedNames = Get-Names $ExcludeCapability
$requestedNames = Get-Names $Candidate
$rows = [Collections.Generic.List[object]]::new()
$excluded = [Collections.Generic.List[object]]::new()
$stale = $false
foreach ($skill in @($catalog.skills | Sort-Object name)) {
    $name=[string]$skill.name
    if ($domainNames.Count -gt 0 -and $name -notin $allowedByDomain) { continue }
    if ($name -in $excludedNames) { $excluded.Add([pscustomobject]@{kind='skill';name=$name;reason='explicitly_excluded'})|Out-Null; continue }
    $path=[IO.Path]::GetFullPath((Join-Path $catalogRoot ([string]$skill.relative_path)))
    if (-not (Test-Within $path $managedRoot) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { $excluded.Add([pscustomobject]@{kind='skill';name=$name;reason='unavailable_or_outside_catalog_root'})|Out-Null; continue }
    $expected=([string]$skill.entrypoint_sha256).ToLowerInvariant()
    if ($expected -match '^[0-9a-f]{64}$' -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) { $stale=$true;$excluded.Add([pscustomobject]@{kind='skill';name=$name;reason='catalog_stale'})|Out-Null;continue }
    $rows.Add([pscustomobject][ordered]@{kind='skill';name=$name;description=[string]$skill.description;path=$path;availability='available';load_side_effect=$(if($skill.load_side_effect){[string]$skill.load_side_effect}else{'read_only'});side_effect=$(if($skill.side_effect){[string]$skill.side_effect}else{'unknown'});contained=$true})|Out-Null
}
$all=@($rows.ToArray())
$truncated=$all.Count -gt $MaxCandidates
$visible=@($all | Select-Object -First $MaxCandidates)
$selected=@()
foreach($name in $requestedNames){
    $match=@($all|Where-Object name -eq $name)
    if($match.Count -eq 1){$selected+=$match[0]}else{$excluded.Add([pscustomobject]@{kind='skill';name=$name;reason='not_available'})|Out-Null}
}

[pscustomobject][ordered]@{
    schema_version=1
    decision_owner='host_ai'
    semantic_routing_performed=$false
    query_received=(-not [string]::IsNullOrWhiteSpace($Query))
    catalog_path=$catalogFile
    catalog=[ordered]@{status=$(if($stale){'stale'}else{'current'});skill_count=@($catalog.skills).Count}
    discovery_domains=@($catalog.domains | Select-Object name,purpose)
    retrieval=[ordered]@{strategy='catalog_discovery';candidates=$visible;truncated=$truncated}
    selected=@($selected)
    excluded=@($excluded.ToArray())
    validation=[ordered]@{requested=$requestedNames;pass=($requestedNames.Count -eq $selected.Count);checks=@('exists','catalog_root_containment','entrypoint_hash','availability','side_effect_disclosure')}
    writes_performed=$false
    provider_calls=0
    native_mutations=0
} | ConvertTo-Json -Depth 10 -Compress
