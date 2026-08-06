Set-StrictMode -Version Latest

$script:CanonicalWatchRuntimeGenerationId = 'watch-runtime-generation:4992baeae3bcfe2412e2428e72a48221cd8db27cf85ac043511fe86d0851f2f9'

function Get-WatchRuntimeGenerationId {
    return $script:CanonicalWatchRuntimeGenerationId
}

function Test-WatchRfc3339Timestamp {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][ref]$Parsed
    )

    if ($null -eq $Value) { return $false }
    if ($Value -is [datetimeoffset] -or $Value -is [datetime]) {
        $Parsed.Value = ([datetimeoffset]$Value).ToUniversalTime()
        return $true
    }

    $text = [string]$Value
    if ($text -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') {
        return $false
    }

    $candidate = [datetimeoffset]::MinValue
    $formats = [string[]]@(
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'",
        "yyyy-MM-dd'T'HH:mm:sszzz",
        "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz"
    )
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetimeoffset]::TryParseExact(
            $text,
            $formats,
            [Globalization.CultureInfo]::InvariantCulture,
            $styles,
            [ref]$candidate)) {
        return $false
    }

    $Parsed.Value = $candidate.ToUniversalTime()
    return $true
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
