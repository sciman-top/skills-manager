#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('app_server', 'cli', 'offline')][string]$Mode = 'app_server',
    [string]$Cwd = (Get-Location).Path,
    [string]$ConfigPath = '',
    [string]$ConfigText = '',
    [string]$OutputPath = '',
    [ValidateRange(5, 120)][int]$TimeoutSeconds = 30,
    [switch]$ForceRefresh,
    [string]$CapturedAt = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\HostCapabilitySnapshot.ps1')
. (Join-Path $repoRoot 'src\Application\HostCapabilityResolution.ps1')
. (Join-Path $repoRoot 'src\Infrastructure\HostCapabilityAdapters.ps1')

if ([string]::IsNullOrWhiteSpace($CapturedAt)) { $CapturedAt = [DateTimeOffset]::UtcNow.ToString('o') }

function Get-CodexLaunchSpec {
    $shim = @(Get-Command codex.ps1 -All -ErrorAction SilentlyContinue | Select-Object -First 1)
    $pwsh = @(Get-Command pwsh -All -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandType -eq 'Application' -and [IO.Path]::GetExtension([string]$_.Source) -ieq '.exe'
    } | Select-Object -First 1)
    if ($shim.Count -gt 0 -and $pwsh.Count -gt 0) {
        return [pscustomobject]@{
            file_name = [string]$pwsh[0].Source
            arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', [string]$shim[0].Source)
            launcher = 'pwsh-codex-shim'
        }
    }
    $commands = @(Get-Command codex -All -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandType -eq 'Application' -and [IO.Path]::GetExtension([string]$_.Source) -ieq '.exe'
    })
    if ($commands.Count -eq 0) { return $null }
    return [pscustomobject]@{ file_name = [string]$commands[0].Source; arguments = @(); launcher = 'native-codex-exe' }
}

function Invoke-BoundedNativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [string[]]$Arguments = @(),
        [string]$InputText = '',
        [string[]]$ExpectedJsonRpcResponseIds = @(),
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FileName
    foreach ($argument in @($Arguments)) { $startInfo.ArgumentList.Add([string]$argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ started = $false; timed_out = $false; exit_code = $null; stdout = ''; stderr = 'native process did not start.' }
        }
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not [string]::IsNullOrEmpty($InputText)) { $process.StandardInput.Write($InputText); $process.StandardInput.Flush() }

        if (@($ExpectedJsonRpcResponseIds).Count -gt 0) {
            $pendingIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($id in @($ExpectedJsonRpcResponseIds)) { [void]$pendingIds.Add([string]$id) }
            $stdoutLines = [Collections.Generic.List[string]]::new()
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $readTask = $null
            $streamEnded = $false
            while ($pendingIds.Count -gt 0 -and -not $streamEnded -and $timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
                if ($null -eq $readTask) { $readTask = $process.StandardOutput.ReadLineAsync() }
                if (-not $readTask.Wait(100)) { continue }
                $line = $readTask.Result
                $readTask = $null
                if ($null -eq $line) { $streamEnded = $true; continue }
                $stdoutLines.Add([string]$line) | Out-Null
                try {
                    $message = $line | ConvertFrom-Json -ErrorAction Stop
                    if ($null -ne $message.id) { [void]$pendingIds.Remove([string]$message.id) }
                }
                catch { }
            }
            $process.StandardInput.Close()
            $responseComplete = $pendingIds.Count -eq 0
            $remainingMs = [Math]::Max(1, [int](($TimeoutSeconds * 1000) - $timer.ElapsedMilliseconds))
            $exited = $process.WaitForExit([Math]::Min($remainingMs, 2000))
            if (-not $exited) {
                try { $process.Kill($true) } catch { }
                $process.WaitForExit(2000)
            }
            $stdout = $stdoutLines -join "`n"
            $stderr = if ($stderrTask.Wait(2000)) { [string]$stderrTask.Result } else { '' }
            return [pscustomobject]@{
                started = $true
                timed_out = -not $responseComplete
                response_complete = $responseComplete
                exit_code = if ($exited) { $process.ExitCode } else { $null }
                stdout = $stdout
                stderr = $stderr
            }
        }

        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $exited = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $exited) {
            try { $process.Kill($true) } catch { }
            $process.WaitForExit(2000)
        }
        $stdout = if ($stdoutTask.Wait(2000)) { [string]$stdoutTask.Result } else { '' }
        $stderr = if ($stderrTask.Wait(2000)) { [string]$stderrTask.Result } else { '' }
        return [pscustomobject]@{
            started = $true
            timed_out = -not $exited
            exit_code = if ($exited) { $process.ExitCode } else { $null }
            stdout = $stdout
            stderr = $stderr
        }
    }
    catch {
        return [pscustomobject]@{ started = $false; timed_out = $false; exit_code = $null; stdout = ''; stderr = $_.Exception.Message }
    }
    finally { $process.Dispose() }
}

