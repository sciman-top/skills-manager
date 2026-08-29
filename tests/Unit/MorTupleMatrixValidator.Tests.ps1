Describe 'MOR tuple matrix validator fail-closed behavior' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:validatorPath = Join-Path $repoRoot 'scripts\quality\validate-mor-tuple-matrix.ps1'
        $script:canonicalPath = Join-Path $repoRoot 'docs\decision\MOR-090-tuple-matrix.json'
        $script:tempFiles = [System.Collections.Generic.List[string]]::new()

        function Invoke-ValidatorAgainst([string]$MatrixJson) {
            $fixture = Join-Path ([IO.Path]::GetTempPath()) ('mor-matrix-' + [guid]::NewGuid().ToString('N') + '.json')
            $script:tempFiles.Add($fixture) | Out-Null
            Set-Content -LiteralPath $fixture -Value $MatrixJson -Encoding UTF8
            $output = & pwsh -NoProfile -File $script:validatorPath -Path $fixture 2>&1
            return [pscustomobject]@{ exit_code = $LASTEXITCODE; output = @($output) }
        }
    }

    AfterAll {
        foreach ($f in @($script:tempFiles)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }

    It 'passes the canonical matrix unchanged' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('mor-matrix-' + [guid]::NewGuid().ToString('N') + '.json')
        $script:tempFiles.Add($fixture) | Out-Null
        Copy-Item -LiteralPath $script:canonicalPath -Destination $fixture
        $output = & pwsh -NoProfile -File $script:validatorPath -Path $fixture 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output -join "`n") | Should -Match 'MOR tuple matrix validation passed'
    }

    It 'rejects an empty object' {
        $r = Invoke-ValidatorAgainst '{}'
        $r.exit_code | Should -Be 1
    }

    It 'rejects an empty tuples array' {
        $r = Invoke-ValidatorAgainst '{"tuples":[]}'
        $r.exit_code | Should -Be 1
    }

    It 'rejects a structurally valid tuple whose verified status has no facts' {
        $json = @'
{
  "_meta": {
    "status_enum": ["verified", "partial", "pending"],
    "contract_layers": ["host_adapter"]
  },
  "tuples": [
    {
      "surface": "x",
      "layer": "host_adapter",
      "model": "m",
      "effort": "low",
      "field_path": "f",
      "status": "verified",
      "facts": []
    }
  ]
}
'@
        $r = Invoke-ValidatorAgainst $json
        $r.exit_code | Should -Be 1
    }
}
