function New-NativeSkillProjectionRuntimePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Snapshot,
        $Policy = $null,
        [string[]]$IncludedNames = @(),
        [string[]]$ExcludedNames = @(),
        [string]$GeneratedAt = ([DateTimeOffset]::UtcNow.ToString('o'))
    )

    $root = [IO.Path]::GetFullPath($ManagedRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw ('Managed skill root does not exist: {0}' -f $root) }
    $excluded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($ExcludedNames)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) { $excluded.Add(([string]$name).Trim()) | Out-Null }
    }
    $included = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($IncludedNames)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) { $included.Add(([string]$name).Trim()) | Out-Null }
    }
    $useIncludeFilter = $included.Count -gt 0
    $discoveredPackages = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entries = @(
        Get-ChildItem -LiteralPath $root -Directory -Force |
            Where-Object { $_.Name -ne '.system' -and -not $excluded.Contains($_.Name) -and (-not $useIncludeFilter -or $included.Contains($_.Name)) } |
            Sort-Object Name |
            ForEach-Object {
                $skillPath = Join-Path $_.FullName 'SKILL.md'
                if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
                    $discoveredPackages.Add($_.Name) | Out-Null
                    [pscustomobject][ordered]@{
                        path = $skillPath
                        source_root = $root
                        enabled = $true
                        availability = 'available'
                        freshness = 'fresh'
                        load_side_effect = 'read_only'
                        side_effect = 'read_only'
                        surfaces = @('native_discovery')
                    }
                }
            }
    )
    $missingIncludedPackages = @($included | Where-Object { -not $discoveredPackages.Contains($_) } | Sort-Object)
    if ($missingIncludedPackages.Count -gt 0) {
        throw ('Managed link include packages are missing or lack SKILL.md: {0}' -f ($missingIncludedPackages -join ', '))
    }
    $catalog = Compile-SkillCatalog -Entries $entries -GeneratedAt $GeneratedAt
    $catalogContract = Test-SkillCatalogContract $catalog
    if (-not [bool]$catalog.complete -or -not [bool]$catalogContract.pass) {
        throw ('Native runtime catalog contract failed: {0}' -f (@($catalog.findings + $catalogContract.findings | ForEach-Object code | Select-Object -Unique) -join ', '))
    }
    $availableNames = @($catalog.entries | ForEach-Object { [string]$_.name })
    $eligibility = @($catalog.entries | ForEach-Object {
            Evaluate-SkillEligibility -Skill $_ -Surface 'native_discovery' -AllowedRoots @($root) -AvailableDependencies $availableNames
        })
    $metadata = Plan-NativeMetadata -Inventory $catalog -Snapshot $Snapshot -Policy $Policy
    $metadataContract = Test-NativeMetadataPlanContract $metadata
    if (-not [bool]$metadataContract.pass) {
        throw ('Native metadata plan contract failed: {0}' -f (@($metadataContract.findings | ForEach-Object code) -join ', '))
    }
    $plan = New-NativeSkillProjectionPlan -Catalog $catalog -Eligibility $eligibility -MetadataPlan $metadata -Config $Config
    $planContract = Test-NativeSkillProjectionPlanContract $plan
    if (-not [bool]$planContract.pass) {
        throw ('Native projection plan contract failed: {0}' -f (@($planContract.findings | ForEach-Object code) -join ', '))
    }
    return $plan
}
