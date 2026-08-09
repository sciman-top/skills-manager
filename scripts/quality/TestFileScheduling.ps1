function ConvertTo-TestFileSchedulingKey {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalizedPath = $Path.Replace('/', '\').TrimStart('\').ToLowerInvariant()
    return ('{0}|{1}' -f $Stage.Trim().ToLowerInvariant(), $normalizedPath)
}

function Get-TestFileSchedulingRelativePath {
    param(
        [Parameter(Mandatory = $true)]$File,
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $root = [IO.Path]::GetFullPath($RootPath)
    $filePath = [IO.Path]::GetFullPath([string]$File.FullName)
    return [IO.Path]::GetRelativePath($root, $filePath).Replace('/', '\')
}

function Import-TestFileSchedulingTiming {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $lookup = [Collections.Generic.Dictionary[string, double]]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return [pscustomobject][ordered]@{ status = 'missing'; path = $fullPath; lookup = $lookup }
    }

    try {
        $report = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ([int]$report.schema_version -lt 2 -or $null -eq $report.stages) { throw 'unsupported timing report schema' }
        foreach ($stage in @($report.stages)) {
            $stageName = ([string]$stage.stage).Trim()
            if ([string]::IsNullOrWhiteSpace($stageName)) { continue }
            foreach ($row in @($stage.files)) {
                $relativePath = ([string]$row.path).Trim()
                if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
                $elapsed = 0.0
                if (-not [double]::TryParse([string]$row.elapsed_ms, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$elapsed) -or $elapsed -lt 0) { continue }
                $key = ConvertTo-TestFileSchedulingKey -Stage $stageName -Path $relativePath
                if (-not $lookup.ContainsKey($key) -or $elapsed -gt $lookup[$key]) { $lookup[$key] = $elapsed }
            }
        }
        return [pscustomobject][ordered]@{ status = 'loaded'; path = $fullPath; lookup = $lookup }
    }
    catch {
        return [pscustomobject][ordered]@{ status = 'invalid'; path = $fullPath; lookup = $lookup }
    }
}

function Get-TestFileSchedule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Files,
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)]$Timing,
        [string[]]$InProcessTestFiles = @(),
        [string[]]$SerialTestFiles = @()
    )

    $rows = @($Files | ForEach-Object {
        $file = $_
        $relativePath = Get-TestFileSchedulingRelativePath -File $file -RootPath $RootPath
        $group = if ($InProcessTestFiles -contains $file.Name) { 0 } elseif ($SerialTestFiles -contains $file.Name) { 1 } else { 2 }
        $duration = 0.0
        $matched = $false
        if ($null -ne $Timing.lookup) {
            $key = ConvertTo-TestFileSchedulingKey -Stage $Stage -Path $relativePath
            $matched = $Timing.lookup.TryGetValue($key, [ref]$duration)
        }
        [pscustomobject]@{
            file = $file
            relative_path = $relativePath
            group = $group
            historical_duration_ms = if ($group -eq 2 -and $matched) { $duration } else { 0.0 }
            historical_match = ($group -eq 2 -and $matched)
        }
    })
    $ordered = @($rows | Sort-Object `
        @{ Expression = { $_.group }; Ascending = $true }, `
        @{ Expression = { $_.historical_duration_ms }; Descending = $true }, `
        @{ Expression = { $_.relative_path }; Ascending = $true })

    return [pscustomobject][ordered]@{
        files = [object[]]@($ordered | ForEach-Object file)
        matched_file_count = @($ordered | Where-Object historical_match).Count
        file_count = $ordered.Count
    }
}
