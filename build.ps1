$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Src = Join-Path $Root "src"
$Dist = Join-Path $Root "skills.ps1"

$Files = @(
    "Version.ps1",
    "Core.ps1",
    "Git.ps1",
    "Config.ps1",
    "Commands/Doctor.ps1",
    "Commands/Install.ps1",
    "Commands/Update.ps1",
    "Commands/Mcp.ps1",
    "Commands/Utils.ps1",
    "Main.ps1"
)

$Content = @()
foreach ($f in $Files) {
    $p = Join-Path $Src $f
    if (-not (Test-Path $p)) { throw "Missing source file: $p" }
    # Read as UTF8 (Force)
    $Content += Get-Content -Path $p -Raw -Encoding UTF8
    $Content += "`r`n"
}

# Write UTF-8 with BOM for Windows PowerShell 5.1 compatibility.
# Use bytes explicitly to avoid host/runtime encoding differences.
$utf8NoBom = [System.Text.Encoding]::UTF8
$bom = (New-Object System.Text.UTF8Encoding($true)).GetPreamble()
$payload = $utf8NoBom.GetBytes($Content)
$bytes = New-Object byte[] ($bom.Length + $payload.Length)
[Array]::Copy($bom, 0, $bytes, 0, $bom.Length)
[Array]::Copy($payload, 0, $bytes, $bom.Length, $payload.Length)
[System.IO.File]::WriteAllBytes($Dist, $bytes)
Write-Host "Build success: $Dist" -ForegroundColor Green
