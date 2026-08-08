[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TestFile,
    [Parameter(Mandatory)]
    [ValidateSet('unit', 'e2e')]
    [string]$Stage,
    [Parameter(Mandatory)]
    [string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'
$startedAt = [datetimeoffset]::UtcNow
$timer = [Diagnostics.Stopwatch]::StartNew()
$exitCode = 1
$receipt = $null

try {
    $requiredVersion = [version]'4.10.1'
    $required = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -eq $requiredVersion } |
        Select-Object -First 1
    if (-not $required) {
        throw 'Pester 4.10.1 is required to run the test suite.'
    }

    Import-Module Pester -RequiredVersion $requiredVersion -Force | Out-Null
    $result = Invoke-Pester -Script $TestFile -PassThru -Show Failed,Summary
    if (-not $result -or [int]$result.TotalCount -le 0) {
        throw ("{0} test discovery returned zero tests for {1}" -f $Stage, $TestFile)
    }

    $cases = @($result.TestResult | ForEach-Object {
        [pscustomobject][ordered]@{
            describe = [string]$_.Describe
            name = [string]$_.Name
            result = [string]$_.Result
            elapsed_ms = [math]::Round([double]$_.Time.TotalMilliseconds, 3)
        }
    })
    $exitCode = if ([int]$result.FailedCount -gt 0) { 1 } else { 0 }
    $receipt = [pscustomobject][ordered]@{
        schema_version = 1
        stage = $Stage
        test_file = [System.IO.Path]::GetFullPath($TestFile)
        status = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
        total_count = [int]$result.TotalCount
        passed_count = [int]$result.PassedCount
        failed_count = [int]$result.FailedCount
        skipped_count = [int]$result.SkippedCount
        pending_count = [int]$result.PendingCount
        inconclusive_count = [int]$result.InconclusiveCount
        started_at = $startedAt.ToString('o')
        elapsed_ms = 0
        cases = $cases
        error = $null
    }
}
catch {
    $receipt = [pscustomobject][ordered]@{
        schema_version = 1
        stage = $Stage
        test_file = [System.IO.Path]::GetFullPath($TestFile)
        status = 'error'
        total_count = 0
        passed_count = 0
        failed_count = 1
        skipped_count = 0
        pending_count = 0
        inconclusive_count = 0
        started_at = $startedAt.ToString('o')
        elapsed_ms = 0
        cases = @()
        error = $_.Exception.Message
    }
    Write-Error $_
}
finally {
    $timer.Stop()
    $receipt.elapsed_ms = $timer.ElapsedMilliseconds
    $directory = Split-Path $ReceiptPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        [System.IO.Path]::GetFullPath($ReceiptPath),
        ($receipt | ConvertTo-Json -Depth 8),
        (New-Object System.Text.UTF8Encoding($false))
    )
}

exit $exitCode
