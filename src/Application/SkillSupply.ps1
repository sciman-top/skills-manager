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

function Get-PackagePayloadFiles([string]$Root) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
        throw "package_payload_missing:$rootFull"
    }
    return @(Get-ChildItem -LiteralPath $rootFull -Force -Recurse -File -ErrorAction Stop | Sort-Object FullName | ForEach-Object {
        if ([bool]($_.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw ("package_payload_reparse_point:{0}" -f $_.FullName)
        }
        $_
    })
}

function Get-PackageFileEntries([string]$Root) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return @(Get-PackagePayloadFiles $rootFull | ForEach-Object {
        [ordered]@{
            path = [IO.Path]::GetRelativePath($rootFull, $_.FullName).Replace('\', '/')
            size = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}

function New-VerifiedPackageArchive([string]$SourceRoot, [string]$DestinationPath) {
    $sourceFull = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\', '/')
    $destinationFull = [IO.Path]::GetFullPath($DestinationPath)
    $archiveRoot = Split-Path -Leaf $sourceFull
    if ([string]::IsNullOrWhiteSpace($archiveRoot)) { throw 'package_archive_root_missing' }

    $destinationParent = Split-Path -Parent $destinationFull
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $destinationFull) { [IO.File]::Delete($destinationFull) }

    $files = @(Get-PackagePayloadFiles $sourceFull)
    $expected = @{}
    foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($sourceFull, $file.FullName).Replace('\', '/')
        $expected[$relative] = [ordered]@{
            size = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    $stream = [IO.File]::Open($destinationFull, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($file in $files) {
                $relative = [IO.Path]::GetRelativePath($sourceFull, $file.FullName).Replace('\', '/')
                $entry = $archive.CreateEntry(("{0}/{1}" -f $archiveRoot, $relative), [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $input = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    $output = $entry.Open()
                    try { $input.CopyTo($output) }
                    finally { $output.Dispose() }
                }
                finally { $input.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }

    $observed = @{}
    $readStream = [IO.File]::Open($destinationFull, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $readArchive = [IO.Compression.ZipArchive]::new($readStream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            foreach ($entry in @($readArchive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })) {
                $prefix = $archiveRoot + '/'
                if (-not $entry.FullName.StartsWith($prefix, [StringComparison]::Ordinal)) {
                    throw ("package_archive_root_mismatch:{0}" -f $entry.FullName)
                }
                $relative = $entry.FullName.Substring($prefix.Length)
                if ($observed.ContainsKey($relative)) { throw ("package_archive_duplicate:{0}" -f $relative) }
                $entryStream = $entry.Open()
                try {
                    $sha = [Security.Cryptography.SHA256]::Create()
                    try { $hash = [Convert]::ToHexString($sha.ComputeHash($entryStream)).ToLowerInvariant() }
                    finally { $sha.Dispose() }
                }
                finally { $entryStream.Dispose() }
                $observed[$relative] = [ordered]@{ size = $entry.Length; sha256 = $hash }
            }
        }
        finally { $readArchive.Dispose() }
    }
    finally { $readStream.Dispose() }

    if ($observed.Count -ne $expected.Count) {
        throw ("package_archive_file_count_mismatch:expected={0}:actual={1}" -f $expected.Count, $observed.Count)
    }
    foreach ($relative in @($expected.Keys | Sort-Object)) {
        if (-not $observed.ContainsKey($relative)) { throw ("package_archive_missing:{0}" -f $relative) }
        if ([long]$observed[$relative].size -ne [long]$expected[$relative].size -or [string]$observed[$relative].sha256 -ne [string]$expected[$relative].sha256) {
            throw ("package_archive_hash_mismatch:{0}" -f $relative)
        }
    }
    return [pscustomobject][ordered]@{
        path = $destinationFull
        file_count = $observed.Count
        size = (Get-Item -LiteralPath $destinationFull).Length
        sha256 = (Get-FileHash -LiteralPath $destinationFull -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
