#Requires -Version 7
[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path $PSScriptRoot 'Labels.ps1'),
    [string]$ProbeDirectory
)

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$relativePath = [IO.Path]::GetRelativePath($repoRoot, $PSScriptRoot).Replace('\', '/')
if ((Test-Path -LiteralPath (Join-Path $repoRoot 'skills.json') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $repoRoot 'skills.ps1') -PathType Leaf) -and
    $relativePath -eq 'tests/fixtures/ai-coding-workflow') {
    Write-Error 'Refusing to run the checked-in acceptance fixture. Copy it to a disposable workspace first.'
    exit 1
}

$ErrorActionPreference = 'Stop'
$probeReceipt = Join-Path $PSScriptRoot '.probe-receipt.json'
[IO.File]::Delete($probeReceipt)
$sourcePath = $SourcePath
$sourceLoadError = $null
$sourceFailureKind = 'evaluator'
try {
    $sourcePath = [IO.Path]::GetFullPath($SourcePath, $PWD.Path)
    $rootPrefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $sourcePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Acceptance source must be in the disposable fixture root.'
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        $sourceFailureKind = 'missing_input'
        throw 'There is no Labels.ps1 in the fixture; restore it before rerunning.'
    }
    . $sourcePath
}
catch { $sourceLoadError = $_ }
$candidateFunctions = @(Get-Command Get-NormalizedLabels, New-LabelFile, Remove-LabelFile -CommandType Function -ErrorAction SilentlyContinue)
$observedProbes = [Collections.Generic.List[object]]::new()
try {
    if ($sourceLoadError) { throw $sourceLoadError }
    $createdProbeDirectory = [string]::IsNullOrWhiteSpace($ProbeDirectory)
    if ($createdProbeDirectory) {
        $ProbeDirectory = Join-Path $PSScriptRoot ('probe-' + [guid]::NewGuid().ToString('N'))
    }
        $sharedProbeDirectory = -not $createdProbeDirectory
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
        $observedProbes.Add([pscustomobject]@{ name = 'New-LabelFile'; status = 'passed' }) | Out-Null
        $generatedLines = @(Get-Content -LiteralPath $probePath)
        if ($generatedLines.Count -ne 2) { throw "Expected 2 generated lines, got $($generatedLines.Count)." }
        $generatedOk = 1
        Remove-LabelFile -Path $probePath
        if (Test-Path -LiteralPath $probePath) { throw 'Generated file was not removed.' }
        $observedProbes.Add([pscustomobject]@{ name = 'Remove-LabelFile'; status = 'passed' }) | Out-Null
        $cleanupOk = 1
    }
    catch {
        $failed++
        $cleanupOk = 0
        $observedProbes.Add([pscustomobject]@{ name = 'generated behavior'; status = 'failed'; error = $_.Exception.Message }) | Out-Null
        Write-Output "FAIL generated behavior: $($_.Exception.Message)"
    }
    finally {
        if ($probePath -and (Test-Path -LiteralPath $probePath)) {
            try { Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop }
            catch {
                $generatedOk = 0
                $failed++
                Write-Output "FAIL cleanup: $($_.Exception.Message)"
                $observedProbes.Add([pscustomobject]@{ name = 'test cleanup'; status = 'failed'; error = $_.Exception.Message }) | Out-Null
            }
        }
        if ($createdProbeDirectory -and $ProbeDirectory -and (Test-Path -LiteralPath $ProbeDirectory)) {
            try { Remove-Item -LiteralPath $ProbeDirectory -Force -ErrorAction Stop }
            catch {
                $cleanupOk = 0
                $failed++
                Write-Output "FAIL cleanup: $($_.Exception.Message)"
                $observedProbes.Add([pscustomobject]@{ name = 'test cleanup'; status = 'failed'; error = $_.Exception.Message }) | Out-Null
            }
        }
    }
    if ($observedProbes.Count -eq 0) {
        $observedProbes.Add([pscustomobject]@{ name = 'generated behavior'; status = 'skipped'; error = $null }) | Out-Null
    }
    $candidateHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($sourcePath))).ToLowerInvariant()
    $receipt = [ordered]@{
        schema_version = 1
        receipt_path = $probeReceipt
        source_path = $sourcePath
        source_sha256 = $candidateHash
        status = $(if ($cases.Count -eq 11 -and $failed -eq 0 -and $generatedOk -eq 1 -and $cleanupOk -eq 1) { 'passed' } else { 'failed' })
        discovered_candidate = [ordered]@{ functions = @($candidateFunctions.Name); callable = ($candidateFunctions.Count -eq 3) }
        case_count = $cases.Count
        failed_count = $failed
        generated_ok = ($generatedOk -eq 1)
        cleanup_ok = ($cleanupOk -eq 1)
        observed_probes = @($observedProbes.ToArray() | ForEach-Object { [pscustomobject]@{
            name = $_.name; status = $_.status; error = $(if ($_.PSObject.Properties['error']) { $_.error } else { $null })
        } })
    }
    [IO.File]::WriteAllText($probeReceipt, ($receipt | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    Write-Output "generated_ok=$generatedOk cleanup_ok=$cleanupOk shared_dir=$([int]$sharedProbeDirectory)"
    Write-Output "cases=$($cases.Count) failed=$failed"
    Write-Output "receipt=$probeReceipt"
    if ($failed -gt 0) { exit 1 }
}
finally {
    if (-not (Test-Path -LiteralPath $probeReceipt -PathType Leaf)) {
        $sourceHash = $null
        try { $sourceHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($SourcePath))).ToLowerInvariant() }
        catch { }
        $failureReceipt = [ordered]@{
            schema_version = 1
            receipt_path = $probeReceipt
            source_path = $sourcePath
            source_sha256 = $sourceHash
            failure_kind = $sourceFailureKind
            discovered_candidate = [ordered]@{ functions = @($candidateFunctions.Name); callable = $false }
            status = 'failed'
            observed_probes = @([ordered]@{ name = 'Test-Labels'; status = 'failed'; error = 'Evaluator did not complete.' })
        }
        [IO.File]::WriteAllText($probeReceipt, ($failureReceipt | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
        Write-Output "receipt=$probeReceipt"
    }
}
