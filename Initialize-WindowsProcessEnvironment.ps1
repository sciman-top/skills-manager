function Initialize-WindowsProcessEnvironment {
    [CmdletBinding()]
    param(
        [switch]$Strict
    )

    function Set-DefaultProcessEnvironmentVariable {
        param([string]$Name, [string]$Value)

        if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Value)) {
            return
        }
        if ([string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($Name, "Process"))) {
            [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")
        }
    }

    function Read-CodexShellEnvironmentPolicySet {
        $codexHome = [System.Environment]::GetEnvironmentVariable("CODEX_HOME", "Process")
        if ([string]::IsNullOrWhiteSpace($codexHome)) {
            $profileRoot = [System.Environment]::GetEnvironmentVariable("USERPROFILE", "Process")
            if ([string]::IsNullOrWhiteSpace($profileRoot)) {
                $profileRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
            }
            if ([string]::IsNullOrWhiteSpace($profileRoot)) {
                return @{}
            }
            $codexHome = Join-Path $profileRoot ".codex"
        }

        $configPath = Join-Path $codexHome "config.toml"
        if (-not (Test-Path -LiteralPath $configPath)) {
            return @{}
        }

        $values = @{}
        $insidePolicySet = $false
        foreach ($rawLine in Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue) {
            $line = [string]$rawLine
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
                continue
            }
            if ($trimmed -match '^\[(.+)\]$') {
                $insidePolicySet = ($matches[1] -eq "shell_environment_policy.set")
                continue
            }
            if (-not $insidePolicySet) {
                continue
            }
            if ($trimmed -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"(.*)"\s*$') {
                $name = $matches[1]
                $value = $matches[2].Replace('\"', '"').Replace('\\', '\')
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $values[$name] = $value
                }
            }
        }
        return $values
    }

    function Import-SafeCodexShellEnvironmentPolicy {
        $safeNames = @(
            "COMSPEC", "ComSpec",
            "WINDIR", "windir",
            "SYSTEMROOT", "SystemRoot",
            "APPDATA",
            "LOCALAPPDATA",
            "PROGRAMDATA",
            "ProgramFiles",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy"
        )

        $policySet = Read-CodexShellEnvironmentPolicySet
        foreach ($name in $safeNames) {
            if ($policySet.ContainsKey($name)) {
                Set-DefaultProcessEnvironmentVariable -Name $name -Value ([string]$policySet[$name])
                continue
            }
            $userValue = [System.Environment]::GetEnvironmentVariable($name, "User")
            if (-not [string]::IsNullOrWhiteSpace($userValue)) {
                Set-DefaultProcessEnvironmentVariable -Name $name -Value $userValue
                continue
            }
            $machineValue = [System.Environment]::GetEnvironmentVariable($name, "Machine")
            if (-not [string]::IsNullOrWhiteSpace($machineValue)) {
                Set-DefaultProcessEnvironmentVariable -Name $name -Value $machineValue
            }
        }
    }

    Import-SafeCodexShellEnvironmentPolicy

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
