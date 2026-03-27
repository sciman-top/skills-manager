param()

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path -LiteralPath ".githooks\pre-commit")) {
    Write-Host "Missing .githooks/pre-commit. Install aborted." -ForegroundColor Red
    exit 1
}

git config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    Write-Host "git config core.hooksPath failed. Check .git permissions." -ForegroundColor Red
    exit 2
}

Write-Host "core.hooksPath=.githooks has been set." -ForegroundColor Green
Write-Host "Run 'git config --get core.hooksPath' to verify." -ForegroundColor Green
