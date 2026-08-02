function New-RulePatchGuardFinding([string]$Code, [string]$Path, [string]$Message) {
    return [pscustomobject]@{ code = $Code; severity = 'error'; path = $Path; message = $Message }
}

function Test-RulePatchReparsePath([string]$Path, [string]$BoundaryRoot) {
    $cursor = [System.IO.Path]::GetFullPath($Path)
    $boundary = [System.IO.Path]::GetFullPath($BoundaryRoot).TrimEnd('\', '/')
    while ($true) {
        if ([System.IO.File]::Exists($cursor) -or [System.IO.Directory]::Exists($cursor)) {
            $attributes = [System.IO.File]::GetAttributes($cursor)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        }
        if ($cursor.TrimEnd('\', '/').Equals($boundary, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [System.IO.Directory]::GetParent($cursor)
        if ($null -eq $parent -or -not (Test-RuleDiscoveryPathWithin $parent.FullName $boundary)) { break }
        $cursor = $parent.FullName
    }
    return $false
}

function Test-RulePatchApplyGuard {
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)][string]$FixtureRoot, [Parameter(Mandatory = $true)][string]$Token)
    $findings = New-Object System.Collections.Generic.List[object]
    $contract = Test-RulePatchPlanContract $Plan
    foreach ($finding in @($contract.findings)) { $findings.Add($finding) | Out-Null }
    $fixture = [System.IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\', '/')
    $target = Get-OperationObjectProperty $Plan 'target'; $path = [System.IO.Path]::GetFullPath([string](Get-OperationObjectProperty $target 'path'))
    $authorized = [System.IO.Path]::GetFullPath([string](Get-OperationObjectProperty $target 'authorized_root')).TrimEnd('\', '/')
    $root = [System.IO.Path]::GetPathRoot($fixture).TrimEnd('\', '/')
    if ($fixture.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { $findings.Add((New-RulePatchGuardFinding 'fixture_root_is_drive_root' '$.target.authorized_root' 'Drive roots are never valid fixture roots.')) | Out-Null }
    if (-not [System.IO.File]::Exists((Join-Path $fixture '.skills-manager-fixture'))) { $findings.Add((New-RulePatchGuardFinding 'fixture_marker_missing' '$.target.authorized_root' 'Fixture executor requires a .skills-manager-fixture marker.')) | Out-Null }
    if (-not (Test-RuleDiscoveryPathWithin $authorized $fixture) -or -not (Test-RuleDiscoveryPathWithin $path $authorized)) { $findings.Add((New-RulePatchGuardFinding 'target_out_of_fixture_root' '$.target.path' 'Target and authorized root must remain inside the explicit fixture root.')) | Out-Null }
    if (Test-RulePatchReparsePath $path $fixture) { $findings.Add((New-RulePatchGuardFinding 'reparse_path_forbidden' '$.target.path' 'Reparse points are not accepted by the fixture executor.')) | Out-Null }
    $requiredToken = [string](Get-OperationObjectProperty (Get-OperationObjectProperty $Plan 'apply') 'required_token')
    if ([string]::IsNullOrWhiteSpace($requiredToken) -or $Token -cne $requiredToken) { $findings.Add((New-RulePatchGuardFinding 'apply_token_invalid' '$.apply.required_token' 'Explicit apply token does not match.')) | Out-Null }
    if (-not [System.IO.File]::Exists($path)) { $findings.Add((New-RulePatchGuardFinding 'target_missing' '$.target.path' 'Fixture target must already exist.')) | Out-Null }
    else {
        $current = [System.IO.File]::ReadAllText($path); $currentHash = Get-RulePatchTextHash $current
        if ($currentHash -ne [string](Get-OperationObjectProperty $target 'before_hash')) { $findings.Add((New-RulePatchGuardFinding 'target_hash_stale' '$.target.before_hash' 'Target content changed after planning.')) | Out-Null }
    }
    $desiredText = [string](Get-OperationObjectProperty $Plan 'desired_text')
    if ((Get-RulePatchTextHash $desiredText) -ne [string](Get-OperationObjectProperty $target 'desired_hash')) { $findings.Add((New-RulePatchGuardFinding 'desired_hash_mismatch' '$.target.desired_hash' 'Desired text does not match its declared hash.')) | Out-Null }
    return [pscustomobject][ordered]@{ pass = ($findings.Count -eq 0); findings = @($findings.ToArray()); target_path = $path; fixture_root = $fixture; writes = 0 }
}
