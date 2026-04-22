[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Push-Location $root
try {
    $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'skills.ps1') doctor --json 2>&1)
    $exitCode = $LASTEXITCODE
    $text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()

    if ($exitCode -ne 0) {
        throw ("doctor --json exited with {0}: {1}" -f $exitCode, $text)
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'doctor --json returned empty output.'
    }

    try {
        $report = $text | ConvertFrom-Json
    }
    catch {
        throw ("doctor --json output is not valid JSON: {0}`nOutput:`n{1}" -f $_.Exception.Message, $text)
    }

    if ($null -eq $report.checks) { throw 'doctor --json report misses checks.' }
    if ($null -eq $report.checks.git -or $report.checks.git.ok -ne $true) { throw 'doctor --json report has failing or missing git check.' }
    if ($null -eq $report.checks.config -or $report.checks.config.ok -ne $true) { throw 'doctor --json report has failing or missing config check.' }
    if ($null -eq $report.summary) { throw 'doctor --json report misses summary.' }

    Write-Host 'doctor JSON contract check passed.'
}
finally {
    Pop-Location
}
