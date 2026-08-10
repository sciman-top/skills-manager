$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

Describe 'PowerShell 7-only runtime contract' {
    It 'declares PowerShell 7-only support and an explicit unsupported-runtime boundary' {
        $runbook = Get-Content -LiteralPath (Join-Path $repoRoot 'docs\runbooks\powershell-runtime-compatibility.md') -Raw

        $runbook | Should Match 'PowerShell 7 \(`pwsh`\)'
        $runbook | Should Match 'PS7_ONLY_STATUS'
        $runbook | Should Match 'Windows PowerShell 5\.1 is not supported'
        $runbook | Should Match 'Migration guide'
        $runbook | Should Match 'Rollback'
        $runbook | Should Match 'repo_verified'
        $runbook | Should Not Match 'Bootstrap fallback'
        $runbook | Should Not Match '\| Compatibility smoke \|'
    }

    It 'requires PowerShell 7 in the source and keeps deterministic UTF-8 release encoding' {
        $versionSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Version.ps1') -Raw
        $buildSource = Get-Content -LiteralPath (Join-Path $repoRoot 'build.ps1') -Raw
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $repoRoot 'skills.ps1'))

        $versionSource | Should Match '(?m)^#requires -Version 7\.0\s*$'
        $buildSource | Should Match '(?m)^#requires -Version 7\.0\s*$'
        $buildSource | Should Match 'deterministic UTF-8 BOM'
        @($bytes[0..2]) -join ',' | Should Be '239,187,191'
    }

    It 'uses only pwsh in the single authoritative GitHub CI surface' {
        $github = Get-Content -LiteralPath (Join-Path $repoRoot '.github\workflows\ci.yml') -Raw

        $github | Should Match 'Verify PowerShell 7 runtime'
        $github | Should Not Match 'Windows PowerShell 5\.1'
        $github | Should Not Match 'shell:\s*powershell'
        Test-Path -LiteralPath (Join-Path $repoRoot 'azure-pipelines.yml') | Should Be $false
        Test-Path -LiteralPath (Join-Path $repoRoot '.gitlab-ci.yml') | Should Be $false
    }

    It 'fails closed instead of falling back to Windows PowerShell' {
        $installer = Get-Content -LiteralPath (Join-Path $repoRoot 'install.ps1') -Raw
        $cmd = Get-Content -LiteralPath (Join-Path $repoRoot 'skills.cmd') -Raw
        $core = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Core.ps1') -Raw
        $mcp = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Commands\Mcp.ps1') -Raw

        $installer | Should Match '(?m)^#requires -Version 7\.0\s*$'
        $installer | Should Match 'Assert-PowerShell7'
        $installer | Should Not Match 'powershell\.exe'
        $cmd | Should Match 'PowerShell 7\+ \(pwsh\) is required'
        $cmd | Should Not Match 'set "POWERSHELL_EXE=powershell\.exe"'
        $core | Should Not Match 'CODEX_ALLOW_WINDOWS_POWERSHELL'
        $core | Should Not Match 'Get-Command powershell'
        $mcp | Should Not Match '"powershell\.exe"'
        $mcp | Should Match '"pwsh\.exe"'
    }

    It 'passes the PowerShell 7 runtime floor and generated bundle parse' {
        $PSVersionTable.PSEdition | Should Be 'Core'
        $PSVersionTable.PSVersion.Major | Should BeGreaterThan 6
        [void][scriptblock]::Create((Get-Content -LiteralPath (Join-Path $repoRoot 'skills.ps1') -Raw))
    }
}