function Protect-AdapterDiagnostic([string]$Message) {
    $safe = Protect-OperationSensitiveString (($Message -replace '\s+', ' ').Trim())
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'native adapter did not provide a diagnostic message.' }
    if ($safe.Length -gt 240) { return $safe.Substring(0, 240) }
    return $safe
}

function Add-AdapterTransportDiagnostic {
    param([Parameter(Mandatory = $true)]$Snapshot, [string]$Code, [string]$Message)

    $diagnostic = [pscustomobject][ordered]@{ code = $Code; message = Protect-AdapterDiagnostic $Message }
    $Snapshot.errors = @($Snapshot.errors) + $diagnostic
    if ([string]$Snapshot.status -eq 'complete') { $Snapshot.status = 'partial' }
    return $Snapshot
}

function ConvertFrom-AppServerStdout {
    param([string]$Stdout)

    $messages = New-Object System.Collections.Generic.List[object]
    foreach ($line in @($Stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        try {
            $parsed = $line | ConvertFrom-Json -ErrorAction Stop
            if (Test-OperationArray $parsed) { foreach ($item in @($parsed)) { $messages.Add($item) | Out-Null } }
            else { $messages.Add($parsed) | Out-Null }
        }
        catch { }
    }
    return @($messages.ToArray())
}

function Invoke-AppServerSnapshot {
    param([string]$WorkingDirectory, [int]$TimeoutSeconds, [bool]$ForceReload)

    $launcher = Get-CodexLaunchSpec
    if ($null -eq $launcher) {
        return New-HostCapabilityUnknownAdapterSnapshot -Adapter 'app_server' -Source 'app_server' -Surface 'app_server' -CapturedAt $CapturedAt -Status 'platform_na' -UnknownReason 'app_server_unavailable_platform_na' -PlatformNa
    }
    $requests = @(
        [ordered]@{ jsonrpc = '2.0'; id = 0; method = 'initialize'; params = [ordered]@{ clientInfo = [ordered]@{ name = 'skills_manager_snapshot'; title = 'skills-manager capability snapshot'; version = '1.0.0' }; capabilities = [ordered]@{ optOutNotificationMethods = @('skills/changed') } } },
        [ordered]@{ jsonrpc = '2.0'; method = 'initialized'; params = @{} },
        [ordered]@{ jsonrpc = '2.0'; id = 1; method = 'config/read'; params = @{} },
        [ordered]@{ jsonrpc = '2.0'; id = 2; method = 'model/list'; params = @{} },
        [ordered]@{ jsonrpc = '2.0'; id = 3; method = 'modelProvider/capabilities/read'; params = @{} },
        [ordered]@{ jsonrpc = '2.0'; id = 4; method = 'skills/list'; params = [ordered]@{ cwds = @([IO.Path]::GetFullPath($WorkingDirectory)); forceReload = $ForceReload } }
    )
    $inputText = (($requests | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress }) -join "`n") + "`n"
    $run = Invoke-BoundedNativeProcess -FileName $launcher.file_name -Arguments (@($launcher.arguments) + @('app-server', '--stdio')) -InputText $inputText -ExpectedJsonRpcResponseIds @('1', '2', '3', '4') -TimeoutSeconds $TimeoutSeconds
    $messages = ConvertFrom-AppServerStdout $run.stdout
    $byId = @{}
    foreach ($message in @($messages)) {
        if (Test-OperationObjectProperty $message 'id') { $byId[[string](Get-OperationObjectProperty $message 'id')] = $message }
    }
    $transportMessage = if ($run.timed_out) { 'App Server probe timed out.' } elseif (-not $run.started) { $run.stderr } elseif ($run.exit_code -ne 0) { $run.stderr } else { '' }
    $responses = [ordered]@{}
    foreach ($entry in @(
        [pscustomobject]@{ id = '1'; name = 'config_read'; method = 'config/read' },
        [pscustomobject]@{ id = '2'; name = 'model_list'; method = 'model/list' },
        [pscustomobject]@{ id = '3'; name = 'model_provider_capabilities_read'; method = 'modelProvider/capabilities/read' },
        [pscustomobject]@{ id = '4'; name = 'skills_list'; method = 'skills/list' }
    )) {
        if ($byId.ContainsKey($entry.id)) { $responses[$entry.name] = $byId[$entry.id] }
        else { $responses[$entry.name] = [pscustomobject]@{ error = [pscustomobject]@{ message = if ($transportMessage) { $transportMessage } else { 'App Server response was not received before the bounded probe ended.' } } } }
    }
    $snapshot = New-HostCapabilitySnapshotFromAppServer -Responses ([pscustomobject]$responses) -Surface 'app_server' -CapturedAt $CapturedAt
    if ($transportMessage) { $snapshot = Add-AdapterTransportDiagnostic -Snapshot $snapshot -Code 'app_server_transport_partial' -Message $transportMessage }
    $snapshot | Add-Member -NotePropertyName native_probe -NotePropertyValue ([pscustomobject]@{ mode = 'app_server'; started = $run.started; timed_out = $run.timed_out; exit_code = $run.exit_code }) -Force
    return $snapshot
}

