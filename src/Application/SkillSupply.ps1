function Test-SkillPackagePathInsideOrEqual {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([string]::Equals($fullPath, $fullRoot, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-SkillPackageSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ContainmentRoot,
        [string]$Label = 'skill-package'
    )

    $packageFull = [IO.Path]::GetFullPath($Path)
    $rootFull = [IO.Path]::GetFullPath($ContainmentRoot)
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
        throw ("skill_package_unsafe:containment_root_missing:{0}" -f $Label)
    }
    if (-not (Test-SkillPackagePathInsideOrEqual -Path $packageFull -Root $rootFull)) {
        throw ("skill_package_unsafe:path_escape:{0}" -f $Label)
    }
    if (-not (Test-Path -LiteralPath $packageFull -PathType Container)) {
        throw ("skill_package_unsafe:package_missing:{0}" -f $Label)
    }

    $rootItem = Get-Item -LiteralPath $rootFull -Force -ErrorAction Stop
    if ([bool]($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ("skill_package_unsafe:reparse_point:{0}" -f $Label)
    }

    $relativePackage = [IO.Path]::GetRelativePath($rootFull, $packageFull)
    $cursor = $rootFull
    if ($relativePackage -ne '.') {
        foreach ($segment in @($relativePackage -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $cursor = Join-Path $cursor $segment
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if ([bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw ("skill_package_unsafe:reparse_point:{0}" -f $Label)
            }
        }
    }

    $entryCount = 0
    foreach ($entry in @(Get-ChildItem -LiteralPath $packageFull -Force -Recurse -ErrorAction Stop)) {
        $entryCount++
        if ([bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw ("skill_package_unsafe:reparse_point:{0}" -f $Label)
        }
        if (-not $entry.PSIsContainer -and $entry -isnot [IO.FileInfo]) {
            throw ("skill_package_unsafe:special_file:{0}" -f $Label)
        }
    }

    $trackedFileCount = 0
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitRootOutput = @(& git -C $packageFull rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -eq 0 -and $gitRootOutput.Count -gt 0) {
            $gitRoot = [IO.Path]::GetFullPath(([string]$gitRootOutput[-1]).Trim())
            if (Test-SkillPackagePathInsideOrEqual -Path $packageFull -Root $gitRoot) {
                $gitRelative = [IO.Path]::GetRelativePath($gitRoot, $packageFull).Replace('\', '/')
                $stageLines = @(& git -C $gitRoot ls-files --stage -- $gitRelative 2>$null)
                if ($LASTEXITCODE -ne 0) {
                    throw ("skill_package_unsafe:git_index_inspection_failed:{0}" -f $Label)
                }
                foreach ($line in $stageLines) {
                    if ([string]::IsNullOrWhiteSpace([string]$line)) { continue }
                    if ([string]$line -notmatch '^(?<mode>[0-9]{6})\s') {
                        throw ("skill_package_unsafe:git_index_entry_invalid:{0}" -f $Label)
                    }
                    $trackedFileCount++
                    if ($Matches.mode -notin @('100644', '100755')) {
                        throw ("skill_package_unsafe:git_special_mode:{0}:{1}" -f $Label, $Matches.mode)
                    }
                }
            }
        }
    }

    return [pscustomobject][ordered]@{
        safe = $true
        path = $packageFull
        containment_root = $rootFull
        entry_count = $entryCount
        tracked_file_count = $trackedFileCount
    }
}
