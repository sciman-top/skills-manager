function New-RuleRepoTruthIndex {
    param([Parameter(Mandatory = $true)][string]$RepoRoot, $RepoScan = $null)
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $commands = @()
    if ($null -ne $RepoScan) {
        $detected = Get-OperationObjectProperty $RepoScan 'detected'
        $commands = @((Get-OperationObjectProperty $detected 'build_commands')) + @((Get-OperationObjectProperty $detected 'test_commands'))
    }
    return [pscustomobject][ordered]@{ schema_version = 1; repo_root = $root; commands = @($commands | ForEach-Object { [string]$_ } | Sort-Object -Unique); source = $(if ($null -eq $RepoScan) { 'filesystem_only' } else { 'target_audit_repo_scan' }); scanned_at = Get-OperationObjectProperty $RepoScan 'scanned_at' }
}

function Test-RuleRepoReferences {
    param([Parameter(Mandatory = $true)]$TruthIndex, [object[]]$References = @())
    $root = [string]$TruthIndex.repo_root
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($reference in @($References)) {
        $kind = [string](Get-OperationObjectProperty $reference 'kind'); $value = [string](Get-OperationObjectProperty $reference 'value'); $sourceType = [string](Get-OperationObjectProperty $reference 'source_type')
        $state = 'unknown'; $evidence = @()
        if ($sourceType -eq 'recommendation') { $state = 'not_checked'; $evidence = @([pscustomobject]@{ reason = 'recommendation_not_evidence' }) }
        elseif ($kind -eq 'path') {
            $candidate = if ([System.IO.Path]::IsPathRooted($value)) { [System.IO.Path]::GetFullPath($value) } else { [System.IO.Path]::GetFullPath((Join-Path $root $value)) }
            if (-not (Test-RuleDiscoveryPathWithin $candidate $root)) { $state = 'out_of_root' }
            elseif ([System.IO.File]::Exists($candidate) -or [System.IO.Directory]::Exists($candidate)) { $state = 'verified'; $evidence = @([pscustomobject]@{ type = 'filesystem'; path = $candidate }) }
            else { $state = 'absent'; $evidence = @([pscustomobject]@{ type = 'filesystem'; path = $candidate }) }
        }
        elseif ($kind -eq 'command') {
            if (@($TruthIndex.commands | Where-Object { [string]::Equals($_.Trim(), $value.Trim(), [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { $state = 'verified'; $evidence = @([pscustomobject]@{ type = $TruthIndex.source; command = $value }) }
            else {
                $entrypoint = $null
                $fileMatch = [regex]::Match($value, '(?i)(?:^|\s)-File\s+(?:"([^"]+)"|([^\s]+))')
                $scriptMatch = [regex]::Match($value, '^(?i)(?:python|py|node)\s+(?:"([^"]+)"|([^\s]+))')
                if ($fileMatch.Success) { $entrypoint = $(if ($fileMatch.Groups[1].Success) { $fileMatch.Groups[1].Value } else { $fileMatch.Groups[2].Value }) }
                elseif ($scriptMatch.Success) { $entrypoint = $(if ($scriptMatch.Groups[1].Success) { $scriptMatch.Groups[1].Value } else { $scriptMatch.Groups[2].Value }) }
                if (-not [string]::IsNullOrWhiteSpace($entrypoint)) {
                    $candidate = if ([System.IO.Path]::IsPathRooted($entrypoint)) { [System.IO.Path]::GetFullPath($entrypoint) } else { [System.IO.Path]::GetFullPath((Join-Path $root $entrypoint)) }
                    if ((Test-RuleDiscoveryPathWithin $candidate $root) -and [System.IO.File]::Exists($candidate)) {
                        $state = 'verified'; $evidence = @([pscustomobject]@{ type = 'filesystem_entrypoint'; path = $candidate; command = $value })
                    }
                    else { $state = 'not_observed'; $evidence = @([pscustomobject]@{ type = $TruthIndex.source; command = $value }) }
                }
                else { $state = 'not_observed'; $evidence = @([pscustomobject]@{ type = $TruthIndex.source; command = $value }) }
            }
        }
        $results.Add([pscustomobject][ordered]@{ kind = $kind; value = $value; state = $state; evidence = $evidence; executed = $false }) | Out-Null
    }
    return [pscustomobject][ordered]@{ schema_version = 1; references = @($results.ToArray()); commands_executed = 0; writes = 0; recommendations_used_as_evidence = 0 }
}

function Get-RuleAuditResponsibilityConstraints {
    param([object[]]$Documents = @())
    $constraints = [ordered]@{}
    foreach ($document in @($Documents)) {
        $path = [string](Get-OperationObjectProperty $document 'path')
        if (-not [System.IO.File]::Exists($path)) { continue }
        $inMapping = $false
        $lines = [System.IO.File]::ReadAllLines($path)
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            if ($line -match '^#{1,6}\s+(.+?)\s*$') {
                $heading = [string]$Matches[1]
                $inMapping = ($heading -match '(?i)Global\s+Rule\s*[-=]+>\s*Repo\s+Action|Repo\s+Action|规则.+项目')
                continue
            }
            if (-not $inMapping -or $line -notmatch '^\s*-\s+(?:`(?<id>[^`]+)`|(?<id>[^:：]+?))\s*[:：]\s*(?<action>.+?)\s*$') { continue }
            $id = ([string]$Matches['id']).Trim()
            $action = ([string]$Matches['action']).Trim()
            if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($action)) { continue }
            if (-not $constraints.Contains($id)) {
                $constraints[$id] = [pscustomobject][ordered]@{
                    constraint_id = $id; common_intent = $action; platform_deltas = @(); project_actions = @($action)
                    enforcement_refs = @(); evidence = @([pscustomobject]@{ type = 'rule_mapping'; path = $path; line = $index + 1 })
                    need_kind = 'project_guidance'
                }
            }
            else {
                $constraints[$id].project_actions = @($constraints[$id].project_actions) + @($action)
                $constraints[$id].evidence = @($constraints[$id].evidence) + @([pscustomobject]@{ type = 'rule_mapping'; path = $path; line = $index + 1 })
            }
        }
    }
    return @($constraints.Values)
}

function Get-RuleAuditReferences {
    param([object[]]$Documents = @())
    $references = [ordered]@{}
    foreach ($document in @($Documents)) {
        $path = [string](Get-OperationObjectProperty $document 'path')
        if (-not [System.IO.File]::Exists($path)) { continue }
        $text = [System.IO.File]::ReadAllText($path)
        foreach ($match in @([regex]::Matches($text, '`([^`\r\n]+)`'))) {
            $value = ([string]$match.Groups[1].Value).Trim()
            $kind = $null
            if ($value -match '^(?i)(pwsh|powershell|python|py|node|npm|npx|dotnet|git)\s+') { $kind = 'command' }
            else {
                $rooted = [System.IO.Path]::IsPathRooted($value)
                $boundedToken = ($value -notmatch '\s' -and $value -notmatch '[*?<>|]')
                $pathShape = ($value -match '^[.][\\/]' -or $value -match '[\\/]$' -or $value -match '(?i)\.(ps1|py|json|ya?ml|md|toml|xml|csproj|sln)$')
                if ($rooted -or ($boundedToken -and $pathShape)) { $kind = 'path' }
            }
            if ($null -eq $kind) { continue }
            $key = '{0}|{1}' -f $kind, $value.ToLowerInvariant()
            if (-not $references.Contains($key)) { $references[$key] = [pscustomobject]@{ kind = $kind; value = $value; source_type = 'rule' } }
        }
    }
    return @($references.Values)
}
