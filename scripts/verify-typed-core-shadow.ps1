[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path $PSScriptRoot -Parent),
    [switch]$MeasurePublish,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RootPath)
$project = Join-Path $root 'typed-core\SkillsManager.TypedCore\SkillsManager.TypedCore.csproj'
$fixtureRoot = Join-Path $root 'tests\fixtures\operation-contracts'
$operationModule = Join-Path $root 'src\Domain\OperationPlan.ps1'
$receiptModule = Join-Path $root 'src\Domain\Receipt.ps1'

function Set-DotnetArchitectureEnvironment {
    if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITECTURE)) { return $false }
    $env:PROCESSOR_ARCHITECTURE = switch ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()) {
        'X64' { 'AMD64' }
        'X86' { 'x86' }
        'Arm64' { 'ARM64' }
        default { [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToUpperInvariant() }
    }
    return $true
}

function Invoke-DotnetCommand([string[]]$Arguments) {
    $output = @(& dotnet @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ('dotnet {0} failed with exit {1}: {2}' -f ($Arguments -join ' '), $exitCode, ($output -join [Environment]::NewLine))
    }
    return @($output)
}

function Invoke-JsonProcess([string]$FileName, [string[]]$Arguments, [string]$InputJson) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FileName
    foreach ($argument in @($Arguments)) { $startInfo.ArgumentList.Add($argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'Failed to start typed-core process.' }
        $process.StandardInput.Write($InputJson)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $timer.Stop()
        return [pscustomobject]@{
            exit_code = $process.ExitCode
            stdout = $stdout.Trim()
            stderr = $stderr.Trim()
            elapsed_ms = $timer.ElapsedMilliseconds
        }
    }
    finally {
        if ($timer.IsRunning) { $timer.Stop() }
        $process.Dispose()
    }
}

function Get-FindingFingerprint($Result) {
    return @($Result.findings | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.code, $_.severity, $_.path, $_.message } | Sort-Object)
}

function Invoke-ShadowRequest([string]$DotnetPath, [string]$DllPath, [string]$Operation, $Document) {
    $request = [ordered]@{ protocol_version = 1; operation = $Operation; payload = $Document } | ConvertTo-Json -Depth 40 -Compress
    return Invoke-JsonProcess $DotnetPath @($DllPath) $request
}

