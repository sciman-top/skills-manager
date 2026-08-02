function New-PluginContractFinding([string]$Code, [string]$Path, [string]$Message) {
    return New-OperationFinding $Code 'error' $Path $Message
}

function Test-PluginPathWithin([string]$Path, [string]$Boundary) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Boundary)) { return $false }
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = [System.IO.Path]::GetFullPath($Boundary).TrimEnd('\', '/')
    return $full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith(($root + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PluginRelativeComponentPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not $Path.StartsWith('./', [System.StringComparison]::Ordinal)) { return $false }
    $normalized = $Path.Replace('\', '/').Substring(2)
    if ([string]::IsNullOrWhiteSpace($normalized) -or [System.IO.Path]::IsPathRooted($normalized)) { return $false }
    return (@($normalized.Split('/') | Where-Object { $_ -eq '..' }).Count -eq 0)
}

function Test-PluginReparsePoint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-PluginTreeContainsReparsePoint([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $false }
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push([System.IO.Path]::GetFullPath($Root))
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
    return $false
}

function Test-PluginExistingAncestorReparsePoint([string]$Path, [string]$Boundary) {
    $root = [System.IO.Path]::GetFullPath($Boundary).TrimEnd('\', '/')
    $current = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $current)) { $current = Split-Path $current -Parent }
    while (-not [string]::IsNullOrWhiteSpace($current) -and (Test-PluginPathWithin $current $root)) {
        if ((Test-Path -LiteralPath $current) -and (Test-PluginReparsePoint $current)) { return $true }
        if ($current.TrimEnd('\', '/').Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = Split-Path $current -Parent
        if ([string]::Equals($parent, $current, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $current = $parent
    }
    return $false
}

function Get-PluginSensitivePropertyFindings($Value, [string]$Path = '$') {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) {
            $name = [string]$key
            $childPath = '{0}.{1}' -f $Path, $name
            if ($name -match '(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|bearer)') {
                $findings.Add((New-PluginContractFinding 'sensitive_property_forbidden' $childPath 'Plugin metadata must reference credentials, not contain sensitive properties.')) | Out-Null
            }
            foreach ($finding in @(Get-PluginSensitivePropertyFindings $Value[$key] $childPath)) { $findings.Add($finding) | Out-Null }
        }
    }
    elseif ($Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            $name = [string]$property.Name
            $childPath = '{0}.{1}' -f $Path, $name
            if ($name -match '(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|bearer)') {
                $findings.Add((New-PluginContractFinding 'sensitive_property_forbidden' $childPath 'Plugin metadata must reference credentials, not contain sensitive properties.')) | Out-Null
            }
            foreach ($finding in @(Get-PluginSensitivePropertyFindings $property.Value $childPath)) { $findings.Add($finding) | Out-Null }
        }
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $index = 0
        foreach ($item in $Value) {
            foreach ($finding in @(Get-PluginSensitivePropertyFindings $item ('{0}[{1}]' -f $Path, $index))) { $findings.Add($finding) | Out-Null }
            $index++
        }
    }
    return $findings.ToArray()
}

function Get-PluginShape($Manifest) {
    $hasSkills = -not [string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Manifest 'skills'))
    $hasMcp = -not [string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Manifest 'mcpServers'))
    $hasApp = -not [string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Manifest 'apps'))
    if ($hasSkills -and ($hasMcp -or $hasApp)) { return $(if ($hasApp) { 'skill_mcp_ui' } else { 'skill_mcp' }) }
    if ($hasSkills) { return 'skills_only' }
    if ($hasMcp -or $hasApp) { return $(if ($hasApp) { 'mcp_ui' } else { 'mcp_only' }) }
    return 'invalid'
}

