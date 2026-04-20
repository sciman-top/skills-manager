param(
    [switch]$IncludeReports
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$docsDir = Join-Path $root "docs"
$reportsDir = Join-Path $root "reports"
$removed = 0

function Remove-FileSafely([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    return $true
}

$runtimePatterns = @(
    "runtime-adapter-events-sm-*.txt",
    "runtime-auto-write-sm-*.txt"
)

if (Test-Path -LiteralPath $docsDir -PathType Container) {
    foreach ($pattern in $runtimePatterns) {
        foreach ($file in (Get-ChildItem -LiteralPath $docsDir -Filter $pattern -File -ErrorAction SilentlyContinue)) {
            if (Remove-FileSafely $file.FullName) {
                $removed++
                Write-Host ("Removed: {0}" -f $file.FullName)
            }
        }
    }
}

if ($IncludeReports -and (Test-Path -LiteralPath $reportsDir -PathType Container)) {
    foreach ($entry in (Get-ChildItem -LiteralPath $reportsDir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
        $removed++
        Write-Host ("Removed: {0}" -f $entry.FullName)
    }
}

Write-Host ("Cleanup complete. Removed items: {0}" -f $removed) -ForegroundColor Cyan
