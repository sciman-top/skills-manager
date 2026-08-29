Describe 'release-update-worker staged payload integrity' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $workerSource = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\release\release-update-worker.ps1') -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($workerSource, [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Assert-StagedPayloadIntegrity' }, $true)
        if ($null -eq $fn) { throw 'Assert-StagedPayloadIntegrity not found in worker script' }
        . ([scriptblock]::Create($fn.Extent.Text))
        $script:roots = [System.Collections.Generic.List[string]]::new()

        function New-StagedPackage {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('worker-integrity-' + [guid]::NewGuid().ToString('N'))
            $script:roots.Add($root) | Out-Null
            New-Item -ItemType Directory -Path $root | Out-Null
            $files = @()
            foreach ($relative in @('skills.ps1', 'install.ps1')) {
                $path = Join-Path $root $relative
                Set-Content -LiteralPath $path -Value ('payload ' + $relative) -Encoding UTF8
                $files += [ordered]@{
                    path   = $relative
                    size   = (Get-Item -LiteralPath $path).Length
                    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
            $manifest = [ordered]@{ schema_version = 2; product = 'skills-manager'; version = 'v9.99'; package = 'bootstrap'; publishable = $true; files = @($files) }
            $manifestPath = Join-Path $root 'RELEASE-MANIFEST.json'
            $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
            return [pscustomobject]@{
                root           = $root
                manifest_sha   = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
                manifest_path  = $manifestPath
            }
        }
    }

    AfterAll {
        foreach ($r in @($script:roots)) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'passes a genuine freshly built package including the manifest itself' {
        $pkg = New-StagedPackage
        { Assert-StagedPayloadIntegrity $pkg.root $pkg.manifest_sha } | Should -Not -Throw
    }

    It 'rejects a payload file modified after handoff' {
        $pkg = New-StagedPackage
        Set-Content -LiteralPath (Join-Path $pkg.root 'skills.ps1') -Value 'tampered' -Encoding UTF8
        { Assert-StagedPayloadIntegrity $pkg.root $pkg.manifest_sha } | Should -Throw '*modified after handoff*'
    }

    It 'rejects an unmanifested file added after handoff' {
        $pkg = New-StagedPackage
        Set-Content -LiteralPath (Join-Path $pkg.root 'UNEXPECTED.ps1') -Value 'payload' -Encoding UTF8
        # The count guard fires first for an added file; the per-file
        # unmanifested check covers same-count swaps.
        { Assert-StagedPayloadIntegrity $pkg.root $pkg.manifest_sha } | Should -Throw '*does not match the manifest*'
    }

    It 'rejects a swapped manifest that no longer matches the handoff hash' {
        $pkg = New-StagedPackage
        $manifest = Get-Content -LiteralPath $pkg.manifest_path -Raw | ConvertFrom-Json
        $manifest.version = 'v9.98'
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $pkg.manifest_path -Encoding utf8
        { Assert-StagedPayloadIntegrity $pkg.root $pkg.manifest_sha } | Should -Throw '*changed after handoff*'
    }
}
