Set-StrictMode -Version Latest

$script:CanonicalWatchRuntimeGenerationId = 'watch-runtime-generation:afeebb26f33764756b9e28d1c93bcfb2305064d8a0c8f8eb61623eacdfe0b2d5'

function Get-WatchRuntimeGenerationId {
    return $script:CanonicalWatchRuntimeGenerationId
}

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
