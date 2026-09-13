#Requires -Version 7
[CmdletBinding()]
param([string]$SourcePath = (Join-Path $PSScriptRoot 'Labels.ps1'))

$ErrorActionPreference = 'Stop'
. $SourcePath
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
Write-Output "cases=$($cases.Count) failed=$failed"
if ($failed -gt 0) { exit 1 }
