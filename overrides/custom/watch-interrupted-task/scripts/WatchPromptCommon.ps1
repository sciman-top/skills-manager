Set-StrictMode -Version Latest

$script:WatchRuntimePolicyRevision = 3
$script:WatchRuntimeCommittedSources = @(
    'overrides/custom/watch-interrupted-task/scripts/WatchPromptCommon.ps1',
    'overrides/custom/watch-interrupted-task/scripts/New-WatchHeartbeatPrompt.ps1',
    'overrides/custom/watch-interrupted-task/scripts/New-WatchFleetSupervisorPrompt.ps1',
    'overrides/custom/watch-interrupted-task/scripts/Get-WatchHeartbeatDisposition.ps1',
    'overrides/custom/watch-interrupted-task/scripts/Get-WatchFleetShutdownDisposition.ps1',
    'overrides/custom/watch-interrupted-task/scripts/Get-WatchPeerBusyDisposition.ps1',
    'overrides/custom/watch-interrupted-task/scripts/New-WatchRuntimeGeneration.ps1',
    'overrides/custom/watch-interrupted-task/scripts/Test-WatchRuntimeArming.ps1',
    'scripts/hooks/block-cross-thread-send.ps1',
    'scripts/hooks/CrossThreadGuardPolicy.ps1'
)

function ConvertTo-WatchNormalizedText {
    param([Parameter(Mandatory = $true)][string]$Text)

    return (($Text -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()
}

function Get-WatchPromptSha256 {
    param([Parameter(Mandatory = $true)][string]$Body)

    $normalized = ConvertTo-WatchNormalizedText -Text $Body
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-WatchBytesSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-WatchRepositoryRoot {
    return (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
}

function Invoke-WatchGitText {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = @(& git -C $RepositoryRoot @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw ('git_command_failed:{0}' -f ($Arguments -join ' ')) }
    return (@($output) -join "`n").Trim()
}

function Get-WatchCommittedBlobBytes {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Commit,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.WorkingDirectory = $RepositoryRoot
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-C')
    $startInfo.ArgumentList.Add($RepositoryRoot)
    $startInfo.ArgumentList.Add('cat-file')
    $startInfo.ArgumentList.Add('blob')
    $startInfo.ArgumentList.Add("$Commit`:$RelativePath")

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $memory = [System.IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) { throw 'git_cat_file_start_failed' }
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw ("committed_source_missing:{0}:{1}" -f $RelativePath, $stderr.Trim()) }
        return $memory.ToArray()
    }
    finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-WatchCommittedSourceHashes {
    param(
        [string]$RepositoryRoot = (Get-WatchRepositoryRoot),
        [string]$Commit = ''
    )

    if ([string]::IsNullOrWhiteSpace($Commit)) {
        $Commit = Invoke-WatchGitText -RepositoryRoot $RepositoryRoot -Arguments @('rev-parse', 'HEAD')
    }
    if ($Commit -notmatch '^[0-9a-f]{40,64}$') { throw 'head_commit_invalid' }

    $hashes = [ordered]@{}
    foreach ($relativePath in $script:WatchRuntimeCommittedSources) {
        $bytes = Get-WatchCommittedBlobBytes -RepositoryRoot $RepositoryRoot -Commit $Commit -RelativePath $relativePath
        $hashes[$relativePath] = Get-WatchBytesSha256 -Bytes $bytes
    }
    return $hashes
}

function Get-WatchWorkingSourceHashes {
    param([string]$RepositoryRoot = (Get-WatchRepositoryRoot))
    $hashes = [ordered]@{}
    foreach ($relativePath in $script:WatchRuntimeCommittedSources) {
        $path = Join-Path $RepositoryRoot ($relativePath -replace '/',[IO.Path]::DirectorySeparatorChar)
        if (-not [IO.File]::Exists($path)) { throw "source_file_missing:$relativePath" }
        $hashes[$relativePath] = Get-WatchBytesSha256 -Bytes ([IO.File]::ReadAllBytes($path))
    }
    return $hashes
}

function Get-WatchRuntimeGenerationId {
    param(
        [string]$RepositoryRoot = (Get-WatchRepositoryRoot),
        [string]$Commit = '',
        [switch]$CommittedOnly
    )

    if ([string]::IsNullOrWhiteSpace($Commit)) {
        $Commit = Invoke-WatchGitText -RepositoryRoot $RepositoryRoot -Arguments @('rev-parse', 'HEAD')
    }
    $hashes = if ($CommittedOnly) {
        Get-WatchCommittedSourceHashes -RepositoryRoot $RepositoryRoot -Commit $Commit
    }
    else {
        Get-WatchWorkingSourceHashes -RepositoryRoot $RepositoryRoot
    }
    $binding = [System.Collections.Generic.List[string]]::new()
    $binding.Add("policy_revision=$script:WatchRuntimePolicyRevision") | Out-Null
    $binding.Add("source_commit=$($Commit.ToLowerInvariant())") | Out-Null
    foreach ($path in @($hashes.Keys | Sort-Object)) {
        $binding.Add("source:$path=$($hashes[$path])") | Out-Null
    }
    return 'watch-runtime-generation:' + (Get-WatchPromptSha256 -Body ([string]::Join("`n", $binding.ToArray())))
}

function New-WatchPromptEnvelope {
    param(
        [Parameter(Mandatory = $true)][string]$Marker,
        [Parameter(Mandatory = $true)][string]$Body,
        [ValidateRange(1, 999)][int]$PolicyRevision = 3
    )

    $normalizedBody = ConvertTo-WatchNormalizedText -Text $Body
    $hash = Get-WatchPromptSha256 -Body $normalizedBody
    return "$Marker`npolicy_revision=$PolicyRevision`nprompt_sha256=$hash`n`n$normalizedBody"
}
