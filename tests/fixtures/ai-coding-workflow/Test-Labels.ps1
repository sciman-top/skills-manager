#Requires -Version 7
[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path $PSScriptRoot 'Labels.ps1'),
    [string]$ProbeDirectory
)

$ErrorActionPreference = 'Stop'
$SourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
if ((Get-Item -LiteralPath $SourcePath).Directory.FullName -ne $PSScriptRoot) {
    throw 'Acceptance source must be in the disposable fixture root.'
}
. $SourcePath
$createdProbeDirectory = [string]::IsNullOrWhiteSpace($ProbeDirectory)
if ($createdProbeDirectory) {
    $ProbeDirectory = Join-Path ([IO.Path]::GetTempPath()) ('ai-coding-probe-' + [guid]::NewGuid().ToString('N'))
}
$sharedProbeDirectory = -not $createdProbeDirectory -and (Test-Path -LiteralPath $ProbeDirectory -PathType Container)
$probePath = Join-Path $ProbeDirectory 'labels.txt'
$generatedOk = 0
$cleanupOk = 0
$cases = @(
    @{ Name = 'empty'; Input = @(); Expected = @() }
    @{ Name = 'null'; Input = $null; Expected = @() }
    @{ Name = 'single'; Input = @(' One '); Expected = @('One') }
    @{ Name = 'blank'; Input = @($null, '', '   '); Expected = @() }
    @{ Name = 'case-and-trim'; Input = @(' Alpha ', 'alpha', 'BETA', ' beta '); Expected = @('Alpha', 'BETA') }
    @{ Name = 'order'; Input = @('B', 'A', 'B', 'C', 'A'); Expected = @('B', 'A', 'C') }
    @{ Name = 'first-spelling'; Input = @(' mixed ', 'MIXED', 'MiXeD'); Expected = @('mixed') }
    @{ Name = 'whitespace-variants'; Input = @("`tA`r`n", 'a', "`t", ' B '); Expected = @('A', 'B') }
    @{ Name = 'internal-spaces'; Input = @('a b', 'a  b', ' A B '); Expected = @('a b', 'a  b') }
    @{ Name = 'punctuation-and-numeric'; Input = @('0', '00', 'x-y', 'X-Y', 'x_y'); Expected = @('0', '00', 'x-y', 'x_y') }
    @{ Name = 'culture-independent'; Input = @('FILE', 'file', 'I', 'i'); Expected = @('FILE', 'I') }
)
$originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
$failed = 0
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
    foreach ($case in $cases) {
        try {
            $before = ConvertTo-Json -InputObject $case.Input -Compress
            $actual = @(Get-NormalizedLabels -Labels $case.Input)
            $actualJson = ConvertTo-Json -InputObject $actual -Compress
            $expectedJson = ConvertTo-Json -InputObject $case.Expected -Compress
            if ($actualJson -cne $expectedJson) { throw "expected=$expectedJson actual=$actualJson" }
            if ((ConvertTo-Json -InputObject $case.Input -Compress) -cne $before) { throw 'Caller input mutated.' }
            $again = @(Get-NormalizedLabels -Labels $actual)
            if ((ConvertTo-Json -InputObject $again -Compress) -cne $actualJson) { throw 'Repeated normalization changed the result.' }
            Write-Output "PASS $($case.Name)"
        }
        catch {
            $failed++
            Write-Output "FAIL $($case.Name): $($_.Exception.Message)"
        }
    }
}
finally { [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture }
try {
    if (-not $sharedProbeDirectory) {
        $null = New-Item -ItemType Directory -Path $ProbeDirectory -Force
    }
    New-LabelFile -Path $probePath -Labels @('One', 'two')
    $generatedLines = @(Get-Content -LiteralPath $probePath)
    if ($generatedLines.Count -ne 2) { throw "Expected 2 generated lines, got $($generatedLines.Count)." }
    $generatedOk = 1
    Remove-LabelFile -Path $probePath
    if (Test-Path -LiteralPath $probePath) { throw 'Generated file was not removed.' }
    $cleanupOk = 1
}
catch {
    $failed++
    Write-Output "FAIL generated behavior: $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $probePath) {
        try { Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop } catch { $generatedOk = 0 }
    }
    if ($createdProbeDirectory -and (Test-Path -LiteralPath $ProbeDirectory)) {
        try { Remove-Item -LiteralPath $ProbeDirectory -Force -ErrorAction Stop } catch { $cleanupOk = 0 }
    }
}
Write-Output "generated_ok=$generatedOk cleanup_ok=$cleanupOk shared_dir=$([int]$sharedProbeDirectory)"
Write-Output "cases=$($cases.Count) failed=$failed"
if ($failed -gt 0) { exit 1 }
