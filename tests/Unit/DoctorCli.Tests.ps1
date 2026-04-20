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
}
