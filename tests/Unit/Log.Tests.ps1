. $PSScriptRoot\..\..\skills.ps1

Describe "Log Rotation" {
    Context "Write-LogRecord" {
        It "Rotates build.log when max size is exceeded" {
            $oldLogPath = $script:LogPath
            $oldDryRun = $script:DryRun
            $oldMaxBytes = $script:LogMaxBytes
            $oldMaxBackups = $script:LogMaxBackups
            $oldGlobalLogPath = $global:LogPath
            $oldGlobalDryRun = $global:DryRun
            $oldGlobalMaxBytes = $global:LogMaxBytes
            $oldGlobalMaxBackups = $global:LogMaxBackups
            try {
                $script:DryRun = $false
                $script:LogPath = Join-Path $TestDrive "build.log"
                $script:LogMaxBytes = 120
                $script:LogMaxBackups = 2
                $global:DryRun = $script:DryRun
                $global:LogPath = $script:LogPath
                $global:LogMaxBytes = $script:LogMaxBytes
                $global:LogMaxBackups = $script:LogMaxBackups

                Set-Content -Path $script:LogPath -Value ("x" * 200) -NoNewline
                Log "rotation-test" "INFO" -NoHost

                (Test-Path $script:LogPath) | Should Be $true
                (Test-Path ($script:LogPath + ".1")) | Should Be $true

                $content = Get-Content -Path $script:LogPath -Raw
                $content | Should Match "rotation-test"
            }
            finally {
                $script:LogPath = $oldLogPath
                $script:DryRun = $oldDryRun
                $script:LogMaxBytes = $oldMaxBytes
                $script:LogMaxBackups = $oldMaxBackups
                $global:LogPath = $oldGlobalLogPath
                $global:DryRun = $oldGlobalDryRun
                $global:LogMaxBytes = $oldGlobalMaxBytes
                $global:LogMaxBackups = $oldGlobalMaxBackups
            }
        }
    }
}
