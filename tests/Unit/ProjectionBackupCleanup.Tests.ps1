BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $scriptPath = Join-Path $repoRoot 'scripts\cleanup-stale-projection-backups.ps1'
}

Describe 'Projection backup cleanup safety' {
    It 'is limited to the exact ignored backup root and missing agent targets' {
        $text = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

        $text | Should -Match 'BackupRoot must equal the managed backup root'
        $text | Should -Match 'targetPath.StartsWith\(\$agentPrefix'
        $text | Should -Match "LinkType -ne 'Junction'"
        $text | Should -Match 'ShouldProcess'
        $text | Should -Match 'FileAttributes]::ReadOnly'
        $text | Should -Match 'Directory]::Delete'
        $text | Should -Match '\$false\)'
    }

    It 'supports a non-mutating WhatIf discovery run' {
        $text = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8
        $text | Should -Match 'SupportsShouldProcess'
        $text | Should -Match 'remaining_stale'
    }
}
