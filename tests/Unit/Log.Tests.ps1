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

        It "redacts secrets recursively at the final log sink while preserving environment references" {
            $oldLogPath = $script:LogPath
            $oldActiveLogPath = $script:ActiveLogPath
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $script:LogPath = Join-Path $TestDrive "redacted-build.log"
                $script:ActiveLogPath = $script:LogPath
                $data = [ordered]@{
                    password = 'nested-password-value'
                    nested = [pscustomobject]@{
                        token = 'nested-token-value'
                        safe_template = '${UNIT_TEST_TOKEN_ENV}'
                        bearer_token_env_var = 'UNIT_TEST_TOKEN_ENV'
                    }
                }

                Write-LogRecord 'ERROR' 'token spaced-secret-value https://user:pass@example.invalid/repo?api_key=query-secret Authorization: Bearer bearer-secret' $data

                $content = Get-Content -LiteralPath $script:LogPath -Raw
                $content | Should Not Match 'spaced-secret-value|user:pass|query-secret|bearer-secret|nested-password-value|nested-token-value'
                $content | Should Match '<redacted>'
                $content | Should Match '\$\{UNIT_TEST_TOKEN_ENV\}'
                $content | Should Match 'UNIT_TEST_TOKEN_ENV'
            }
            finally {
                $script:LogPath = $oldLogPath
                $script:ActiveLogPath = $oldActiveLogPath
                $script:DryRun = $oldDryRun
            }
        }
    }
}
