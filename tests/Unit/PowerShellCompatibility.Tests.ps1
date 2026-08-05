$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

Describe 'PowerShell runtime compatibility contract' {
    It 'declares PowerShell 7 as primary and Windows PowerShell 5.1 as bounded compatibility' {
        $runbook = Get-Content -LiteralPath (Join-Path $repoRoot 'docs\runbooks\powershell-runtime-compatibility.md') -Raw

        $runbook | Should Match 'PowerShell 7 \(`pwsh`\)'
        $runbook | Should Match 'Windows PowerShell 5\.1'
        $runbook | Should Match 'Compatibility removal gate'
        $runbook | Should Match 'Typed-core migration boundary'
        $runbook | Should Match 'C#/\.NET typed core'
        $runbook | Should Match 'dual implementations or dual configuration truth are forbidden'
        $runbook | Should Match 'does not promise every workflow'
        $runbook | Should Match 'repo_verified'
    }

    It 'keeps the generated entry at the 5.1 compatibility floor and current UTF-8 BOM release encoding' {
        $versionSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Version.ps1') -Raw
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $repoRoot 'skills.ps1'))

        $versionSource | Should Match '(?m)^#requires -Version 5\.1\s*$'
        @($bytes[0..2]) -join ',' | Should Be '239,187,191'
    }

    It 'uses pwsh for authoritative CI gates and powershell only for bounded smoke' {
        $github = Get-Content -LiteralPath (Join-Path $repoRoot '.github\workflows\ci.yml') -Raw
        $azure = Get-Content -LiteralPath (Join-Path $repoRoot 'azure-pipelines.yml') -Raw

        $github | Should Match 'Verify PowerShell 7 primary runtime'
        $github | Should Match 'Windows PowerShell 5\.1 bounded compatibility smoke'
        $azure | Should Match 'Verify PowerShell 7 primary runtime'
        $azure | Should Match 'Windows PowerShell 5\.1 bounded compatibility smoke'
    }

    It 'keeps installer selection pwsh-first with Windows PowerShell fallback' {
        $installer = Get-Content -LiteralPath (Join-Path $repoRoot 'install.ps1') -Raw
        $pwshIndex = $installer.IndexOf('Get-Command pwsh')
        $legacyIndex = $installer.IndexOf('Get-Command powershell.exe')

        $pwshIndex | Should BeGreaterThan -1
        $legacyIndex | Should BeGreaterThan $pwshIndex
        $installer | Should Match '优先安装 PowerShell 7'
    }

    It 'passes the PowerShell 7 primary runtime floor' {
        $PSVersionTable.PSVersion.Major | Should BeGreaterThan 6
        [void][scriptblock]::Create((Get-Content -LiteralPath (Join-Path $repoRoot 'skills.ps1') -Raw))
    }

    It 'passes the bounded Windows PowerShell 5.1 parse and plain-object smoke when available' {
        $legacy = Get-Command powershell.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $legacy) {
            Write-Host 'powershell.exe unavailable: platform_na; PS7 parse remains the alternative evidence.'
            return
        }
        $entry = (Join-Path $repoRoot 'skills.ps1').Replace("'", "''")
        $operation = (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1').Replace("'", "''")
        $receipt = (Join-Path $repoRoot 'src\Domain\Receipt.ps1').Replace("'", "''")
        $plugin = (Join-Path $repoRoot 'src\Domain\PluginManifest.ps1').Replace("'", "''")
        $scriptText = "[void][scriptblock]::Create((Get-Content -Raw '$entry')); . '$operation'; . '$receipt'; . '$plugin'; `$p=New-OperationPlan -OperationId compat -Domain runtime -Mode dry_run -CreatedAt 2026-08-01T08:00:00Z; `$r=New-OperationReceipt -OperationId compat -Status dry_run -StartedAt 2026-08-01T08:00:00Z -CompletedAt 2026-08-01T08:00:01Z; `$m=Test-PluginManifestContract ([pscustomobject]@{name='compat';version='1.0.0';description='compat';repository='https://example.invalid/compat';license='MIT';skills='./skills/'}) '' `$true; [pscustomobject]@{version=`$PSVersionTable.PSVersion.ToString();plan=`$p.schema_version;receipt=`$r.schema_version;plugin=`$m.shape}|ConvertTo-Json -Compress"

        $output = @(& $legacy.Source -NoProfile -ExecutionPolicy Bypass -Command $scriptText 2>&1)
        $exitCode = $LASTEXITCODE
        $result = ($output -join "`n") | ConvertFrom-Json

        $exitCode | Should Be 0
        $result.version | Should Match '^5\.1\.'
        $result.plan | Should Be 1
        $result.receipt | Should Be 1
        $result.plugin | Should Be 'skills_only'
    }
}