function Test-PluginManifestContract {
    param($Manifest, [string]$PluginRoot, [bool]$RequireDistributionMetadata = $true)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Manifest) {
        $findings.Add((New-PluginContractFinding 'manifest_missing' '$' 'Plugin manifest is required.')) | Out-Null
        return [pscustomobject][ordered]@{ pass = $false; shape = 'invalid'; findings = $findings.ToArray(); provider_calls = 0; native_mutations = 0; writes = 0 }
    }
    $name = [string](Get-OperationObjectProperty $Manifest 'name')
    $version = [string](Get-OperationObjectProperty $Manifest 'version')
    $description = [string](Get-OperationObjectProperty $Manifest 'description')
    if ($name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $findings.Add((New-PluginContractFinding 'plugin_name_invalid' '$.name' 'Plugin name must use stable kebab-case.')) | Out-Null }
    if ($version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') { $findings.Add((New-PluginContractFinding 'plugin_version_invalid' '$.version' 'Plugin version must be SemVer.')) | Out-Null }
    if ([string]::IsNullOrWhiteSpace($description) -or $description.Length -gt 1024) { $findings.Add((New-PluginContractFinding 'plugin_description_invalid' '$.description' 'Plugin description is required and must be at most 1024 characters.')) | Out-Null }

    if ($RequireDistributionMetadata) {
        $repository = [string](Get-OperationObjectProperty $Manifest 'repository')
        $license = [string](Get-OperationObjectProperty $Manifest 'license')
        $parsedUri = $null
        if (-not [System.Uri]::TryCreate($repository, [System.UriKind]::Absolute, [ref]$parsedUri) -or $parsedUri.Scheme -notin @('https', 'http')) {
            $findings.Add((New-PluginContractFinding 'plugin_repository_invalid' '$.repository' 'Distribution metadata requires an absolute HTTP(S) repository source.')) | Out-Null
        }
        if ($license -notmatch '^[A-Za-z0-9][A-Za-z0-9.+-]*(?:\s+(?:AND|OR)\s+[A-Za-z0-9][A-Za-z0-9.+-]*)*$') {
            $findings.Add((New-PluginContractFinding 'plugin_license_invalid' '$.license' 'Distribution metadata requires an SPDX-like or LicenseRef license expression.')) | Out-Null
        }
    }

    $shape = Get-PluginShape $Manifest
    if ($shape -eq 'invalid') { $findings.Add((New-PluginContractFinding 'plugin_components_missing' '$' 'Plugin must declare skills, apps, or mcpServers.')) | Out-Null }
    foreach ($field in @('skills', 'apps', 'mcpServers', 'hooks')) {
        $value = [string](Get-OperationObjectProperty $Manifest $field)
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if (-not (Test-PluginRelativeComponentPath $value)) {
            $findings.Add((New-PluginContractFinding 'plugin_component_path_invalid' ('$.{0}' -f $field) 'Component paths must start with ./ and remain relative without parent traversal.')) | Out-Null
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($PluginRoot)) {
            $candidate = [System.IO.Path]::GetFullPath((Join-Path $PluginRoot $value.Substring(2)))
            if (-not (Test-PluginPathWithin $candidate $PluginRoot)) {
                $findings.Add((New-PluginContractFinding 'plugin_component_outside_root' ('$.{0}' -f $field) 'Component path escapes the plugin root.')) | Out-Null
            }
            elseif (-not (Test-Path -LiteralPath $candidate)) {
                $findings.Add((New-PluginContractFinding 'plugin_component_missing' ('$.{0}' -f $field) 'Declared component path does not exist.')) | Out-Null
            }
            elseif (Test-PluginReparsePoint $candidate) {
                $findings.Add((New-PluginContractFinding 'plugin_component_reparse_forbidden' ('$.{0}' -f $field) 'Reparse-point components are not supported.')) | Out-Null
            }
            elseif ($field -eq 'skills') {
                if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                    $findings.Add((New-PluginContractFinding 'plugin_skills_not_directory' '$.skills' 'skills must resolve to a directory.')) | Out-Null
                }
                else {
                    if (Test-PluginTreeContainsReparsePoint $candidate) { $findings.Add((New-PluginContractFinding 'plugin_tree_reparse_forbidden' '$.skills' 'Reparse points are not supported anywhere in the skills tree.')) | Out-Null }
                    $skillDirs = @(Get-ChildItem -LiteralPath $candidate -Directory -Force -ErrorAction SilentlyContinue)
                    if ($skillDirs.Count -eq 0) { $findings.Add((New-PluginContractFinding 'plugin_skills_empty' '$.skills' 'skills directory must contain at least one direct skill directory.')) | Out-Null }
                    foreach ($skillDir in $skillDirs) {
                        if (Test-PluginReparsePoint $skillDir.FullName) { $findings.Add((New-PluginContractFinding 'plugin_skill_reparse_forbidden' '$.skills' ('Skill directory is a reparse point: {0}' -f $skillDir.Name))) | Out-Null; continue }
                        if (-not (Test-Path -LiteralPath (Join-Path $skillDir.FullName 'SKILL.md') -PathType Leaf)) { $findings.Add((New-PluginContractFinding 'plugin_skill_manifest_missing' '$.skills' ('Skill {0} is missing SKILL.md.' -f $skillDir.Name))) | Out-Null }
                    }
                }
            }
        }
    }
    foreach ($finding in @(Get-PluginSensitivePropertyFindings $Manifest)) { $findings.Add($finding) | Out-Null }
    return [pscustomobject][ordered]@{
        pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0)
        shape = $shape
        findings = $findings.ToArray()
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}