function Invoke-CliSnapshot {
    $launcher = Get-CodexLaunchSpec
    if ($null -eq $launcher) {
        return New-HostCapabilitySnapshotFromCli -CapturedAt $CapturedAt -ExecutableAvailable $false
    }
    $run = Invoke-BoundedNativeProcess -FileName $launcher.file_name -Arguments (@($launcher.arguments) + @('debug', 'prompt-input', '-c', 'model_provider="openai"', 'p6-host-capability-snapshot')) -TimeoutSeconds $TimeoutSeconds
    if (-not $run.started -or $run.timed_out -or $run.exit_code -ne 0) {
        $snapshot = New-HostCapabilitySnapshotFromCli -CapturedAt $CapturedAt -ExecutableAvailable $true
        $code = if ($run.timed_out) { 'cli_timeout_partial' } else { 'cli_probe_failed' }
        $message = if ($run.timed_out) { 'CLI prompt-input probe timed out.' } else { $run.stderr }
        return Add-AdapterTransportDiagnostic -Snapshot $snapshot -Code $code -Message $message
    }
    $snapshot = New-HostCapabilitySnapshotFromCli -PromptInput $run.stdout -CapturedAt $CapturedAt -ExecutableAvailable $true
    $snapshot | Add-Member -NotePropertyName native_probe -NotePropertyValue ([pscustomobject]@{ mode = 'cli'; started = $run.started; timed_out = $run.timed_out; exit_code = $run.exit_code }) -Force
    return $snapshot
}

function Write-SnapshotOutput {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $json = $Snapshot | ConvertTo-Json -Depth 50
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
        $parent = Split-Path -Parent $fullOutputPath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($fullOutputPath, $json, [Text.UTF8Encoding]::new($false))
    }
    Write-Output $json
}

switch ($Mode) {
    'offline' {
        $snapshot = New-HostCapabilitySnapshotFromConfigFallback -ConfigText $ConfigText -ConfigPath $ConfigPath -Surface 'offline' -CapturedAt $CapturedAt
    }
    'cli' {
        $snapshot = Invoke-CliSnapshot
    }
    default {
        $snapshot = Invoke-AppServerSnapshot -WorkingDirectory $Cwd -TimeoutSeconds $TimeoutSeconds -ForceReload ([bool]$ForceRefresh)
    }
}

Write-SnapshotOutput $snapshot
