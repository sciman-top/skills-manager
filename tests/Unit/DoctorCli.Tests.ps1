. $PSScriptRoot\..\..\skills.ps1

Describe "Doctor CLI behavior" {
    It "Returns failing report under strict mode when risks exist" {
        $oldCfgPath = $script:CfgPath
        try {
            $script:CfgPath = Join-Path $TestDrive "skills.json"
            $cfg = @{
                vendors = @(
                    @{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    @{ path = "~/.codex/skills" },
                    @{ path = "~/.codex/skills" }
                )
                mappings = @(
                    @{ vendor = "vendor-a"; from = "a"; to = "skill-x" },
                    @{ vendor = "vendor-a"; from = "b"; to = "skill-x" }
                )
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                sync_mode = "link"
                update_force = $true
            } | ConvertTo-Json -Depth 20
            Set-Content -Path $script:CfgPath -Value $cfg -Encoding UTF8

            Mock Get-CimInstance { [pscustomobject]@{ Caption = "Windows"; OSArchitecture = "64-bit" } }
            Mock Test-NetConnection { $true }
            Mock Invoke-GitCapture { "git version 2.50.0" }
            Mock Get-ItemProperty { [pscustomobject]@{ LongPathsEnabled = 1 } }

            $report = Invoke-Doctor @("--json", "--strict")
            $report.pass | Should Be $false
            @($report.risks).Count | Should BeGreaterThan 0
            $report.strict | Should Be $true
            $report.summary.warn_count | Should BeGreaterThan 0
        }
        finally {
            $script:CfgPath = $oldCfgPath
        }
    }

    It "Accepts line-commented skills.json consistent with LoadCfg rules" {
        $oldCfgPath = $script:CfgPath
        try {
            $script:CfgPath = Join-Path $TestDrive "skills.json"
            $cfg = @'
{
  // this line comment is supported by LoadCfg
  "vendors": [{"name":"vendor-a","repo":"https://example.com/a.git","ref":"main"}],
  "targets": [{"path":"~/.codex/skills"}],
  "mappings": [],
  "imports": [],
  "mcp_servers": [],
  "mcp_targets": [],
  "sync_mode": "link",
  "update_force": true
}
'@
            Set-Content -Path $script:CfgPath -Value $cfg -Encoding UTF8

            Mock Get-CimInstance { [pscustomobject]@{ Caption = "Windows"; OSArchitecture = "64-bit" } }
            Mock Test-NetConnection { $true }
            Mock Invoke-GitCapture { "git version 2.50.0" }
            Mock Get-ItemProperty { [pscustomobject]@{ LongPathsEnabled = 1 } }

            $report = Invoke-Doctor @("--json")
            $report.checks.config.ok | Should Be $true
            $report.pass | Should Be $true
        }
        finally {
            $script:CfgPath = $oldCfgPath
        }
    }

    It "Falls back to runtime OS description when CIM is unavailable" {
        $oldCfgPath = $script:CfgPath
        try {
            $script:CfgPath = Join-Path $TestDrive "skills.json"
            $cfg = @{
                vendors = @(
                    @{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    @{ path = "~/.codex/skills" }
                )
                mappings = @()
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                sync_mode = "link"
                update_force = $true
            } | ConvertTo-Json -Depth 20
            Set-Content -Path $script:CfgPath -Value $cfg -Encoding UTF8

            Mock Get-CimInstance { throw "CIM unavailable" }
            Mock Test-NetConnection { $true }
            Mock Invoke-GitCapture { "git version 2.50.0" }
            Mock Get-ItemProperty { [pscustomobject]@{ LongPathsEnabled = 1 } }

            $report = Invoke-Doctor @("--json")
            $report.checks.os | Should Not Be "unknown"
            [string]::IsNullOrWhiteSpace([string]$report.checks.os) | Should Be $false
        }
        finally {
            $script:CfgPath = $oldCfgPath
        }
    }

    It "Fails config check for contract violations beyond JSON syntax" {
        $oldCfgPath = $script:CfgPath
        try {
            $script:CfgPath = Join-Path $TestDrive "skills-invalid-contract.json"
            $cfg = @{
                vendors = @(
                    @{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" }
                )
                targets = @(
                    @{ path = "~/.codex/skills" }
                )
                mappings = @(
                    @{ vendor = "vendor-a"; from = "..\\escape"; to = "skill-x" }
                )
                imports = @()
                mcp_servers = @()
                mcp_targets = @()
                sync_mode = "link"
                update_force = $true
            } | ConvertTo-Json -Depth 20
            Set-Content -Path $script:CfgPath -Value $cfg -Encoding UTF8

            Mock Get-CimInstance { [pscustomobject]@{ Caption = "Windows"; OSArchitecture = "64-bit" } }
            Mock Test-NetConnection { $true }
            Mock Invoke-GitCapture { "git version 2.50.0" }
            Mock Get-ItemProperty { [pscustomobject]@{ LongPathsEnabled = 1 } }

            $report = Invoke-Doctor @("--json", "--strict")
            $report.pass | Should Be $false
            $report.checks.config.ok | Should Be $false
            $report.checks.config.reason | Should Match "contract_error"
            (@($report.summary.errors) -contains "config_contract_error") | Should Be $true
        }
        finally {
            $script:CfgPath = $oldCfgPath
        }
    }

    It "Emits parseable JSON from the CLI entry without leading log lines" {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "skills.ps1") doctor --json 2>&1)
        $LASTEXITCODE | Should Be 0

        $text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
        $parsed = $null
        $thrown = $false
        try {
            $parsed = $text | ConvertFrom-Json
        }
        catch {
            $thrown = $true
        }

        $thrown | Should Be $false
        $parsed.checks.git.ok | Should Be $true
        $parsed.checks.config.ok | Should Be $true
    }
}
