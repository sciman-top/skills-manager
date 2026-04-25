$ErrorActionPreference = "Stop"

Describe "git-acl-guard script" {
    BeforeAll {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $repoRoot "scripts\git-acl-guard.ps1"
        $fixScriptPath = Join-Path $repoRoot "scripts\fix-git-acl.ps1"
    }

    It "Stores ACL backups under reports/runtime/acl-backups by default" {
        $raw = Get-Content -LiteralPath $scriptPath -Raw
        $raw | Should Match "reports\\runtime\\acl-backups"

        $fixRaw = Get-Content -LiteralPath $fixScriptPath -Raw
        $fixRaw | Should Match "reports\\runtime\\acl-backups"
    }

    It "Writes FailureReason and JSON fields when DENY exists without fix mode" {
        $workspace = Join-Path $TestDrive ("git-acl-guard-nofix-" + [guid]::NewGuid().ToString("N"))
        $repo = Join-Path $workspace "repo"
        $gitDir = Join-Path $repo ".git"
        $denyFile = Join-Path $gitDir "deny.txt"
        $reportPath = Join-Path $workspace "report.json"
        $principal = "{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME

        New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
        Set-Content -LiteralPath $denyFile -Value "deny"
        icacls $denyFile /deny "${principal}:(R)" | Out-Null

        try {
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -GitDir $gitDir -JsonReport $reportPath 2>&1)
            $exitCode = $LASTEXITCODE
            $exitCode | Should Be 3

            (Test-Path -LiteralPath $reportPath) | Should Be $true
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json

            $report.Success | Should Be $false
            $report.FailureReason | Should Be "deny_detected_requires_fix_mode"
            ($report.BeforeDenyCount -gt 0) | Should Be $true
            ($report.PSObject.Properties.Name -contains "BeforeAclReadErrorCount") | Should Be $true
            ($report.PSObject.Properties.Name -contains "FailureReason") | Should Be $true
        }
        finally {
            icacls $denyFile /remove:d "$principal" | Out-Null
            Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Skips repair under WhatIf and records ShouldProcess outcome in JSON report" {
        $workspace = Join-Path $TestDrive ("git-acl-guard-whatif-" + [guid]::NewGuid().ToString("N"))
        $repo = Join-Path $workspace "repo"
        $gitDir = Join-Path $repo ".git"
        $denyFile = Join-Path $gitDir "deny.txt"
        $reportPath = Join-Path $workspace "report.json"
        $principal = "{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME

        New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
        Set-Content -LiteralPath $denyFile -Value "deny"
        icacls $denyFile /deny "${principal}:(R)" | Out-Null

        try {
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -GitDir $gitDir -LightFix -WhatIf -JsonReport $reportPath 2>&1)
            $exitCode = $LASTEXITCODE
            $exitCode | Should Be 0

            (Test-Path -LiteralPath $reportPath) | Should Be $true
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json

            $report.Success | Should Be $true
            $report.RepairStrategy | Should Be "skipped_by_shouldprocess"
            $report.FailureReason | Should Be "repair_skipped_by_shouldprocess"
            $report.SkippedByShouldProcess | Should Be $true
            ($report.PSObject.Properties.Name -contains "WhatIfMode") | Should Be $true
            $report.WhatIfMode | Should Be $true

            $denyRules = @((Get-Acl -LiteralPath $denyFile).Access | Where-Object { $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny })
            ($denyRules.Count -gt 0) | Should Be $true
        }
        finally {
            icacls $denyFile /remove:d "$principal" | Out-Null
            Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