$architectureWasAdded = Set-DotnetArchitectureEnvironment
$publishRoot = $null
try {
    if (-not (Test-Path -LiteralPath $project -PathType Leaf)) { throw "Typed-core project is missing: $project" }
    if (-not (Test-Path -LiteralPath $fixtureRoot -PathType Container)) { throw "Operation contract corpus is missing: $fixtureRoot" }

    $sdkVersion = (& dotnet --version).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve pinned .NET SDK.' }
    $null = Invoke-DotnetCommand @('build', $project, '-c', 'Release', '--nologo', '--verbosity', 'quiet')
    $dllPath = Join-Path (Split-Path $project -Parent) 'bin\Release\net10.0\skills-manager-typed-core.dll'
    if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { throw "Typed-core output is missing: $dllPath" }

    . $operationModule
    . $receiptModule
    $dotnetPath = (Get-Command dotnet -ErrorAction Stop).Source
    $caseResults = [System.Collections.Generic.List[object]]::new()
    $mismatches = [System.Collections.Generic.List[object]]::new()

    foreach ($fixture in @(Get-ChildItem -LiteralPath $fixtureRoot -File -Filter '*.json' | Sort-Object Name)) {
        $document = Get-Content -LiteralPath $fixture.FullName -Raw | ConvertFrom-Json
        $isPlan = $fixture.Name -like '*plan*'
        $operation = if ($isPlan) { 'validate_plan' } else { 'validate_receipt' }
        $powershellResult = if ($isPlan) { Test-OperationPlanContract $document } else { Test-OperationReceiptContract $document }
        $processResult = Invoke-ShadowRequest $dotnetPath $dllPath $operation $document
        $typedResult = $processResult.stdout | ConvertFrom-Json
        $expectedExit = if ($powershellResult.pass) { 0 } else { 2 }
        $powerShellFingerprint = @(Get-FindingFingerprint $powershellResult)
        $typedFingerprint = @(Get-FindingFingerprint $typedResult)
        $parity = (
            [bool]$typedResult.pass -eq [bool]$powershellResult.pass -and
            $processResult.exit_code -eq $expectedExit -and
            ($powerShellFingerprint -join "`n") -ceq ($typedFingerprint -join "`n") -and
            [string]::IsNullOrWhiteSpace($processResult.stderr)
        )
        $case = [pscustomobject][ordered]@{
            fixture = $fixture.Name
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixture.FullName).Hash.ToLowerInvariant()
            operation = $operation
            powershell_pass = [bool]$powershellResult.pass
            typed_core_pass = [bool]$typedResult.pass
            typed_core_exit_code = $processResult.exit_code
            finding_count = @($typedResult.findings).Count
            parity = $parity
        }
        $caseResults.Add($case) | Out-Null
        if (-not $parity) {
            $mismatches.Add([pscustomobject]@{ fixture = $fixture.Name; powershell = $powerShellFingerprint; typed_core = $typedFingerprint; exit_code = $processResult.exit_code; stderr = $processResult.stderr }) | Out-Null
        }
    }

    $negativeCases = @(
        @{ name = 'invalid_json'; json = '{not-json'; code = 'request_json_invalid' },
        @{ name = 'protocol_version'; json = '{"protocol_version":2,"operation":"validate_plan","payload":{}}'; code = 'protocol_version_invalid' },
        @{ name = 'unsupported_operation'; json = '{"protocol_version":1,"operation":"write_host","payload":{}}'; code = 'operation_unsupported' },
        @{ name = 'missing_payload'; json = '{"protocol_version":1,"operation":"validate_plan"}'; code = 'payload_missing' }
    )
    $negativeResults = foreach ($negative in $negativeCases) {
        $processResult = Invoke-JsonProcess $dotnetPath @($dllPath) $negative.json
        $body = $processResult.stdout | ConvertFrom-Json
        $pass = $processResult.exit_code -eq 64 -and @($body.findings | Where-Object code -eq $negative.code).Count -eq 1 -and [string]::IsNullOrWhiteSpace($processResult.stderr)
        if (-not $pass) { $mismatches.Add([pscustomobject]@{ fixture = $negative.name; expected_code = $negative.code; exit_code = $processResult.exit_code; stdout = $processResult.stdout; stderr = $processResult.stderr }) | Out-Null }
        [pscustomobject]@{ name = $negative.name; expected_code = $negative.code; exit_code = $processResult.exit_code; pass = $pass }
    }

    $publishResults = @()
    if ($MeasurePublish) {
        $publishRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('skills-manager-typed-core-{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $publishRoot -Force | Out-Null
        $modes = @(
            [pscustomobject]@{ name = 'framework_dependent'; args = @('publish', $project, '-c', 'Release', '--nologo', '--no-self-contained', '-p:UseAppHost=false'); executable = 'dotnet'; artifact = 'skills-manager-typed-core.dll' },
            [pscustomobject]@{ name = 'self_contained'; args = @('publish', $project, '-c', 'Release', '--nologo', '-r', 'win-x64', '--self-contained', 'true', '-p:PublishSingleFile=false'); executable = 'skills-manager-typed-core.exe'; artifact = 'skills-manager-typed-core.exe' },
            [pscustomobject]@{ name = 'self_contained_single_file'; args = @('publish', $project, '-c', 'Release', '--nologo', '-r', 'win-x64', '--self-contained', 'true', '-p:PublishSingleFile=true'); executable = 'skills-manager-typed-core.exe'; artifact = 'skills-manager-typed-core.exe' }
        )
        $validPlan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'valid-plan.json') -Raw | ConvertFrom-Json
        $requestJson = [ordered]@{ protocol_version = 1; operation = 'validate_plan'; payload = $validPlan } | ConvertTo-Json -Depth 40 -Compress
        foreach ($mode in $modes) {
            $outputPath = Join-Path $publishRoot $mode.name
            $arguments = @($mode.args) + @('-o', $outputPath)
            $null = Invoke-DotnetCommand $arguments
            $files = @(Get-ChildItem -LiteralPath $outputPath -File -Recurse)
            $artifactPath = Join-Path $outputPath $mode.artifact
            $launchFile = if ($mode.executable -eq 'dotnet') { $dotnetPath } else { Join-Path $outputPath $mode.executable }
            $launchArguments = if ($mode.executable -eq 'dotnet') { @($artifactPath) } else { @() }
            $timings = @()
            foreach ($iteration in 1..3) {
                $processResult = Invoke-JsonProcess $launchFile $launchArguments $requestJson
                $body = $processResult.stdout | ConvertFrom-Json
                if ($processResult.exit_code -ne 0 -or -not $body.pass) { throw "Published mode failed: $($mode.name)" }
                $timings += [long]$processResult.elapsed_ms
            }
            $publishResults += [pscustomobject][ordered]@{
                mode = $mode.name
                file_count = $files.Count
                total_bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
                main_artifact_bytes = [long](Get-Item -LiteralPath $artifactPath).Length
                startup_ms = @($timings | Sort-Object)
                median_startup_ms = [long](@($timings | Sort-Object)[1])
            }
        }
    }

    $report = [pscustomobject][ordered]@{
        schema_version = 1
        captured_at = [datetimeoffset]::UtcNow.ToString('o')
        status = if ($mismatches.Count -eq 0) { 'pass' } else { 'fail' }
        protocol_version = 1
        seam = 'operation_contract_validation_v1'
        powershell_runtime_authoritative = $true
        typed_core_mode = 'shadow_only'
        sdk_version = $sdkVersion
        target_framework = 'net10.0'
        fixture_count = $caseResults.Count
        parity_count = @($caseResults | Where-Object parity).Count
        negative_case_count = @($negativeResults).Count
        negative_pass_count = @($negativeResults | Where-Object pass).Count
        cases = $caseResults.ToArray()
        negative_cases = @($negativeResults)
        publish = @($publishResults)
        mismatches = $mismatches.ToArray()
    }

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $absoluteReportPath = [System.IO.Path]::GetFullPath((Join-Path $root $ReportPath))
        $reportDirectory = Split-Path $absoluteReportPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
        [System.IO.File]::WriteAllText($absoluteReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    }

    $report | ConvertTo-Json -Depth 20
    if ($mismatches.Count -gt 0) { exit 1 }
}
finally {
    if ($publishRoot -and (Test-Path -LiteralPath $publishRoot)) { Remove-Item -LiteralPath $publishRoot -Recurse -Force }
    if ($architectureWasAdded) { Remove-Item Env:PROCESSOR_ARCHITECTURE -ErrorAction SilentlyContinue }
}
