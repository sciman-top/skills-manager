[CmdletBinding()]
param(
    [string]$EventPath = $env:GITHUB_EVENT_PATH,
    [string]$Body = ''
)

$ErrorActionPreference = 'Stop'

function Get-CharterBody {
    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        return [pscustomobject]@{ applicable = $true; body = $Body }
    }
    if ([string]::IsNullOrWhiteSpace($EventPath)) {
        return [pscustomobject]@{ applicable = $false; body = '' }
    }
    if (-not (Test-Path -LiteralPath $EventPath -PathType Leaf)) {
        throw "GitHub event file does not exist: $EventPath"
    }
    try {
        $event = Get-Content -LiteralPath $EventPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "GitHub event file is not valid JSON: $($_.Exception.Message)"
    }
    if ($null -eq $event.pull_request) {
        return [pscustomobject]@{ applicable = $false; body = '' }
    }
    return [pscustomobject]@{ applicable = $true; body = [string]$event.pull_request.body }
}

function Get-CharterField([string]$Text, [string]$Label) {
    $escaped = [regex]::Escape($Label)
    $match = [regex]::Match($Text, "(?im)^\s*-\s*$escaped\s*:\s*(?<value>[^\r\n]*)\s*$")
    if (-not $match.Success) { return '' }
    return $match.Groups['value'].Value.Trim()
}

function Assert-CharterValue([string]$Label, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '^<[^>]+>$') {
        throw "PR charter field is missing or still contains the template placeholder: $Label"
    }
}

$charter = Get-CharterBody
if (-not [bool]$charter.applicable) {
    Write-Host 'PR charter check: not applicable (no pull_request event body).' -ForegroundColor Yellow
    exit 0
}
$charterBody = [string]$charter.body
if ([string]::IsNullOrWhiteSpace($charterBody)) {
    throw 'Pull request body is empty; fill in the repository PR charter before requesting review.'
}

$goalMatch = [regex]::Match($charterBody, '(?ims)^\s*##\s*Goal\s*$\r?\n\s*-\s*(?<value>[^\r\n]+)')
if (-not $goalMatch.Success) { throw 'PR charter section is missing: ## Goal' }
Assert-CharterValue 'Goal' $goalMatch.Groups['value'].Value.Trim()

$newSurface = Get-CharterField $charterBody 'New surface'
if ($newSurface -notin @('yes', 'no')) {
    throw 'PR charter field New surface must be yes or no.'
}

$requiredSections = @('Risks and Rollback')
if ($newSurface -eq 'yes') { $requiredSections += @('Charter admission', 'Deletion delta') }
foreach ($section in $requiredSections) {
    if (-not [regex]::IsMatch($charterBody, "(?im)^\s*##\s*$([regex]::Escape($section))(?:\s+\([^\r\n)]*\))?\s*$")) {
        throw "PR charter section is missing: ## $section"
    }
}

$requiredFields = @('Risk', 'Rollback')
if ($newSurface -eq 'yes') { $requiredFields += @('Current caller', 'Replaces / deletes', 'Minimum proof', 'Removed') }
foreach ($label in $requiredFields) {
    Assert-CharterValue $label (Get-CharterField $charterBody $label)
}

if ($newSurface -eq 'yes') {
    Write-Host 'PR charter check passed: new-surface caller, replacement/deletion, minimum proof, removal delta, risk and rollback are declared.' -ForegroundColor Green
}
else {
    Write-Host 'PR charter check passed: routine change; new-surface admission is not applicable.' -ForegroundColor Green
}
