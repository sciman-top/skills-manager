param(
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

function Write-CheckOk([string]$msg) {
    Write-Host ("[prebuild] OK    {0}" -f $msg) -ForegroundColor Green
}

function Write-CheckWarn([string]$msg) {
    Write-Host ("[prebuild] WARN  {0}" -f $msg) -ForegroundColor Yellow
}

function Write-CheckFail([string]$msg) {
    Write-Host ("[prebuild] FAIL  {0}" -f $msg) -ForegroundColor Red
}

function Test-JsonWithLineComments([string]$path) {
    $raw = Get-Content -Path $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { throw ("配置文件为空：{0}" -f $path) }
    $clean = $raw -replace "(?m)^\s*//.*", ""
    return ($clean | ConvertFrom-Json)
}

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$failed = $false

$requiredAlways = @(
    "build.ps1",
    "skills.json",
    "src\\Main.ps1"
)

$requiredStrict = @(
    "src\\Core.ps1",
    "src\\Config.ps1",
    "src\\Git.ps1",
    "src\\Commands\\Install.ps1",
    "src\\Commands\\Update.ps1",
    "src\\Commands\\Doctor.ps1"
)

foreach ($rel in $requiredAlways) {
    $p = Join-Path $root $rel
    if (Test-Path -LiteralPath $p) {
        Write-CheckOk ("found {0}" -f $rel)
    }
    else {
        if ($Strict) {
            Write-CheckFail ("missing required file: {0}" -f $rel)
            $failed = $true
        }
        else {
            Write-CheckWarn ("missing file: {0}" -f $rel)
        }
    }
}

if ($Strict) {
    foreach ($rel in $requiredStrict) {
        $p = Join-Path $root $rel
        if (Test-Path -LiteralPath $p) {
            Write-CheckOk ("found {0}" -f $rel)
        }
        else {
            Write-CheckFail ("missing required file: {0}" -f $rel)
            $failed = $true
        }
    }
}

$cfgPath = Join-Path $root "skills.json"
if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
    try {
        $cfg = Test-JsonWithLineComments $cfgPath
        $vendorCount = @($cfg.vendors).Count
        $mappingCount = @($cfg.mappings).Count
        Write-CheckOk ("skills.json parsed (vendors={0}, mappings={1})" -f $vendorCount, $mappingCount)
    }
    catch {
        Write-CheckFail ("skills.json parse failed: {0}" -f $_.Exception.Message)
        $failed = $true
    }
}

if ($failed) { exit 2 }

Write-Host "[prebuild] done" -ForegroundColor Cyan
exit 0
