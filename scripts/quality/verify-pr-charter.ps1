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

foreach ($section in @('Charter admission', 'Deletion delta', 'Risks and Rollback')) {
    if (-not [regex]::IsMatch($charterBody, "(?im)^\s*##\s*$([regex]::Escape($section))(?:\s+\([^\r\n)]*\))?\s*$")) {
        throw "PR charter section is missing: ## $section"
    }
}

foreach ($label in @('Current caller', 'Replaces / deletes', 'Minimum proof', 'Removed', 'Risk', 'Rollback')) {
    Assert-CharterValue $label (Get-CharterField $charterBody $label)
}

Write-Host 'PR charter check passed: Goal, caller, replacement/deletion, proof, removal delta, risk and rollback are declared.' -ForegroundColor Green
