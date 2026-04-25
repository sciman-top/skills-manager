function Initialize-WindowsProcessEnvironment {
    [CmdletBinding()]
    param(
        [switch]$Strict
    )

    $required = @(
        "ComSpec",
        "SystemRoot",
        "WINDIR",
        "APPDATA",
        "LOCALAPPDATA",
        "PROGRAMDATA"
    )

    $windowsDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows)
    $appData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
    $localAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    $commonAppData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonApplicationData)
    $systemDrive = [System.Environment]::GetEnvironmentVariable("SystemDrive", "Process")
    if ([string]::IsNullOrWhiteSpace($systemDrive) -and -not [string]::IsNullOrWhiteSpace($windowsDir)) {
        $systemDrive = ([System.IO.Path]::GetPathRoot($windowsDir)).TrimEnd('\')
    }
    if ([string]::IsNullOrWhiteSpace($commonAppData) -and -not [string]::IsNullOrWhiteSpace($systemDrive)) {
        $commonAppData = Join-Path $systemDrive "ProgramData"
    }

    $setProcessEnv = {
        param([string]$Name, [string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
        [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")
        return $true
    }

    if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("SystemRoot", "Process"))) {
        & $setProcessEnv "SystemRoot" $windowsDir | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("WINDIR", "Process"))) {
        $systemRoot = [System.Environment]::GetEnvironmentVariable("SystemRoot", "Process")
        & $setProcessEnv "WINDIR" $systemRoot | Out-Null
    }

    $systemRootForComSpec = [System.Environment]::GetEnvironmentVariable("SystemRoot", "Process")
    if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("ComSpec", "Process"))) {
        $comSpec = if (-not [string]::IsNullOrWhiteSpace($systemRootForComSpec)) {
            Join-Path $systemRootForComSpec "System32\cmd.exe"
        } else {
            $null
        }
        & $setProcessEnv "ComSpec" $comSpec | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("APPDATA", "Process"))) {
        & $setProcessEnv "APPDATA" $appData | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("LOCALAPPDATA", "Process"))) {
        & $setProcessEnv "LOCALAPPDATA" $localAppData | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("PROGRAMDATA", "Process"))) {
        & $setProcessEnv "PROGRAMDATA" $commonAppData | Out-Null
    }

    $remainingMissing = @(
        $required | Where-Object {
            [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($_, "Process"))
        }
    )

    $result = [pscustomobject]@{
        Ready = ($remainingMissing.Count -eq 0)
        Missing = @($remainingMissing)
        ProcessId = $PID
        ComputerName = [System.Environment]::MachineName
    }

    if (-not $result.Ready -and $Strict) {
        throw ("Missing required Windows process environment variables: {0}" -f ($result.Missing -join ", "))
    }

    return $result
}
