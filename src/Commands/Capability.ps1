function Parse-ReadOnlyCapabilityOptions([object[]]$Tokens) {
    $result = [ordered]@{ json = $false; out_path = $null; view = $null; host_snapshot = $null; host_probe = $false }
    for ($i = 0; $i -lt @($Tokens).Count; $i++) {
        $token = [string]$Tokens[$i]
        switch ($token.ToLowerInvariant()) {
            '--json' { $result.json = $true }
            '--out' { if ($i + 1 -ge @($Tokens).Count) { throw '--out requires a report file path.' }; $i++; $result.out_path = [string]$Tokens[$i] }
            '--view' { if ($i + 1 -ge @($Tokens).Count) { throw '--view requires a view name.' }; $i++; $result.view = [string]$Tokens[$i] }
            '--host-snapshot' { if ($i + 1 -ge @($Tokens).Count) { throw '--host-snapshot requires a snapshot file path.' }; $i++; $result.host_snapshot = [string]$Tokens[$i] }
            '--host-probe' { $result.host_probe = $true }
            default { throw ('Unknown capability-inventory option: {0}' -f $token) }
        }
    }
    return [pscustomobject]$result
}

function Invoke-CapabilityInventoryCommand([object[]]$Tokens = @()) {
    $options = Parse-ReadOnlyCapabilityOptions $Tokens
    $configRaw = [System.IO.File]::ReadAllText($CfgPath) -replace '(?m)^\s*//.*$', ''
    $config = $configRaw | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace([string]$options.view) -and [string]$options.view -ne 'skill-surfaces') { throw ('Unknown capability inventory view: {0}' -f $options.view) }
    $view = New-SkillSurfaceView -RepoRoot $Root -Config $config -HostSnapshotPath ([string]$options.host_snapshot) -HostProbe:([bool]$options.host_probe)
    if (-not [string]::IsNullOrWhiteSpace([string]$options.out_path)) { $view.writes = 1 }
    $envelope = [pscustomobject][ordered]@{ schema_version = 1; command = 'capability-inventory'; view = 'skill-surfaces'; pass = [bool]$view.pass; truth_boundary = 'read_only_skill_surface_snapshot'; data = $view }
    $json = $envelope | ConvertTo-Json -Depth 40 -Compress
    if (-not [string]::IsNullOrWhiteSpace([string]$options.out_path)) {
        $outPath = [System.IO.Path]::GetFullPath([string]$options.out_path)
        $protectedInputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $protectedInputs.Add([System.IO.Path]::GetFullPath($CfgPath)) | Out-Null
        if (-not [string]::IsNullOrWhiteSpace([string]$options.host_snapshot)) {
            $protectedInputs.Add([System.IO.Path]::GetFullPath([string]$options.host_snapshot)) | Out-Null
        }
        foreach ($surface in @($view.surfaces)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$surface.source) -and (Test-Path -LiteralPath ([string]$surface.source) -PathType Leaf)) {
                $protectedInputs.Add([System.IO.Path]::GetFullPath([string]$surface.source)) | Out-Null
            }
            foreach ($item in @($surface.items)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$item.path) -and (Test-Path -LiteralPath ([string]$item.path) -PathType Leaf)) {
                    $protectedInputs.Add([System.IO.Path]::GetFullPath([string]$item.path)) | Out-Null
                }
            }
        }
        if ($protectedInputs.Contains($outPath)) { throw '--out cannot overwrite a capability inventory input.' }
        Write-Utf8FileAtomic -Path $outPath -Content $json
    }
    return [pscustomobject]@{ exit_code = $(if ($envelope.pass) { 0 } else { 1 }); output = $(if ($options.json) { $json } else { 'Skill surfaces: surfaces={0}, findings={1}' -f $view.surface_count, @($view.findings).Count }); json = [bool]$options.json; envelope = $envelope }
}
