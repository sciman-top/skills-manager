# Contract test for the AI risk-control handover payload manifest.
#
# docs/handover/ai-risk-control/ is a cross-machine deployment payload, not repo
# runtime, so it is not covered by verify-skill-integrity.ps1 or the skill
# integrity checks. This suite keeps MANIFEST.sha256 honest: editing a bundled
# tool without refreshing the manifest (or shipping a new tool that was never
# declared) fails here instead of silently drifting.
#
# docs/handover/ai-risk-control/.gitattributes pins '* -text', so the recorded
# byte hashes are stable across checkouts.

BeforeAll {
    $script:handoverRoot = Join-Path $PSScriptRoot '../../docs/handover/ai-risk-control'
    $script:manifestPath = Join-Path $script:handoverRoot 'MANIFEST.sha256'

    function Get-ManifestEntries {
        Get-Content -LiteralPath $script:manifestPath |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                $parts = $_.Trim() -split '\s+', 2
                [pscustomobject]@{ relative = $parts[0].Replace('\', '/'); sha256 = $parts[1] }
            }
    }
}

Describe 'AI risk-control handover manifest' {
    It 'exists and declares entries' {
        Test-Path -LiteralPath $script:manifestPath -PathType Leaf | Should -BeTrue
        @(Get-ManifestEntries).Count | Should -BeGreaterThan 0
    }

    It 'matches every declared file byte for byte' {
        $drift = @()
        foreach ($entry in @(Get-ManifestEntries)) {
            $full = Join-Path $script:handoverRoot $entry.relative
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                $drift += ("missing: {0}" -f $entry.relative)
                continue
            }
            $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $entry.sha256.ToLowerInvariant()) {
                $drift += ("drift: {0}" -f $entry.relative)
            }
        }
        ($drift -join '; ') | Should -BeNullOrEmpty
    }

    It 'declares every shipped tool file' {
        $declared = @(Get-ManifestEntries | ForEach-Object { $_.relative })
        $shipped = @(
            Get-ChildItem -LiteralPath (Join-Path $script:handoverRoot 'tools') -Recurse -File |
                ForEach-Object { [IO.Path]::GetRelativePath($script:handoverRoot, $_.FullName).Replace('\', '/') } |
                Sort-Object
        )
        @($shipped).Count | Should -BeGreaterThan 0
        foreach ($tool in $shipped) {
            $declared | Should -Contain $tool
        }
    }
}
