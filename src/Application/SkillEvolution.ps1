$script:SkillEvolutionRepoRoot = if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\skills.json'))) {
    (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
elseif ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json'))) {
    (Resolve-Path -LiteralPath $PSScriptRoot).Path
}
else { (Get-Location).Path }

if (-not (Get-Command Get-OperationSha256 -ErrorAction SilentlyContinue)) {
    . (Join-Path $script:SkillEvolutionRepoRoot 'src\Domain\OperationPlan.ps1')
}
if (-not (Get-Command New-OperationReceipt -ErrorAction SilentlyContinue)) {
    . (Join-Path $script:SkillEvolutionRepoRoot 'src\Domain\Receipt.ps1')
}

$script:SkillEvolutionAllowedSignalTypes = @('missed_trigger', 'wrong_trigger', 'execution_failure', 'repeated_manual_work', 'obsolete_overlap', 'no_change')
$script:SkillEvolutionAllowedReasoningEfforts = @('low', 'medium', 'high', 'xhigh')
$script:SkillEvolutionAllowedReferenceExtensions = @('.md', '.txt', '.json', '.yaml', '.yml', '.csv', '.tsv')
$script:SkillEvolutionForbiddenContentPattern = '(?im)(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|\bcurl(?:\.exe)?\b|\bwget(?:\.exe)?\b|\bMCP\b|\.codex-plugin|plugin\.json|\bhooks?[/\\]|^\s*dependencies\s*:|scheduled\s+task|Register-ScheduledTask|New-Service|Set-ExecutionPolicy|chmod\s+\+x|\bnetwork\s+(?:access|request|call))'
$script:SkillEvolutionForbiddenSignalFields = @('raw_prompt', 'credentials', 'business_data', 'full_session_transcript')
$script:SkillEvolutionMinDescriptionCharacters = 24
$script:SkillEvolutionMaxDescriptionCharacters = 384

function Get-SkillEvolutionProperty($Object, [string]$Name) {
    return Get-OperationObjectProperty $Object $Name
}

function Resolve-SkillEvolutionPath([string]$Path, [string]$BaseRoot) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $candidate = $Path.Trim()
    if (-not [System.IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $BaseRoot $candidate }
    return [System.IO.Path]::GetFullPath($candidate)
}

function ConvertTo-SkillEvolutionRelativePath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [System.IO.Path]::IsPathRooted($RelativePath)) { return $null }
    $anchor = Join-Path ([System.IO.Path]::GetTempPath()) 'skill-evolution-relative-anchor'
    try {
        $fullAnchor = [System.IO.Path]::GetFullPath($anchor)
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $fullAnchor $RelativePath))
        if (-not (Test-OperationPathWithinRoot $fullPath $fullAnchor) -or $fullPath -eq $fullAnchor) { return $null }
        return [System.IO.Path]::GetRelativePath($fullAnchor, $fullPath).Replace('/', '\')
    }
    catch { return $null }
}

function Test-SkillEvolutionPathWithin([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    try { return Test-OperationPathWithinRoot ([System.IO.Path]::GetFullPath($Path)) ([System.IO.Path]::GetFullPath($Root)) }
    catch { return $false }
}

function Assert-SkillEvolutionReportPath([string]$Path, [string]$RepoRoot, [switch]$AllowCandidateRoot) {
    $full = [System.IO.Path]::GetFullPath($Path)
    $reportsRoot = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'reports\skill-evolution'
    if (-not (Test-SkillEvolutionPathWithin $full $reportsRoot)) {
        throw ('SkillEvolution report path must stay under {0}: {1}' -f $reportsRoot, $full)
    }
    return $full
}

function Get-SkillEvolutionFileHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $stream = [System.IO.File]::OpenRead($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-SkillEvolutionJsonHash($Object) {
    return Get-OperationSha256 ($Object | ConvertTo-Json -Depth 80 -Compress)
}

function Write-SkillEvolutionJsonAtomic([string]$Path, $Value) {
    $json = $Value | ConvertTo-Json -Depth 80
    if (Get-Command Write-Utf8FileAtomic -ErrorAction SilentlyContinue) {
        Write-Utf8FileAtomic -Path $Path -Content $json
        return
    }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
    $temp = '{0}.tmp-{1}' -f $Path, ([guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($temp, $Path, $true)
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Test-SkillEvolutionAllowedRelativePath([string]$RelativePath) {
    $relative = ConvertTo-SkillEvolutionRelativePath $RelativePath
    if ([string]::IsNullOrWhiteSpace($relative)) { return $false }
    if ($relative -ieq 'SKILL.md' -or $relative -ieq 'agents\openai.yaml') { return $true }
    if (-not $relative.StartsWith('references\', [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    return ([System.IO.Path]::GetExtension($relative).ToLowerInvariant() -in $script:SkillEvolutionAllowedReferenceExtensions)
}

function Read-SkillEvolutionMetadata([string]$SkillPath) {
    if (-not (Test-Path -LiteralPath $SkillPath -PathType Leaf)) { return [pscustomobject]@{ valid = $false; name = $null; description = $null; text = '' } }
    $text = [System.IO.File]::ReadAllText($SkillPath)
    $frontmatter = [regex]::Match($text, '(?s)\A---\s*\r?\n(?<yaml>.*?)\r?\n---')
    if (-not $frontmatter.Success) { return [pscustomobject]@{ valid = $false; name = $null; description = $null; text = $text } }
    $yaml = $frontmatter.Groups['yaml'].Value
    $nameMatch = [regex]::Match($yaml, '(?m)^name:\s*["'']?(?<value>[^\r\n"'']+)')
    $descriptionMatch = [regex]::Match($yaml, '(?m)^description:\s*["'']?(?<value>[^\r\n]+)')
    return [pscustomobject]@{
        valid = ($nameMatch.Success -and $descriptionMatch.Success)
        name = if ($nameMatch.Success) { $nameMatch.Groups['value'].Value.Trim() } else { $null }
        description = if ($descriptionMatch.Success) { $descriptionMatch.Groups['value'].Value.Trim().Trim('"', "'") } else { $null }
        text = $text
    }
}

function Get-SkillEvolutionPackageState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$CandidateDirectory)

    $root = [System.IO.Path]::GetFullPath($CandidateDirectory)
    $findings = [System.Collections.Generic.List[object]]::new()
    $files = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $findings.Add((New-OperationFinding 'candidate_directory_missing' 'error' '$.candidate' 'Candidate directory does not exist.')) | Out-Null
        return [pscustomobject]@{ root = $root; pass = $false; fingerprint = $null; files = @(); findings = $findings.ToArray() }
    }
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        $findings.Add((New-OperationFinding 'candidate_reparse_root' 'error' '$.candidate' 'Candidate root cannot be a junction or symbolic link.')) | Out-Null
    }

    foreach ($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction Stop)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $findings.Add((New-OperationFinding 'candidate_reparse_entry' 'error' $item.FullName 'Candidate package cannot contain junctions or symbolic links.')) | Out-Null
            continue
        }
        if ($item.PSIsContainer) { continue }
        $relative = ConvertTo-SkillEvolutionRelativePath ([System.IO.Path]::GetRelativePath($root, $item.FullName))
        if ([string]::IsNullOrWhiteSpace($relative)) {
            $findings.Add((New-OperationFinding 'candidate_path_escape' 'error' $item.FullName 'Candidate entry does not resolve to a contained relative path.')) | Out-Null
            continue
        }
        if ($relative -in @('candidate.json', 'evaluation.json') -or $relative -like 'evaluation-*.json') { continue }
        if (-not (Test-SkillEvolutionAllowedRelativePath $relative)) {
            $findings.Add((New-OperationFinding 'candidate_path_forbidden' 'error' $relative 'MVP candidates may contain only SKILL.md, agents/openai.yaml, and non-executable references.')) | Out-Null
            continue
        }
        $text = [System.IO.File]::ReadAllText($item.FullName)
        if ($text -match $script:SkillEvolutionForbiddenContentPattern) {
            $findings.Add((New-OperationFinding 'candidate_behavior_deferred' 'error' $relative 'Executable, hook, MCP, plugin, permission, network, or system-maintenance behavior requires separate admission.')) | Out-Null
        }
        $files.Add([pscustomobject][ordered]@{ path = $relative; hash = Get-SkillEvolutionFileHash $item.FullName; bytes = [int64]$item.Length }) | Out-Null
    }
    $skillPath = Join-Path $root 'SKILL.md'
    $metadata = Read-SkillEvolutionMetadata $skillPath
    if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
        $findings.Add((New-OperationFinding 'skill_entrypoint_missing' 'error' 'SKILL.md' 'Candidate must contain SKILL.md.')) | Out-Null
    }
    else {
        $skillText = [string]$metadata.text
        if (-not [bool]$metadata.valid) {
            $findings.Add((New-OperationFinding 'skill_metadata_invalid' 'error' 'SKILL.md' 'Candidate SKILL.md requires YAML frontmatter with name and description.')) | Out-Null
        }
        elseif ([string]$metadata.name -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') {
            $findings.Add((New-OperationFinding 'skill_name_invalid' 'error' 'SKILL.md' 'Candidate skill name must use lowercase kebab-case and be at most 64 characters.')) | Out-Null
        }
        $descriptionLength = ([string]$metadata.description).Length
        if ($descriptionLength -lt $script:SkillEvolutionMinDescriptionCharacters -or $descriptionLength -gt $script:SkillEvolutionMaxDescriptionCharacters) {
            $findings.Add((New-OperationFinding 'skill_description_budget_invalid' 'error' 'SKILL.md' ('Candidate description must be {0}-{1} characters.' -f $script:SkillEvolutionMinDescriptionCharacters, $script:SkillEvolutionMaxDescriptionCharacters))) | Out-Null
        }
        if ($skillText.Length -gt 20000) {
            $findings.Add((New-OperationFinding 'skill_metadata_budget_exceeded' 'error' 'SKILL.md' 'Candidate SKILL.md exceeds the 20000 character MVP budget.')) | Out-Null
        }
    }
    $orderedFiles = @($files.ToArray() | Sort-Object path)
    $canonical = @($orderedFiles | ForEach-Object { '{0}|{1}|{2}' -f $_.path.ToLowerInvariant(), $_.hash, $_.bytes }) -join "`n"
    return [pscustomobject][ordered]@{
        root = $root
        pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0)
        fingerprint = Get-OperationSha256 $canonical
        files = $orderedFiles
        metadata = [pscustomobject]@{ name = [string]$metadata.name; description = [string]$metadata.description; description_hash = Get-OperationSha256 ([string]$metadata.description) }
        findings = @($findings.ToArray())
    }
}

function Get-SkillEvolutionCatalogFingerprint([string]$RepoRoot) {
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in @('skills.json', 'skills.lock.json')) {
        $path = Join-Path $root $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) { $entries.Add(('{0}|{1}' -f $relative, (Get-SkillEvolutionFileHash $path))) | Out-Null }
    }
    foreach ($catalogRootName in @('overrides', 'imports', 'vendor', 'agent')) {
        $catalogRoot = Join-Path $root $catalogRootName
        if (-not (Test-Path -LiteralPath $catalogRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $catalogRoot -Recurse -File -Filter 'SKILL.md' -Force -ErrorAction Stop | Sort-Object FullName)) {
            if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace('/', '\')
            $entries.Add(('{0}|{1}' -f $relative.ToLowerInvariant(), (Get-SkillEvolutionFileHash $file.FullName))) | Out-Null
        }
    }
    return Get-OperationSha256 ($entries.ToArray() -join "`n")
}

function Get-SkillEvolutionCatalogMetadata([string]$RepoRoot) {
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    $items = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($catalogRootName in @('overrides', 'agent')) {
        $catalogRoot = Join-Path $root $catalogRootName
        if (-not (Test-Path -LiteralPath $catalogRoot -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $catalogRoot -Recurse -File -Filter 'SKILL.md' -Force -ErrorAction Stop)) {
            if (-not $seenPaths.Add($file.FullName)) { continue }
            $metadata = Read-SkillEvolutionMetadata $file.FullName
            if (-not $metadata.valid) { continue }
            $items.Add([pscustomobject]@{ name = [string]$metadata.name; description = [string]$metadata.description; description_hash = Get-OperationSha256 ([string]$metadata.description); path = $file.FullName }) | Out-Null
        }
    }
    return $items.ToArray()
}

function Test-SkillEvolutionCatalogConflicts($CandidateState, $Manifest, [string]$RepoRoot) {
    $findings = [System.Collections.Generic.List[object]]::new()
    $skillName = [string]$Manifest.skill_name
    if ([string]$CandidateState.metadata.name -ne $skillName) {
        $findings.Add((New-OperationFinding 'candidate_skill_name_mismatch' 'error' 'SKILL.md' 'Candidate frontmatter name does not match candidate.json.')) | Out-Null
    }
    $catalog = @(Get-SkillEvolutionCatalogMetadata $RepoRoot)
    if ([string]$Manifest.candidate_mode -ne 'existing' -and @($catalog | Where-Object { [string]$_.name -eq $skillName }).Count -gt 0) {
        $findings.Add((New-OperationFinding 'catalog_skill_name_conflict' 'error' '$.skill_name' 'A new candidate cannot duplicate an existing catalog skill name.')) | Out-Null
    }
    foreach ($entry in @($catalog | Where-Object { [string]$_.name -ne $skillName -and [string]$_.description_hash -eq [string]$CandidateState.metadata.description_hash })) {
        $findings.Add((New-OperationFinding 'catalog_trigger_description_conflict' 'error' 'SKILL.md' ('Candidate description exactly duplicates the trigger metadata for {0}.' -f $entry.name))) | Out-Null
    }
    return [pscustomobject]@{ pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0); findings = @($findings.ToArray()) }
}

function Get-SkillEvolutionTargetState([string]$RepoRoot, [string]$SkillName) {
    $target = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) ('overrides\custom\{0}' -f $SkillName)
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        return [pscustomobject]@{ path = $target; exists = $false; fingerprint = Get-OperationSha256 ''; files = @(); findings = @() }
    }
    $state = Get-SkillEvolutionPackageState $target
    if ([string]$state.metadata.name -ne $SkillName) {
        $state.findings = @($state.findings) + @((New-OperationFinding 'target_skill_name_mismatch' 'error' 'SKILL.md' 'Existing target frontmatter name does not match its lifecycle identity.'))
        $state.pass = $false
    }
    return [pscustomobject]@{ path = $target; exists = $true; fingerprint = $state.fingerprint; files = @($state.files); findings = @($state.findings); pass = $state.pass }
}

function Test-SkillEvolutionAdmission {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Pilot, [Parameter(Mandatory = $true)][string[]]$SignalIds, [string]$SkillName)

    $findings = [System.Collections.Generic.List[object]]::new()
    $selected = [System.Collections.Generic.List[object]]::new()
    $ids = @($SignalIds | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    foreach ($id in $ids) {
        $matches = @($Pilot.samples | Where-Object { [string]$_.sample_id -eq $id })
        if ($matches.Count -ne 1) { $findings.Add((New-OperationFinding 'signal_not_found' 'error' $id 'Each signal ID must resolve to exactly one pilot sample.')) | Out-Null; continue }
        $sample = $matches[0]
        if ((Get-SkillEvolutionProperty $sample 'countable') -ne $true -or (Get-SkillEvolutionProperty $sample 'synthetic') -eq $true -or (Get-SkillEvolutionProperty $sample 'self_referential') -eq $true) {
            $findings.Add((New-OperationFinding 'signal_not_real_task' 'error' $id 'Synthetic, self-referential, or non-countable samples cannot admit a candidate.')) | Out-Null
            continue
        }
        $signal = Get-SkillEvolutionProperty $sample 'skill_signal'
        if ($null -eq $signal) { $findings.Add((New-OperationFinding 'skill_signal_missing' 'error' $id 'Selected sample has no skill_signal v1.')) | Out-Null; continue }
        foreach ($forbiddenField in $script:SkillEvolutionForbiddenSignalFields) {
            if ((Test-OperationObjectProperty $sample $forbiddenField) -or (Test-OperationObjectProperty $signal $forbiddenField)) {
                $findings.Add((New-OperationFinding 'signal_sensitive_field_forbidden' 'error' $id ('Skill signal contains forbidden field: {0}.' -f $forbiddenField))) | Out-Null
            }
        }
        $selected.Add([pscustomobject]@{ sample = $sample; signal = $signal }) | Out-Null
    }
    $actionable = @($selected | Where-Object { [string]$_.signal.signal_type -ne 'no_change' })
    $signatures = @($actionable | ForEach-Object { [string]$_.signal.issue_signature } | Where-Object { $_ } | Sort-Object -Unique)
    $tasks = @($actionable | ForEach-Object { [string]$_.sample.task_id } | Where-Object { $_ } | Sort-Object -Unique)
    if ($actionable.Count -lt 2 -or $tasks.Count -lt 2 -or $signatures.Count -ne 1) {
        $findings.Add((New-OperationFinding 'independent_signal_threshold_not_met' 'error' '$.signals' 'Admission requires two independent real tasks with the same issue signature.')) | Out-Null
    }
    if (@($selected | Where-Object { $_.signal.negative_case -eq $true -or [string]$_.signal.control_case -in @('negative', 'no_skill') }).Count -lt 1) {
        $findings.Add((New-OperationFinding 'negative_case_missing' 'error' '$.signals' 'Admission requires at least one negative or no-skill case.')) | Out-Null
    }
    foreach ($entry in @($selected)) {
        $signal = $entry.signal
        if ([string]$signal.signal_type -notin $script:SkillEvolutionAllowedSignalTypes) { $findings.Add((New-OperationFinding 'signal_type_invalid' 'error' '$.signal_type' 'Signal type is not supported.')) | Out-Null }
        foreach ($field in @('surface', 'target_skill', 'issue_signature', 'evidence_link', 'baseline', 'native_equivalent', 'disposition')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-SkillEvolutionProperty $signal $field))) { $findings.Add((New-OperationFinding 'admission_field_missing' 'error' ('$.{0}' -f $field) 'Admission evidence is incomplete.')) | Out-Null }
        }
        if (-not [string]::IsNullOrWhiteSpace($SkillName) -and [string]$signal.target_skill -ne $SkillName) { $findings.Add((New-OperationFinding 'signal_target_mismatch' 'error' '$.target_skill' 'Selected signals must target the requested skill lifecycle identity.')) | Out-Null }
        if ([string]$signal.signal_type -ne 'no_change') {
            if (-not [string]::IsNullOrWhiteSpace([string]$signal.native_equivalent) -and [string]$signal.native_equivalent -notin @('none', 'not_available')) { $findings.Add((New-OperationFinding 'native_equivalent_present' 'error' '$.native_equivalent' 'Existing native coverage blocks candidate admission.')) | Out-Null }
            foreach ($field in @('consumer', 'net_benefit_metric', 'rollback_condition', 'retirement_condition')) {
                if ([string]::IsNullOrWhiteSpace([string](Get-SkillEvolutionProperty $signal $field))) { $findings.Add((New-OperationFinding 'admission_field_missing' 'error' ('$.{0}' -f $field) 'Admission evidence is incomplete.')) | Out-Null }
            }
            if ((Get-SkillEvolutionProperty $signal 'workflow_stable') -ne $true) { $findings.Add((New-OperationFinding 'workflow_not_stable' 'error' '$.workflow_stable' 'Workflow must be stable and repeatable.')) | Out-Null }
        }
    }
    return [pscustomobject][ordered]@{
        pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0)
        issue_signature = if ($signatures.Count -eq 1) { $signatures[0] } else { $null }
        signal_ids = $ids
        independent_task_count = $tasks.Count
        selected = @($selected.ToArray())
        actionable_signal_count = $actionable.Count
        findings = @($findings.ToArray())
    }
}

function Invoke-SkillEvolutionPrepare {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Pilot,
        [Parameter(Mandatory = $true)][string[]]$SignalIds,
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][ValidateSet('existing', 'new')][string]$CandidateMode,
        [Parameter(Mandatory = $true)][string]$OutRoot,
        [string]$RepoRoot = $script:SkillEvolutionRepoRoot
    )
    if ($SkillName -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Skill name must use lowercase kebab-case and be at most 64 characters.' }
    $admission = Test-SkillEvolutionAdmission -Pilot $Pilot -SignalIds $SignalIds -SkillName $SkillName
    if (-not $admission.pass) { return [pscustomobject]@{ schema_version = 1; command = 'skill-evolution-prepare'; pass = $false; status = 'admission_rejected'; admission = $admission; active_writes = 0; report_writes = 0; provider_calls = 0; host_writes = 0 } }

    $out = Assert-SkillEvolutionReportPath $OutRoot $RepoRoot
    $runId = 'se-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), (Get-OperationSha256 (($SignalIds -join '|') + $SkillName)).Substring(0, 8)
    $candidateDir = Join-Path $out ('{0}\candidate\{1}' -f $runId, $SkillName)
    [System.IO.Directory]::CreateDirectory($candidateDir) | Out-Null
    $baselinePath = $null
    if ($CandidateMode -eq 'existing') {
        foreach ($source in @((Join-Path $RepoRoot ('overrides\custom\{0}' -f $SkillName)), (Join-Path $RepoRoot ('agent\{0}' -f $SkillName)))) {
            if (Test-Path -LiteralPath $source -PathType Container) { $baselinePath = $source; break }
        }
        if ([string]::IsNullOrWhiteSpace($baselinePath)) { throw ('Existing skill not found: {0}' -f $SkillName) }
        foreach ($file in @(Get-ChildItem -LiteralPath $baselinePath -Recurse -File -Force)) {
            $relative = [System.IO.Path]::GetRelativePath($baselinePath, $file.FullName)
            if (-not (Test-SkillEvolutionAllowedRelativePath $relative)) { continue }
            $destination = Join-Path $candidateDir $relative
            [System.IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
            [System.IO.File]::Copy($file.FullName, $destination, $true)
        }
    }
    else {
        $template = "---`nname: $SkillName`ndescription: Candidate skill admitted from real-task signals; refine the trigger boundary before evaluation.`n---`n`n# $SkillName`n`nUse only for the admitted issue signature. Keep negative boundaries explicit.`n"
        [System.IO.File]::WriteAllText((Join-Path $candidateDir 'SKILL.md'), $template, [System.Text.UTF8Encoding]::new($false))
    }
    $state = Get-SkillEvolutionPackageState $candidateDir
    if ([string]$state.metadata.name -ne $SkillName) {
        $state.findings = @($state.findings) + @((New-OperationFinding 'candidate_skill_name_mismatch' 'error' 'SKILL.md' 'Prepared candidate frontmatter name does not match the requested skill.'))
        $state.pass = $false
    }
    $targetState = Get-SkillEvolutionTargetState $RepoRoot $SkillName
    $manifest = [pscustomobject][ordered]@{
        schema_version = 1
        candidate_id = $runId
        skill_name = $SkillName
        candidate_mode = $CandidateMode
        status = 'prepared'
        prepared_at = [datetimeoffset]::UtcNow.ToString('o')
        issue_signature = $admission.issue_signature
        signal_ids = @($admission.signal_ids)
        source_pilot_hash = Get-SkillEvolutionJsonHash $Pilot
        candidate_directory = $candidateDir
        baseline_path = $baselinePath
        baseline_fingerprint = $targetState.fingerprint
        initial_candidate_fingerprint = $state.fingerprint
        allowed_paths = @($state.files.path)
        creator_handoff = 'Use the host skill-creator skill inside this isolated candidate directory; do not write active sources or host roots.'
        active_writes = 0
        report_writes = 2
        provider_calls = 0
        host_writes = 0
    }
    Write-SkillEvolutionJsonAtomic (Join-Path $candidateDir 'candidate.json') $manifest
    $receiptPath = Join-Path (Split-Path -Parent (Split-Path -Parent $candidateDir)) 'prepare-receipt.json'
    Write-SkillEvolutionJsonAtomic $receiptPath ([pscustomobject]@{ schema_version = 1; command = 'skill-evolution-prepare'; pass = $state.pass; candidate = $manifest; admission = $admission; findings = @($state.findings); active_writes = 0; report_writes = 2; provider_calls = 0; host_writes = 0 })
    return [pscustomobject]@{ schema_version = 1; command = 'skill-evolution-prepare'; pass = $state.pass; status = 'prepared'; candidate_directory = $candidateDir; candidate_manifest = (Join-Path $candidateDir 'candidate.json'); receipt_path = $receiptPath; candidate_fingerprint = $state.fingerprint; admission = $admission; findings = @($state.findings); active_writes = 0; report_writes = 2; provider_calls = 0; host_writes = 0 }
}

function Invoke-SkillEvolutionEvaluate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CandidateDirectory,
        [Parameter(Mandatory = $true)]$Corpus,
        [object[]]$CaseResults = @(),
        [switch]$Execute,
        [string]$Model = 'gpt-5.6-sol',
        [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort = 'medium',
        [string]$RepoRoot = $script:SkillEvolutionRepoRoot
    )
    if (-not (Test-SkillEvolutionPathWithin $CandidateDirectory (Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'reports\skill-evolution'))) { throw 'Candidate directory must remain under reports/skill-evolution.' }
    $state = Get-SkillEvolutionPackageState $CandidateDirectory
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($finding in @($state.findings)) { $findings.Add($finding) | Out-Null }
    $manifestPath = Join-Path $state.root 'candidate.json'
    $manifest = if (Test-Path -LiteralPath $manifestPath) { [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json } else { $null }
    if ($null -eq $manifest) { $findings.Add((New-OperationFinding 'candidate_manifest_missing' 'error' 'candidate.json' 'Prepared candidate manifest is required.')) | Out-Null }
    $skillName = [string]$manifest.skill_name
    if ([int]$manifest.schema_version -ne 1 -or [string]::IsNullOrWhiteSpace($skillName) -or [string]$manifest.candidate_mode -notin @('existing', 'new')) {
        $findings.Add((New-OperationFinding 'candidate_manifest_invalid' 'error' 'candidate.json' 'Candidate manifest identity and mode are required.')) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$manifest.candidate_directory) -and [System.IO.Path]::GetFullPath([string]$manifest.candidate_directory) -ne $state.root) {
        $findings.Add((New-OperationFinding 'candidate_manifest_path_mismatch' 'error' 'candidate.json' 'Candidate manifest does not bind the evaluated directory.')) | Out-Null
    }
    $catalogConflicts = Test-SkillEvolutionCatalogConflicts $state $manifest $RepoRoot
    foreach ($finding in @($catalogConflicts.findings)) { $findings.Add($finding) | Out-Null }
    $cases = @($Corpus.cases)
    $positive = @($cases | Where-Object { [string]$_.kind -eq 'positive' })
    $negative = @($cases | Where-Object { [string]$_.kind -in @('negative', 'no_skill') })
    $baselineControls = @($cases | Where-Object { [string]$_.kind -eq 'baseline' })
    if ($positive.Count -lt 2) { $findings.Add((New-OperationFinding 'positive_case_threshold_not_met' 'error' '$.corpus.cases' 'At least two positive cases are required.')) | Out-Null }
    if ($negative.Count -lt 1) { $findings.Add((New-OperationFinding 'negative_case_missing' 'error' '$.corpus.cases' 'At least one negative or no-skill case is required.')) | Out-Null }
    if ($baselineControls.Count -lt 1) { $findings.Add((New-OperationFinding 'no_skill_baseline_missing' 'error' '$.corpus.cases' 'At least one no-skill baseline case is required.')) | Out-Null }
    $caseIds = @($cases | ForEach-Object { [string]$_.id })
    if (@($caseIds | Where-Object { $_ } | Sort-Object -Unique).Count -ne $cases.Count) { $findings.Add((New-OperationFinding 'corpus_case_id_invalid' 'error' '$.corpus.cases' 'Corpus case IDs must be present and unique.')) | Out-Null }
    foreach ($metric in @('success_count', 'false_trigger_count', 'tool_rounds', 'side_effects')) {
        if ($null -eq (Get-SkillEvolutionProperty $Corpus.baseline_metrics $metric)) { $findings.Add((New-OperationFinding 'baseline_metric_missing' 'error' ('$.corpus.baseline_metrics.{0}' -f $metric) 'Baseline metrics are required for promotion comparison.')) | Out-Null }
    }
    if ($Execute -and @($CaseResults).Count -ne $cases.Count) { $findings.Add((New-OperationFinding 'forward_test_result_count_invalid' 'error' '$.results' 'Execute evaluation requires one result for every corpus case.')) | Out-Null }
    $resultIds = @($CaseResults | ForEach-Object { [string]$_.case_id })
    if ($Execute -and (($resultIds | Sort-Object -Unique).Count -ne $cases.Count -or @($resultIds | Where-Object { $caseIds -notcontains $_ }).Count -gt 0)) {
        $findings.Add((New-OperationFinding 'forward_test_result_identity_invalid' 'error' '$.results' 'Forward-test result IDs must exactly match the corpus.')) | Out-Null
    }
    $resultIndex = @{}
    foreach ($result in @($CaseResults)) { $resultIndex[[string]$result.case_id] = $result }
    $positivePass = 0; $controlPass = 0; $successCount = 0; $falseTriggers = 0; $toolRounds = 0; $sideEffects = 0
    if ($Execute) {
        foreach ($case in $cases) {
            $result = $resultIndex[[string]$case.id]
            if ($null -eq $result) { continue }
            $receiptValid = [int]$result.exit_code -eq 0 -and [bool]$result.parse_ok -and [string]$result.model -eq $Model -and [string]$result.reasoning_effort -eq $ReasoningEffort
            foreach ($metric in @('duration_ms', 'input_tokens', 'output_tokens', 'tool_rounds', 'side_effects')) {
                if ($null -eq (Get-SkillEvolutionProperty $result $metric) -or [int64](Get-SkillEvolutionProperty $result $metric) -lt 0) { $receiptValid = $false }
            }
            if (-not $receiptValid) {
                $findings.Add((New-OperationFinding 'forward_test_receipt_invalid' 'error' ([string]$case.id) 'Forward-test result lacks a successful parseable exact-model receipt.')) | Out-Null
                continue
            }
            $toolRounds += [int]$result.tool_rounds
            $sideEffects += [int]$result.side_effects
            $kind = [string]$case.kind
            $selected = [string]$result.selected_skill
            $applies = [bool]$result.applicable
            $satisfied = [bool]$result.task_satisfied
            $passed = if ($kind -eq 'positive') { $applies -and $satisfied -and $selected -eq $skillName } else { -not $applies -and [string]::IsNullOrWhiteSpace($selected) }
            if ($kind -eq 'positive' -and $passed) { $positivePass++; $successCount++ }
            elseif ($kind -ne 'positive' -and $passed) { $controlPass++ }
            if ($kind -ne 'positive' -and ($applies -or -not [string]::IsNullOrWhiteSpace($selected))) { $falseTriggers++ }
            if (-not $passed) { $findings.Add((New-OperationFinding 'forward_test_case_failed' 'error' ([string]$case.id) 'Forward-test outcome did not satisfy the case contract.')) | Out-Null }
        }
    }
    $baseline = $Corpus.baseline_metrics
    $noRegression = $Execute -and $falseTriggers -le [int]$baseline.false_trigger_count -and $toolRounds -le [int]$baseline.tool_rounds -and $sideEffects -le [int]$baseline.side_effects
    $targetFailureFixed = $Execute -and $positivePass -eq $positive.Count -and $positive.Count -ge 2
    $metricImproved = $Execute -and ($successCount -gt [int]$baseline.success_count -or $falseTriggers -lt [int]$baseline.false_trigger_count -or $toolRounds -lt [int]$baseline.tool_rounds -or $sideEffects -lt [int]$baseline.side_effects)
    if ($Execute -and -not $noRegression) { $findings.Add((New-OperationFinding 'baseline_regression' 'error' '$.metrics' 'Candidate adds false triggers, tool rounds, or side effects compared with baseline.')) | Out-Null }
    if ($Execute -and -not ($targetFailureFixed -or $metricImproved)) { $findings.Add((New-OperationFinding 'net_benefit_not_demonstrated' 'error' '$.metrics' 'Candidate must fix the target failure or improve a declared metric.')) | Out-Null }
    $targetState = Get-SkillEvolutionTargetState $RepoRoot $skillName
    if ($null -ne $manifest -and [string]$manifest.baseline_fingerprint -ne [string]$targetState.fingerprint) {
        $findings.Add((New-OperationFinding 'candidate_baseline_drift' 'error' 'candidate.json' 'Active baseline changed after candidate preparation.')) | Out-Null
    }
    $staticPass = (@($findings | Where-Object severity -eq 'error').Count -eq 0)
    $promotionEligible = $Execute -and $staticPass -and $positivePass -eq $positive.Count -and $controlPass -eq ($negative.Count + $baselineControls.Count) -and $noRegression -and ($targetFailureFixed -or $metricImproved)
    return [pscustomobject][ordered]@{
        schema_version = 1
        evaluation_id = 'eval-{0}' -f $state.fingerprint.Substring(0, 16)
        evaluated_at = [datetimeoffset]::UtcNow.ToString('o')
        truth_boundary = if ($Execute) { 'isolated_forward_test_not_host_invocation' } else { 'static_candidate_validation' }
        execute = [bool]$Execute
        model = $Model
        reasoning_effort = $ReasoningEffort
        pass = $staticPass
        promotion_eligible = $promotionEligible
        candidate_directory = $state.root
        candidate_fingerprint = $state.fingerprint
        baseline_fingerprint = $targetState.fingerprint
        catalog_fingerprint = Get-SkillEvolutionCatalogFingerprint $RepoRoot
        corpus_fingerprint = Get-SkillEvolutionJsonHash $Corpus
        skill_name = $skillName
        allowed_paths = @($state.files.path)
        metrics = [pscustomobject]@{ positive_passed = $positivePass; positive_total = $positive.Count; controls_passed = $controlPass; controls_total = ($negative.Count + $baselineControls.Count); success_count = $successCount; false_trigger_count = $falseTriggers; tool_rounds = $toolRounds; side_effects = $sideEffects; target_failure_fixed = $targetFailureFixed; metric_improved = $metricImproved; no_regression = $noRegression }
        case_results = @($CaseResults)
        findings = @($findings.ToArray())
        active_writes = 0
        report_writes = 0
        provider_calls = if ($Execute) { $cases.Count } else { 0 }
        host_writes = 0
    }
}

function Test-SkillEvolutionEvaluationReceipt($Evaluation, $CandidateState, $TargetState, [string]$CatalogFingerprint) {
    $findings = [System.Collections.Generic.List[object]]::new()
    if ([int]$Evaluation.schema_version -ne 1 -or -not [bool]$Evaluation.execute -or -not [bool]$Evaluation.pass -or -not [bool]$Evaluation.promotion_eligible) {
        $findings.Add((New-OperationFinding 'evaluation_not_promotion_eligible' 'error' '$.evaluation' 'Evaluation must be an executed, passing, promotion-eligible receipt.')) | Out-Null
    }
    if ([string]$Evaluation.truth_boundary -ne 'isolated_forward_test_not_host_invocation') { $findings.Add((New-OperationFinding 'evaluation_truth_boundary_invalid' 'error' '$.truth_boundary' 'Promotion requires an isolated forward-test receipt.')) | Out-Null }
    if ([string]$Evaluation.candidate_fingerprint -ne [string]$CandidateState.fingerprint -or [string]$Evaluation.baseline_fingerprint -ne [string]$TargetState.fingerprint -or [string]$Evaluation.catalog_fingerprint -ne $CatalogFingerprint) {
        $findings.Add((New-OperationFinding 'evaluation_fingerprint_mismatch' 'error' '$.evaluation' 'Evaluation does not bind the exact-current candidate, baseline, and catalog.')) | Out-Null
    }
    $metrics = $Evaluation.metrics
    $metricsPass = [int]$metrics.positive_total -ge 2 -and [int]$metrics.positive_passed -eq [int]$metrics.positive_total -and [int]$metrics.controls_total -ge 2 -and [int]$metrics.controls_passed -eq [int]$metrics.controls_total -and [bool]$metrics.no_regression -and ([bool]$metrics.target_failure_fixed -or [bool]$metrics.metric_improved)
    if (-not $metricsPass) { $findings.Add((New-OperationFinding 'evaluation_metrics_invalid' 'error' '$.metrics' 'Evaluation metrics do not satisfy the promotion gate.')) | Out-Null }
    $allowed = @($Evaluation.allowed_paths | ForEach-Object { ConvertTo-SkillEvolutionRelativePath ([string]$_) } | Where-Object { $_ } | Sort-Object -Unique)
    $candidateAllowed = @($CandidateState.files.path | ForEach-Object { ConvertTo-SkillEvolutionRelativePath ([string]$_) } | Where-Object { $_ } | Sort-Object -Unique)
    if (($allowed -join '|').ToLowerInvariant() -ne ($candidateAllowed -join '|').ToLowerInvariant()) { $findings.Add((New-OperationFinding 'evaluation_allowed_paths_mismatch' 'error' '$.allowed_paths' 'Evaluation allowed_paths do not match the candidate package.')) | Out-Null }
    if ([string]$Evaluation.reasoning_effort -notin $script:SkillEvolutionAllowedReasoningEfforts -or [string]::IsNullOrWhiteSpace([string]$Evaluation.model)) { $findings.Add((New-OperationFinding 'evaluation_model_effort_invalid' 'error' '$.model' 'Evaluation model and reasoning effort must be explicit.')) | Out-Null }
    if (@($Evaluation.case_results).Count -lt 4 -or @($Evaluation.case_results | Where-Object { [int]$_.exit_code -ne 0 -or -not [bool]$_.parse_ok }).Count -gt 0) {
        $findings.Add((New-OperationFinding 'evaluation_case_receipts_invalid' 'error' '$.case_results' 'Promotion requires at least four successful parseable forward-test receipts.')) | Out-Null
    }
    return [pscustomobject]@{ pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0); findings = @($findings.ToArray()) }
}

function Test-SkillEvolutionReview {
    param($Review, $Evaluation, [string]$EvaluationReceiptHash, [string[]]$AllowedPaths)
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($field in @('candidate_fingerprint', 'baseline_fingerprint', 'reviewer', 'decision', 'reviewed_at', 'expires_at', 'evaluation_receipt_hash')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-SkillEvolutionProperty $Review $field))) { $findings.Add((New-OperationFinding 'review_field_missing' 'error' ('$.{0}' -f $field) 'Reviewed change-set field is required.')) | Out-Null }
    }
    if ([string]$Review.decision -ne 'approve') { $findings.Add((New-OperationFinding 'review_not_approved' 'error' '$.decision' 'Review decision must be approve.')) | Out-Null }
    if ([string]$Review.candidate_fingerprint -ne [string]$Evaluation.candidate_fingerprint -or [string]$Review.baseline_fingerprint -ne [string]$Evaluation.baseline_fingerprint) { $findings.Add((New-OperationFinding 'review_fingerprint_mismatch' 'error' '$.candidate_fingerprint' 'Review does not bind the evaluated candidate and baseline.')) | Out-Null }
    if ([string]$Review.evaluation_receipt_hash -ne $EvaluationReceiptHash) { $findings.Add((New-OperationFinding 'review_evaluation_hash_mismatch' 'error' '$.evaluation_receipt_hash' 'Review does not bind the current evaluation receipt.')) | Out-Null }
    $reviewedAt = [datetimeoffset]::MinValue; $expiresAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Review.reviewed_at, [ref]$reviewedAt) -or -not [datetimeoffset]::TryParse([string]$Review.expires_at, [ref]$expiresAt)) { $findings.Add((New-OperationFinding 'review_timestamp_invalid' 'error' '$.expires_at' 'Review timestamps must be valid RFC3339 values.')) | Out-Null }
    elseif ($expiresAt -le [datetimeoffset]::UtcNow -or $expiresAt -le $reviewedAt -or $reviewedAt -gt [datetimeoffset]::UtcNow.AddMinutes(5)) { $findings.Add((New-OperationFinding 'review_expired' 'error' '$.expires_at' 'Reviewed change-set is expired or has an invalid future timestamp.')) | Out-Null }
    $reviewPaths = @($Review.allowed_paths | ForEach-Object { ConvertTo-SkillEvolutionRelativePath ([string]$_) } | Where-Object { $_ } | Sort-Object -Unique)
    $candidatePaths = @($AllowedPaths | ForEach-Object { ConvertTo-SkillEvolutionRelativePath ([string]$_) } | Where-Object { $_ } | Sort-Object -Unique)
    if ($reviewPaths.Count -ne @($Review.allowed_paths).Count -or $candidatePaths.Count -ne @($AllowedPaths).Count) { $findings.Add((New-OperationFinding 'review_allowed_path_invalid' 'error' '$.allowed_paths' 'Review paths must be unique contained relative paths.')) | Out-Null }
    if (($reviewPaths -join '|').ToLowerInvariant() -ne ($candidatePaths -join '|').ToLowerInvariant()) { $findings.Add((New-OperationFinding 'review_allowed_paths_mismatch' 'error' '$.allowed_paths' 'Review allowed_paths must exactly match the evaluated candidate package.')) | Out-Null }
    return [pscustomobject]@{ pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0); findings = @($findings.ToArray()) }
}

function New-SkillEvolutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CandidateDirectory,
        [Parameter(Mandatory = $true)]$Evaluation,
        [Parameter(Mandatory = $true)][string]$EvaluationPath,
        [Parameter(Mandatory = $true)]$Review,
        [Parameter(Mandatory = $true)][string]$ReviewPath,
        [string]$RepoRoot = $script:SkillEvolutionRepoRoot
    )
    if (-not (Test-SkillEvolutionPathWithin $CandidateDirectory (Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'reports\skill-evolution'))) { throw 'Candidate directory must remain under reports/skill-evolution.' }
    $evaluationFull = Assert-SkillEvolutionReportPath $EvaluationPath $RepoRoot
    $reviewFull = Assert-SkillEvolutionReportPath $ReviewPath $RepoRoot
    $state = Get-SkillEvolutionPackageState $CandidateDirectory
    if (-not $state.pass -or $state.fingerprint -ne [string]$Evaluation.candidate_fingerprint) { throw 'Candidate drifted after evaluation.' }
    $targetState = Get-SkillEvolutionTargetState $RepoRoot ([string]$Evaluation.skill_name)
    $catalogFingerprint = Get-SkillEvolutionCatalogFingerprint $RepoRoot
    $evaluationValidation = Test-SkillEvolutionEvaluationReceipt $Evaluation $state $targetState $catalogFingerprint
    if (-not $evaluationValidation.pass) { throw ('Evaluation is invalid: {0}' -f (@($evaluationValidation.findings.code) -join ',')) }
    if ([string]$Evaluation.skill_name -ne [string]$state.metadata.name) { throw 'Evaluation skill identity does not match candidate frontmatter.' }
    $evaluationHash = Get-SkillEvolutionFileHash $evaluationFull
    $reviewHash = Get-SkillEvolutionFileHash $reviewFull
    $reviewValidation = Test-SkillEvolutionReview $Review $Evaluation $evaluationHash @($state.files.path)
    if (-not $reviewValidation.pass) { throw ('Reviewed change-set is invalid: {0}' -f (@($reviewValidation.findings.code) -join ',')) }
    $target = $targetState.path
    $operation = New-OperationPlan -OperationId ('skill-lifecycle-{0}' -f $state.fingerprint.Substring(0, 16)) -Domain skill_lifecycle -Mode apply -CreatedAt ([datetimeoffset]::UtcNow.ToString('o')) -SourceRevision $catalogFingerprint -Targets @([pscustomobject]@{ target_ref = [string]$Evaluation.skill_name; path = $target; before_hash = if ($targetState.exists) { $targetState.fingerprint } else { $null }; desired_hash = $state.fingerprint; owner = 'skills-manager' }) -Actions @([pscustomobject]@{ type = if ($targetState.exists) { 'update' } else { 'create' }; target_ref = [string]$Evaluation.skill_name; summary = 'Promote reviewed skill candidate into overrides/custom without projection.'; risk = 'medium'; metadata = [pscustomobject]@{ allowed_paths = @($state.files.path) } }) -Preconditions @('candidate_exact_current', 'evaluation_exact_current', 'review_exact_current', 'baseline_exact_current', 'catalog_exact_current') -Verification @('target package hash equals desired hash', 'skills.json/agent/user root/host config remain untouched') -Rollback @('restore only this promotion receipt package')
    $operation | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject][ordered]@{ skill_name = [string]$Evaluation.skill_name; candidate_directory = $state.root; candidate_fingerprint = $state.fingerprint; baseline_fingerprint = $targetState.fingerprint; baseline_existed = [bool]$targetState.exists; catalog_fingerprint = $catalogFingerprint; evaluation_path = $evaluationFull; evaluation_hash = $evaluationHash; review_path = $reviewFull; review_hash = $reviewHash; review_expires_at = [string]$Review.expires_at; allowed_paths = @($state.files.path); projection_disposition = 'cold_catalog_only'; host_mutation = $false })
    return $operation
}

function Copy-SkillEvolutionPackage([string]$Source, [string]$Destination, [string[]]$AllowedPaths) {
    $sourceRoot = [System.IO.Path]::GetFullPath($Source)
    $destinationRoot = [System.IO.Path]::GetFullPath($Destination)
    if (Test-Path -LiteralPath $destinationRoot) { throw ('SkillEvolution destination already exists: {0}' -f $destinationRoot) }
    [System.IO.Directory]::CreateDirectory($destinationRoot) | Out-Null
    foreach ($relative in $AllowedPaths) {
        $normalized = ConvertTo-SkillEvolutionRelativePath $relative
        if ([string]::IsNullOrWhiteSpace($normalized) -or -not (Test-SkillEvolutionAllowedRelativePath $normalized)) { throw ('Forbidden candidate path: {0}' -f $relative) }
        $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $sourceRoot $normalized))
        $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $destinationRoot $normalized))
        if (-not (Test-SkillEvolutionPathWithin $sourcePath $sourceRoot) -or -not (Test-SkillEvolutionPathWithin $destinationPath $destinationRoot)) { throw ('Candidate path escaped its package root: {0}' -f $relative) }
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw ('Candidate source file is missing: {0}' -f $normalized) }
        $sourceItem = Get-Item -LiteralPath $sourcePath -Force
        if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('Candidate source file is a reparse point: {0}' -f $normalized) }
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $destinationPath)) | Out-Null
        [System.IO.File]::Copy($sourcePath, $destinationPath, $true)
    }
}

function Invoke-SkillEvolutionApply {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)][string]$Token, [Parameter(Mandatory = $true)][string]$ReceiptPath, [string]$RepoRoot = $script:SkillEvolutionRepoRoot)
    if ($Token -cne 'PROMOTE_SKILL_CANDIDATE') { throw 'Promotion requires PROMOTE_SKILL_CANDIDATE.' }
    $contract = Test-OperationPlanContract $Plan
    if (-not $contract.pass -or [string]$Plan.domain -ne 'skill_lifecycle') { throw 'Skill lifecycle plan contract is invalid.' }
    $life = $Plan.lifecycle
    $skillName = [string]$life.skill_name
    if ($skillName -notmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or @($Plan.targets).Count -ne 1 -or @($Plan.actions).Count -ne 1 -or [string]$Plan.mode -ne 'apply') { throw 'Skill lifecycle plan shape is invalid.' }
    $expectedTarget = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) ('overrides\custom\{0}' -f $skillName)
    $target = [System.IO.Path]::GetFullPath([string]$Plan.targets[0].path)
    if ($target -ne [System.IO.Path]::GetFullPath($expectedTarget) -or -not (Test-OperationPathWithinRoot $target (Join-Path $RepoRoot 'overrides\custom'))) { throw 'Plan target escaped overrides/custom.' }
    $beforeHashMatches = if ([bool]$life.baseline_existed) { [string]$Plan.targets[0].before_hash -eq [string]$life.baseline_fingerprint } else { $null -eq $Plan.targets[0].before_hash }
    if ([string]$Plan.targets[0].desired_hash -ne [string]$life.candidate_fingerprint -or -not $beforeHashMatches -or [string]$Plan.targets[0].owner -ne 'skills-manager') { throw 'Plan target hashes or ownership do not match the lifecycle binding.' }
    if (-not (Test-SkillEvolutionPathWithin ([string]$life.candidate_directory) (Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'reports\skill-evolution'))) { throw 'Candidate directory escaped reports/skill-evolution.' }
    $candidateState = Get-SkillEvolutionPackageState ([string]$life.candidate_directory)
    $targetState = Get-SkillEvolutionTargetState $RepoRoot $skillName
    if (-not $candidateState.pass -or $candidateState.fingerprint -ne [string]$life.candidate_fingerprint -or [string]$candidateState.metadata.name -ne $skillName) { throw 'Candidate drifted before apply.' }
    if ($targetState.fingerprint -ne [string]$life.baseline_fingerprint) { throw 'Baseline drifted before apply.' }
    $candidatePaths = @($candidateState.files.path | ForEach-Object { ConvertTo-SkillEvolutionRelativePath ([string]$_) } | Sort-Object -Unique)
    $planPaths = @($life.allowed_paths | ForEach-Object { ConvertTo-SkillEvolutionRelativePath ([string]$_) } | Where-Object { $_ } | Sort-Object -Unique)
    $actionPaths = @($Plan.actions[0].metadata.allowed_paths | ForEach-Object { ConvertTo-SkillEvolutionRelativePath ([string]$_) } | Where-Object { $_ } | Sort-Object -Unique)
    if ($planPaths.Count -ne @($life.allowed_paths).Count -or ($planPaths -join '|').ToLowerInvariant() -ne ($candidatePaths -join '|').ToLowerInvariant() -or ($actionPaths -join '|').ToLowerInvariant() -ne ($candidatePaths -join '|').ToLowerInvariant()) { throw 'Plan allowed_paths do not exactly match the candidate package.' }
    $catalogFingerprint = Get-SkillEvolutionCatalogFingerprint $RepoRoot
    if ($catalogFingerprint -ne [string]$life.catalog_fingerprint -or [string]$Plan.source_revision -ne $catalogFingerprint) { throw 'Catalog drifted before apply.' }
    $evaluationFull = Assert-SkillEvolutionReportPath ([string]$life.evaluation_path) $RepoRoot
    $reviewFull = Assert-SkillEvolutionReportPath ([string]$life.review_path) $RepoRoot
    if ((Get-SkillEvolutionFileHash $evaluationFull) -ne [string]$life.evaluation_hash) { throw 'Evaluation receipt drifted before apply.' }
    if ((Get-SkillEvolutionFileHash $reviewFull) -ne [string]$life.review_hash) { throw 'Reviewed change-set drifted before apply.' }
    try { $evaluation = [System.IO.File]::ReadAllText($evaluationFull) | ConvertFrom-Json; $review = [System.IO.File]::ReadAllText($reviewFull) | ConvertFrom-Json }
    catch { throw ('Evaluation or review is invalid JSON: {0}' -f $_.Exception.Message) }
    $evaluationValidation = Test-SkillEvolutionEvaluationReceipt $evaluation $candidateState $targetState $catalogFingerprint
    if (-not $evaluationValidation.pass -or [string]$evaluation.skill_name -ne $skillName) { throw ('Evaluation receipt is invalid: {0}' -f (@($evaluationValidation.findings.code) -join ',')) }
    $reviewValidation = Test-SkillEvolutionReview $review $evaluation ([string]$life.evaluation_hash) $candidatePaths
    if (-not $reviewValidation.pass) { throw ('Reviewed change-set is invalid: {0}' -f (@($reviewValidation.findings.code) -join ',')) }

    $receiptFull = Assert-SkillEvolutionReportPath $ReceiptPath $RepoRoot
    if (Test-Path -LiteralPath $receiptFull) { throw ('Promotion receipt already exists: {0}' -f $receiptFull) }
    $runRoot = Split-Path -Parent $receiptFull
    $backupRoot = Join-Path $runRoot ('backup\{0}' -f $skillName)
    if (Test-Path -LiteralPath $backupRoot) { throw ('Promotion backup already exists: {0}' -f $backupRoot) }
    $targetParent = Split-Path -Parent $target
    [System.IO.Directory]::CreateDirectory($targetParent) | Out-Null
    if ($targetState.exists) { Copy-SkillEvolutionPackage $target $backupRoot @($targetState.files.path) }
    $stage = Join-Path $targetParent ('.{0}.stage-{1}' -f $skillName, ([guid]::NewGuid().ToString('N')))
    $old = Join-Path $targetParent ('.{0}.old-{1}' -f $skillName, ([guid]::NewGuid().ToString('N')))
    Copy-SkillEvolutionPackage ([string]$life.candidate_directory) $stage @($life.allowed_paths)
    $started = [datetimeoffset]::UtcNow.ToString('o')
    try {
        if ($targetState.exists) { Move-Item -LiteralPath $target -Destination $old }
        Move-Item -LiteralPath $stage -Destination $target
        $after = Get-SkillEvolutionPackageState $target
        if (-not $after.pass -or $after.fingerprint -ne [string]$life.candidate_fingerprint -or [string]$after.metadata.name -ne $skillName) { throw 'Promoted target hash does not match the candidate.' }
        $completed = [datetimeoffset]::UtcNow.ToString('o')
        $receipt = New-OperationReceipt -OperationId ([string]$Plan.operation_id) -Status applied -StartedAt $started -CompletedAt $completed -Actions @([pscustomobject]@{ action_id = [string]$Plan.actions[0].action_id; status = 'applied'; target_ref = $skillName; path = $target; before_hash = $life.baseline_fingerprint; after_hash = $after.fingerprint; files = @($after.files) }) -Backups @([pscustomobject]@{ path = if ($targetState.exists) { $backupRoot } else { $null }; before_existed = [bool]$targetState.exists; before_hash = $life.baseline_fingerprint; files = @($targetState.files) }) -Verification ([pscustomobject]@{ static_validated = 'pass'; repo_gates_passed = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }) -Rollback @('exact package rollback only; fail closed on target drift')
        $receipt | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject][ordered]@{ skill_name = $skillName; target = $target; candidate_fingerprint = $life.candidate_fingerprint; before_fingerprint = $life.baseline_fingerprint; after_fingerprint = $after.fingerprint; backup_root = if ($targetState.exists) { $backupRoot } else { $null }; before_existed = [bool]$targetState.exists; plan_hash = Get-SkillEvolutionJsonHash $Plan; evaluation_hash = $life.evaluation_hash; review_hash = $life.review_hash; active_writes = 1; host_writes = 0; provider_calls = 0; projection_changed = $false; skills_config_changed = $false; generated_agent_changed = $false })
        Write-SkillEvolutionJsonAtomic $receiptFull $receipt
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
        return $receipt
    }
    catch {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination $target }
        if (Test-Path -LiteralPath $backupRoot) { Remove-Item -LiteralPath $backupRoot -Recurse -Force }
        throw
    }
    finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}

function Invoke-SkillEvolutionRollback {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Receipt, [Parameter(Mandatory = $true)][string]$Token, [string]$OutPath, [string]$RepoRoot = $script:SkillEvolutionRepoRoot)
    if ($Token -cne 'ROLLBACK_SKILL_PROMOTION') { throw 'Rollback requires ROLLBACK_SKILL_PROMOTION.' }
    if ([string]$Receipt.status -ne 'applied' -or $null -eq $Receipt.lifecycle) { throw 'Only an applied skill promotion receipt can be rolled back.' }
    $life = $Receipt.lifecycle
    $skillName = [string]$life.skill_name
    if ($skillName -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Rollback receipt skill identity is invalid.' }
    $target = [System.IO.Path]::GetFullPath([string]$life.target)
    $allowedRoot = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'overrides\custom'
    $expectedTarget = [System.IO.Path]::GetFullPath((Join-Path $allowedRoot $skillName))
    if ($target -ne $expectedTarget -or -not (Test-OperationPathWithinRoot $target $allowedRoot)) { throw 'Rollback target escaped overrides/custom.' }
    $current = Get-SkillEvolutionPackageState $target
    if (-not $current.pass -or $current.fingerprint -ne [string]$life.after_fingerprint -or [string]$current.metadata.name -ne $skillName) { throw 'Promotion target drifted after apply; rollback is fail closed.' }
    $targetParent = Split-Path -Parent $target
    $restoreStage = Join-Path $targetParent ('.{0}.rollback-{1}' -f $skillName, ([guid]::NewGuid().ToString('N')))
    $promotedOld = Join-Path $targetParent ('.{0}.promoted-{1}' -f $skillName, ([guid]::NewGuid().ToString('N')))
    if ([bool]$life.before_existed) {
        if (-not (Test-SkillEvolutionPathWithin ([string]$life.backup_root) (Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'reports\skill-evolution'))) { throw 'Promotion backup escaped reports/skill-evolution.' }
        $backup = Get-SkillEvolutionPackageState ([string]$life.backup_root)
        if (-not $backup.pass -or $backup.fingerprint -ne [string]$life.before_fingerprint) { throw 'Promotion backup is missing or drifted.' }
        Copy-SkillEvolutionPackage ([string]$life.backup_root) $restoreStage @($backup.files.path)
    }
    $started = [datetimeoffset]::UtcNow.ToString('o')
    try {
        Move-Item -LiteralPath $target -Destination $promotedOld
        if ([bool]$life.before_existed) { Move-Item -LiteralPath $restoreStage -Destination $target }
        $after = if ([bool]$life.before_existed) { Get-SkillEvolutionPackageState $target } else { $null }
        if ([bool]$life.before_existed -and (-not $after.pass -or $after.fingerprint -ne [string]$life.before_fingerprint)) { throw 'Rollback restoration hash mismatch.' }
        if (-not [bool]$life.before_existed -and (Test-Path -LiteralPath $target)) { throw 'Rollback failed to remove the newly promoted package.' }
        $rolled = New-OperationReceipt -OperationId ([string]$Receipt.operation_id) -Status rolled_back -StartedAt $started -CompletedAt ([datetimeoffset]::UtcNow.ToString('o')) -Actions @([pscustomobject]@{ action_id = 'skill-promotion-rollback'; status = 'rolled_back'; target_ref = $skillName; path = $target; restored_hash = if ($after) { $after.fingerprint } else { Get-OperationSha256 '' } }) -Verification ([pscustomobject]@{ static_validated = 'pass'; repo_gates_passed = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }) -Rollback @('promotion receipt consumed without changing host projection')
        $rolled | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject]@{ skill_name = $skillName; target = $target; restored = $true; active_writes = 1; host_writes = 0; provider_calls = 0; projection_changed = $false })
        if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
            $outFull = Assert-SkillEvolutionReportPath $OutPath $RepoRoot
            if (Test-Path -LiteralPath $outFull) { throw ('Rollback receipt already exists: {0}' -f $outFull) }
            Write-SkillEvolutionJsonAtomic $outFull $rolled
        }
        Remove-Item -LiteralPath $promotedOld -Recurse -Force
        return $rolled
    }
    catch {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        if (Test-Path -LiteralPath $promotedOld) { Move-Item -LiteralPath $promotedOld -Destination $target }
        throw
    }
    finally { if (Test-Path -LiteralPath $restoreStage) { Remove-Item -LiteralPath $restoreStage -Recurse -Force } }
}

function Write-SkillEvolutionTextAtomic([string]$Path, [string]$Content) {
    if (Get-Command Write-Utf8FileAtomic -ErrorAction SilentlyContinue) {
        Write-Utf8FileAtomic -Path $Path -Content $Content
        return
    }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
    $temp = '{0}.tmp-{1}' -f $Path, ([guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($temp, $Content, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($temp, $Path, $true)
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function ConvertTo-SkillEvolutionRfc3339($Value) {
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).ToUniversalTime().ToString('o') }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('o') }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Value, [ref]$parsed)) { return [string]$Value }
    return $parsed.ToUniversalTime().ToString('o')
}

function Get-SkillEvolutionReviewToken([string]$ReviewType, [string]$Action = '') {
    if ($ReviewType -eq 'promotion') { return 'PROMOTE_SKILL_CANDIDATE' }
    if ($ReviewType -eq 'activation' -and $Action -eq 'retire') { return 'RETIRE_SKILL_ON_HOST' }
    if ($ReviewType -eq 'activation' -and $Action -in @('enable', 'refresh')) { return 'ACTIVATE_SKILL_ON_HOST' }
    throw ('Unsupported skill evolution review type/action: {0}/{1}' -f $ReviewType, $Action)
}

function Get-SkillEvolutionRejectionToken([string]$ReviewType) {
    if ($ReviewType -eq 'promotion') { return 'REJECT_SKILL_CANDIDATE' }
    if ($ReviewType -eq 'activation') { return 'REJECT_SKILL_ACTIVATION_CHANGE' }
    throw ('Unsupported skill evolution rejection type: {0}' -f $ReviewType)
}

function New-SkillEvolutionReviewInteraction([string]$ReviewType, [string]$Action, [string]$SkillName, [string]$Token) {
    $question = if ($ReviewType -eq 'promotion') {
        '候选技能 {0} 已通过隔离评估。是否授权晋级到 overrides/custom 并自动执行不写宿主的 cold build？' -f $SkillName
    }
    elseif ($Action -eq 'retire') {
        '是否授权将技能 {0} 从活跃覆盖中退役，并在仓库门禁与 clean commit 后自动同步宿主投影？源码将保留在冷 catalog。' -f $SkillName
    }
    else {
        '是否授权将技能 {0} {1}活跃覆盖，并在仓库门禁与 clean commit 后自动同步宿主投影？' -f $SkillName, $(if ($Action -eq 'refresh') { '刷新到' } else { '加入' })
    }
    $options = [System.Collections.Generic.List[object]]::new()
    $options.Add([pscustomobject]@{ decision = 'approve'; label = '批准'; effect = 'Execute only the exact-current reviewed scope.' }) | Out-Null
    $options.Add([pscustomobject]@{
        decision = 'reject'
        label = if ($ReviewType -eq 'promotion') { '拒绝并保留' } else { '拒绝（保持冷态）' }
        effect = if ($ReviewType -eq 'promotion') { 'Do not promote or project; retain redacted evidence and candidate for 7 days.' } else { 'Do not activate, refresh, retire, or project; keep the package in its current cold-catalog state.' }
    }) | Out-Null
    if ($ReviewType -eq 'promotion') {
        $options.Add([pscustomobject]@{ decision = 'reject_delete'; label = '拒绝并删除'; effect = 'Do not promote or project; immediately delete only the isolated unpromoted candidate.' }) | Out-Null
    }
    $decisionValues = if ($ReviewType -eq 'promotion') { 'approve|reject|reject_delete' } else { 'approve|reject' }
    return [pscustomobject][ordered]@{
        required = $true
        kind = 'question'
        notification_class = 'permission_and_question'
        preferred_surface = 'chatgpt_desktop'
        user_action = 'Reply in the current ChatGPT Desktop task; no CLI command or token entry is required from the user.'
        cli_is_host_internal = $true
        host_must_pause = $true
        question = $question
        options = @($options.ToArray())
        default_decision = 'reject'
        approval_token = $Token
        rejection_token = Get-SkillEvolutionRejectionToken $ReviewType
        deletion_token = if ($ReviewType -eq 'promotion') { 'DELETE_REJECTED_SKILL_CANDIDATE' } else { $null }
        host_resume_command = 'skills.ps1 skill-evolution decide --request <request.json> --decision <{0}> --reviewer user --token <token> --out <run-root> --json' -f $decisionValues
    }
}

function New-SkillEvolutionPromotionReviewRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CandidateDirectory,
        [Parameter(Mandatory = $true)]$Evaluation,
        [Parameter(Mandatory = $true)][string]$EvaluationPath,
        [Parameter(Mandatory = $true)][string]$OutPath,
        [int]$ExpiresInHours = 24,
        [string]$RepoRoot = $script:SkillEvolutionRepoRoot
    )
    $state = Get-SkillEvolutionPackageState $CandidateDirectory
    $targetState = Get-SkillEvolutionTargetState $RepoRoot ([string]$Evaluation.skill_name)
    $catalogFingerprint = Get-SkillEvolutionCatalogFingerprint $RepoRoot
    $validation = Test-SkillEvolutionEvaluationReceipt $Evaluation $state $targetState $catalogFingerprint
    if (-not $validation.pass) { throw ('Cannot request promotion review: {0}' -f (@($validation.findings.code) -join ',')) }
    $evaluationFull = Assert-SkillEvolutionReportPath $EvaluationPath $RepoRoot
    $outFull = Assert-SkillEvolutionReportPath $OutPath $RepoRoot
    if ((Get-SkillEvolutionFileHash $evaluationFull) -eq $null) { throw 'Evaluation receipt file is required.' }
    if (Test-Path -LiteralPath $outFull) { throw ('Review request already exists: {0}' -f $outFull) }
    $created = [datetimeoffset]::UtcNow
    $token = Get-SkillEvolutionReviewToken promotion
    $request = [pscustomobject][ordered]@{
        schema_version = 1
        request_id = 'review-promotion-{0}' -f $state.fingerprint.Substring(0, 16)
        review_type = 'promotion'
        action = 'promote'
        status = 'authorization_required'
        created_at = $created.ToString('o')
        expires_at = $created.AddHours([math]::Max(1, $ExpiresInHours)).ToString('o')
        skill_name = [string]$Evaluation.skill_name
        subject_path = $state.root
        subject_fingerprint = $state.fingerprint
        baseline_fingerprint = $targetState.fingerprint
        catalog_fingerprint = $catalogFingerprint
        evaluation_path = $evaluationFull
        evaluation_hash = Get-SkillEvolutionFileHash $evaluationFull
        allowed_paths = @($state.files.path)
        authorization_token = $token
        projection_token = $null
        proposed_effects = @('atomically create or replace overrides/custom/<skill>', 'run cold catalog build with host projection skipped', 'create a separate activation review request')
        excluded_effects = @('no skills.json change', 'no user skill root write', 'no Codex config write', 'no host projection', 'no live acceptance claim')
        interaction = New-SkillEvolutionReviewInteraction promotion promote ([string]$Evaluation.skill_name) $token
    }
    Write-SkillEvolutionJsonAtomic $outFull $request
    return [pscustomobject]@{ request = $request; request_path = $outFull; request_hash = Get-SkillEvolutionFileHash $outFull }
}

function New-SkillEvolutionActivationReviewRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SkillName,
        [ValidateSet('auto', 'enable', 'refresh', 'retire')][string]$Action = 'auto',
        [string]$PromotionReceiptPath,
        [Parameter(Mandatory = $true)][string]$OutPath,
        [int]$ExpiresInHours = 24,
        [string]$RepoRoot = $script:SkillEvolutionRepoRoot
    )
    if ($SkillName -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Activation review skill identity is invalid.' }
    $targetState = Get-SkillEvolutionTargetState $RepoRoot $SkillName
    if (-not $targetState.exists -or -not $targetState.pass) { throw 'Activation review requires an exact-current promoted skill package.' }
    $configPath = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'skills.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'skills.json is required for activation review.' }
    try { $config = [System.IO.File]::ReadAllText($configPath) | ConvertFrom-Json }
    catch { throw ('skills.json is invalid: {0}' -f $_.Exception.Message) }
    if ($null -eq $config.skill_projection) { throw 'skills.json has no skill_projection configuration.' }
    $includes = @($config.skill_projection.managed_link_includes | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($Action -eq 'auto') { $Action = if ($includes -contains $SkillName) { 'refresh' } else { 'enable' } }
    if ($Action -eq 'enable' -and $includes -contains $SkillName) { $Action = 'refresh' }
    if ($Action -eq 'refresh' -and $includes -notcontains $SkillName) { throw 'Refresh requires the skill to be present in managed_link_includes.' }
    if ($Action -eq 'retire' -and $includes -notcontains $SkillName) { throw 'Retirement requires an active managed_link_includes entry.' }
    $promotionFull = $null; $promotionHash = $null
    if (-not [string]::IsNullOrWhiteSpace($PromotionReceiptPath)) {
        $promotionFull = Assert-SkillEvolutionReportPath $PromotionReceiptPath $RepoRoot
        $promotionHash = Get-SkillEvolutionFileHash $promotionFull
        if ($null -eq $promotionHash) { throw 'Promotion receipt is missing.' }
        try { $promotion = [System.IO.File]::ReadAllText($promotionFull) | ConvertFrom-Json }
        catch { throw 'Promotion receipt is invalid JSON.' }
        if ([string]$promotion.status -ne 'applied' -or [string]$promotion.lifecycle.skill_name -ne $SkillName -or [string]$promotion.lifecycle.after_fingerprint -ne $targetState.fingerprint) { throw 'Promotion receipt does not bind the exact-current skill package.' }
    }
    $outFull = Assert-SkillEvolutionReportPath $OutPath $RepoRoot
    if (Test-Path -LiteralPath $outFull) { throw ('Activation review request already exists: {0}' -f $outFull) }
    $created = [datetimeoffset]::UtcNow
    $token = Get-SkillEvolutionReviewToken activation $Action
    $request = [pscustomobject][ordered]@{
        schema_version = 1
        request_id = 'review-{0}-{1}-{2}' -f $Action, $SkillName, $targetState.fingerprint.Substring(0, 12)
        review_type = 'activation'
        action = $Action
        status = 'authorization_required'
        created_at = $created.ToString('o')
        expires_at = $created.AddHours([math]::Max(1, $ExpiresInHours)).ToString('o')
        skill_name = $SkillName
        subject_path = $targetState.path
        subject_fingerprint = $targetState.fingerprint
        baseline_fingerprint = $targetState.fingerprint
        catalog_fingerprint = Get-SkillEvolutionCatalogFingerprint $RepoRoot
        config_path = $configPath
        config_hash = Get-SkillEvolutionFileHash $configPath
        current_managed_link_includes = $includes
        promotion_receipt_path = $promotionFull
        promotion_receipt_hash = $promotionHash
        allowed_paths = @('skills.json')
        authorization_token = $token
        projection_token = 'PROJECT_SKILL_TO_HOST'
        proposed_effects = @('stage exact managed_link_includes change or refresh', 'run cold build without host writes', 'after clean commit and exact-current full gate, project managed links and host config')
        excluded_effects = @('no provider/auth/model/sandbox mutation', 'no host restart', 'no physical source deletion', 'no live acceptance claim')
        interaction = New-SkillEvolutionReviewInteraction activation $Action $SkillName $token
    }
    Write-SkillEvolutionJsonAtomic $outFull $request
    return [pscustomobject]@{ request = $request; request_path = $outFull; request_hash = Get-SkillEvolutionFileHash $outFull }
}

function Test-SkillEvolutionReviewRequest {
    param($Request, [string]$RequestPath, [string]$RepoRoot = $script:SkillEvolutionRepoRoot)
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($field in @('request_id', 'review_type', 'action', 'status', 'created_at', 'expires_at', 'skill_name', 'subject_path', 'subject_fingerprint', 'authorization_token')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-SkillEvolutionProperty $Request $field))) { $findings.Add((New-OperationFinding 'review_request_field_missing' 'error' ('$.{0}' -f $field) 'Review request field is required.')) | Out-Null }
    }
    if ([int]$Request.schema_version -ne 1 -or [string]$Request.status -ne 'authorization_required' -or [string]$Request.review_type -notin @('promotion', 'activation')) { $findings.Add((New-OperationFinding 'review_request_identity_invalid' 'error' '$' 'Review request identity/status is invalid.')) | Out-Null }
    if ([string]$Request.skill_name -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') { $findings.Add((New-OperationFinding 'review_request_skill_invalid' 'error' '$.skill_name' 'Review request skill name is invalid.')) | Out-Null }
    $created = [datetimeoffset]::MinValue; $expires = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Request.created_at, [ref]$created) -or -not [datetimeoffset]::TryParse([string]$Request.expires_at, [ref]$expires) -or $expires -le [datetimeoffset]::UtcNow -or $expires -le $created) { $findings.Add((New-OperationFinding 'review_request_expired' 'error' '$.expires_at' 'Review request is expired or has invalid timestamps.')) | Out-Null }
    try {
        $requestFull = Assert-SkillEvolutionReportPath $RequestPath $RepoRoot
        if (-not (Test-Path -LiteralPath $requestFull -PathType Leaf)) { throw 'missing' }
        $null = [System.IO.File]::ReadAllText($requestFull) | ConvertFrom-Json
    }
    catch { $findings.Add((New-OperationFinding 'review_request_path_invalid' 'error' '$.request_path' 'Review request path is missing or outside reports/skill-evolution.')) | Out-Null }
    $expectedToken = $null
    try { $expectedToken = Get-SkillEvolutionReviewToken ([string]$Request.review_type) ([string]$Request.action) }
    catch { $findings.Add((New-OperationFinding 'review_request_action_invalid' 'error' '$.action' 'Review request type/action is invalid.')) | Out-Null }
    if ($null -ne $expectedToken -and [string]$Request.authorization_token -cne $expectedToken) { $findings.Add((New-OperationFinding 'review_request_token_invalid' 'error' '$.authorization_token' 'Review request authorization token does not match its type/action.')) | Out-Null }
    $expectedRejectToken = $null
    try { $expectedRejectToken = Get-SkillEvolutionRejectionToken ([string]$Request.review_type) }
    catch { }
    $interaction = Get-SkillEvolutionProperty $Request 'interaction'
    $expectedDecisions = if ([string]$Request.review_type -eq 'promotion') { @('approve', 'reject', 'reject_delete') } else { @('approve', 'reject') }
    $actualDecisions = @((Get-SkillEvolutionProperty $interaction 'options') | ForEach-Object { [string](Get-SkillEvolutionProperty $_ 'decision') })
    if ($null -eq $interaction -or $null -eq $expectedRejectToken -or (Get-SkillEvolutionProperty $interaction 'required') -ne $true -or [string](Get-SkillEvolutionProperty $interaction 'kind') -ne 'question' -or [string](Get-SkillEvolutionProperty $interaction 'preferred_surface') -ne 'chatgpt_desktop' -or [string](Get-SkillEvolutionProperty $interaction 'approval_token') -cne [string]$Request.authorization_token -or [string](Get-SkillEvolutionProperty $interaction 'rejection_token') -cne $expectedRejectToken -or ($actualDecisions -join '|') -ne ($expectedDecisions -join '|')) {
        $findings.Add((New-OperationFinding 'review_request_interaction_invalid' 'error' '$.interaction' 'Review interaction does not expose the exact Desktop decision set for its lifecycle stage.')) | Out-Null
    }
    if ([string]$Request.review_type -eq 'promotion' -and [string](Get-SkillEvolutionProperty $interaction 'deletion_token') -cne 'DELETE_REJECTED_SKILL_CANDIDATE') { $findings.Add((New-OperationFinding 'review_request_deletion_token_invalid' 'error' '$.interaction.deletion_token' 'Promotion deletion token is invalid.')) | Out-Null }
    if ([string]$Request.review_type -eq 'activation' -and $null -ne (Get-SkillEvolutionProperty $interaction 'deletion_token')) { $findings.Add((New-OperationFinding 'review_request_deletion_exposed' 'error' '$.interaction.deletion_token' 'Activation review must not expose candidate deletion.')) | Out-Null }
    if ((Get-SkillEvolutionCatalogFingerprint $RepoRoot) -ne [string]$Request.catalog_fingerprint) { $findings.Add((New-OperationFinding 'review_request_catalog_drift' 'error' '$.catalog_fingerprint' 'Catalog drifted after the review request.')) | Out-Null }
    $targetState = Get-SkillEvolutionTargetState $RepoRoot ([string]$Request.skill_name)
    if ([string]$Request.review_type -eq 'promotion') {
        if (-not (Test-SkillEvolutionPathWithin ([string]$Request.subject_path) (Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'reports\skill-evolution'))) { $findings.Add((New-OperationFinding 'review_request_subject_invalid' 'error' '$.subject_path' 'Promotion subject escaped the isolated reports root.')) | Out-Null }
        else {
            $state = Get-SkillEvolutionPackageState ([string]$Request.subject_path)
            if (-not $state.pass -or $state.fingerprint -ne [string]$Request.subject_fingerprint) { $findings.Add((New-OperationFinding 'review_request_subject_drift' 'error' '$.subject_fingerprint' 'Promotion candidate drifted after review request.')) | Out-Null }
        }
        if ((Get-SkillEvolutionFileHash ([string]$Request.evaluation_path)) -ne [string]$Request.evaluation_hash) { $findings.Add((New-OperationFinding 'review_request_evaluation_drift' 'error' '$.evaluation_hash' 'Evaluation receipt drifted after review request.')) | Out-Null }
        if ($targetState.fingerprint -ne [string]$Request.baseline_fingerprint) { $findings.Add((New-OperationFinding 'review_request_baseline_drift' 'error' '$.baseline_fingerprint' 'Promotion baseline drifted after review request.')) | Out-Null }
    }
    else {
        if (-not $targetState.exists -or -not $targetState.pass -or $targetState.fingerprint -ne [string]$Request.subject_fingerprint) { $findings.Add((New-OperationFinding 'review_request_subject_drift' 'error' '$.subject_fingerprint' 'Activation package drifted after review request.')) | Out-Null }
        if ((Get-SkillEvolutionFileHash ([string]$Request.config_path)) -ne [string]$Request.config_hash) { $findings.Add((New-OperationFinding 'review_request_config_drift' 'error' '$.config_hash' 'skills.json drifted after review request.')) | Out-Null }
        if ([string]$Request.action -notin @('enable', 'refresh', 'retire')) { $findings.Add((New-OperationFinding 'review_request_action_invalid' 'error' '$.action' 'Activation action is invalid.')) | Out-Null }
    }
    return [pscustomobject]@{ pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0); findings = @($findings.ToArray()) }
}

function New-SkillEvolutionDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][string]$RequestPath,
        [Parameter(Mandatory = $true)][ValidateSet('approve', 'reject', 'reject_delete')][string]$Decision,
        [Parameter(Mandatory = $true)][string]$Reviewer,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$OutPath,
        [int]$RetentionDays = 7,
        [string]$RepoRoot = $script:SkillEvolutionRepoRoot
    )
    $requestFull = Assert-SkillEvolutionReportPath $RequestPath $RepoRoot
    try { $Request = [System.IO.File]::ReadAllText($requestFull) | ConvertFrom-Json }
    catch { throw ('Review request cannot be parsed: {0}' -f $_.Exception.Message) }
    $validation = Test-SkillEvolutionReviewRequest $Request $requestFull $RepoRoot
    if (-not $validation.pass) { throw ('Review request is invalid: {0}' -f (@($validation.findings.code) -join ',')) }
    if ([string]::IsNullOrWhiteSpace($Reviewer)) { throw 'Reviewer identity is required.' }
    if ($Decision -eq 'reject_delete' -and [string]$Request.review_type -ne 'promotion') { throw 'reject_delete is only valid for an isolated promotion candidate.' }
    $expectedToken = if ($Decision -eq 'approve') { [string]$Request.authorization_token } elseif ($Decision -eq 'reject') { Get-SkillEvolutionRejectionToken ([string]$Request.review_type) } else { 'DELETE_REJECTED_SKILL_CANDIDATE' }
    if ($Token -cne $expectedToken) { throw ('Decision requires {0}.' -f $expectedToken) }
    $outFull = Assert-SkillEvolutionReportPath $OutPath $RepoRoot
    if (Test-Path -LiteralPath $outFull) { throw ('Decision receipt already exists: {0}' -f $outFull) }
    $now = [datetimeoffset]::UtcNow
    $decisionObject = [ordered]@{
        schema_version = 1
        decision_id = 'decision-{0}-{1}' -f $Decision, (Get-SkillEvolutionFileHash $requestFull).Substring(0, 16)
        request_id = [string]$Request.request_id
        request_path = $requestFull
        request_hash = Get-SkillEvolutionFileHash $requestFull
        review_type = [string]$Request.review_type
        action = [string]$Request.action
        skill_name = [string]$Request.skill_name
        subject_fingerprint = [string]$Request.subject_fingerprint
        reviewer = $Reviewer
        decision = $Decision
        reviewed_at = $now.ToString('o')
        expires_at = $now.AddHours(2).ToString('o')
        authorization_token = $expectedToken
        cleanup_not_before = if ($Decision -eq 'reject_delete') { $now.ToString('o') } elseif ($Decision -eq 'reject' -and [string]$Request.review_type -eq 'promotion') { $now.AddDays([math]::Max(1, $RetentionDays)).ToString('o') } else { $null }
        candidate_directory = if ([string]$Request.review_type -eq 'promotion') { [string]$Request.subject_path } else { $null }
        disposition = if ($Decision -eq 'approve') { 'approved_exact_current' } elseif ([string]$Request.review_type -eq 'activation') { 'package_remains_cold' } elseif ($Decision -eq 'reject_delete') { 'candidate_delete_authorized' } else { 'candidate_retained' }
        active_writes = 0
        host_writes = 0
        provider_calls = 0
    }
    if ([string]$Request.review_type -eq 'promotion' -and $Decision -eq 'approve') {
        $decisionObject.candidate_fingerprint = [string]$Request.subject_fingerprint
        $decisionObject.baseline_fingerprint = [string]$Request.baseline_fingerprint
        $decisionObject.allowed_paths = @($Request.allowed_paths)
        $decisionObject.evaluation_receipt_hash = [string]$Request.evaluation_hash
    }
    Write-SkillEvolutionJsonAtomic $outFull ([pscustomobject]$decisionObject)
    return [pscustomobject]@{ decision = [pscustomobject]$decisionObject; decision_path = $outFull; decision_hash = Get-SkillEvolutionFileHash $outFull }
}

function Get-SkillEvolutionDesiredActivationConfig($Config, [string]$SkillName, [string]$Action) {
    $clone = ($Config | ConvertTo-Json -Depth 80) | ConvertFrom-Json
    if ($null -eq $clone.skill_projection) { throw 'skills.json has no skill_projection configuration.' }
    $includes = @($clone.skill_projection.managed_link_includes | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
    if ($Action -eq 'enable') { $includes = @($includes + $SkillName | Sort-Object -Unique) }
    elseif ($Action -eq 'refresh') {
        if ($includes -notcontains $SkillName) { throw 'Refresh requires an active managed link include.' }
    }
    elseif ($Action -eq 'retire') {
        if ($includes -notcontains $SkillName) { throw 'Retirement requires an active managed link include.' }
        $includes = @($includes | Where-Object { $_ -ne $SkillName })
        if ($includes.Count -lt 1) { throw 'Retirement cannot remove the final managed_link_includes entry.' }
    }
    else { throw ('Unsupported activation action: {0}' -f $Action) }
    $clone.skill_projection.managed_link_includes = @($includes)
    return [pscustomobject]@{ config = $clone; includes = @($includes); json = ($clone | ConvertTo-Json -Depth 80) }
}

function New-SkillEvolutionActivationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)][string]$RequestPath,
        [Parameter(Mandatory = $true)]$Decision,
        [Parameter(Mandatory = $true)][string]$DecisionPath,
        [string]$RepoRoot = $script:SkillEvolutionRepoRoot
    )
    $requestFull = Assert-SkillEvolutionReportPath $RequestPath $RepoRoot
    $decisionFull = Assert-SkillEvolutionReportPath $DecisionPath $RepoRoot
    try {
        $Request = [System.IO.File]::ReadAllText($requestFull) | ConvertFrom-Json
        $Decision = [System.IO.File]::ReadAllText($decisionFull) | ConvertFrom-Json
    }
    catch { throw ('Activation request or decision cannot be parsed: {0}' -f $_.Exception.Message) }
    $requestValidation = Test-SkillEvolutionReviewRequest $Request $requestFull $RepoRoot
    if (-not $requestValidation.pass -or [string]$Request.review_type -ne 'activation') { throw 'Activation review request is invalid.' }
    if ([string]$Decision.decision -ne 'approve' -or [string]$Decision.request_hash -ne (Get-SkillEvolutionFileHash $requestFull) -or [string]$Decision.request_id -ne [string]$Request.request_id -or [string]$Decision.skill_name -ne [string]$Request.skill_name) { throw 'Activation decision does not approve the exact review request.' }
    if ((Get-SkillEvolutionFileHash $decisionFull) -eq $null) { throw 'Activation decision receipt is missing.' }
    $decisionExpiresAt = ConvertTo-SkillEvolutionRfc3339 $Decision.expires_at
    $expires = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse($decisionExpiresAt, [ref]$expires) -or $expires -le [datetimeoffset]::UtcNow) { throw 'Activation decision is expired.' }
    $configPath = [System.IO.Path]::GetFullPath([string]$Request.config_path)
    $expectedConfig = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'skills.json'
    if ($configPath -ne [System.IO.Path]::GetFullPath($expectedConfig)) { throw 'Activation config target escaped skills.json.' }
    $configRaw = [System.IO.File]::ReadAllText($configPath)
    $config = $configRaw | ConvertFrom-Json
    $desired = Get-SkillEvolutionDesiredActivationConfig $config ([string]$Request.skill_name) ([string]$Request.action)
    $desiredHash = Get-OperationSha256 $desired.json
    $catalogFingerprint = Get-SkillEvolutionCatalogFingerprint $RepoRoot
    $operation = New-OperationPlan -OperationId ('skill-activation-{0}-{1}' -f [string]$Request.action, ([string]$Request.subject_fingerprint).Substring(0, 12)) -Domain skill_lifecycle -Mode apply -CreatedAt ([datetimeoffset]::UtcNow.ToString('o')) -SourceRevision $catalogFingerprint -Targets @([pscustomobject]@{ target_ref = 'skills.json'; path = $configPath; before_hash = [string]$Request.config_hash; desired_hash = $desiredHash; owner = 'skills-manager' }) -Actions @([pscustomobject]@{ type = 'update'; target_ref = 'skills.json'; summary = ('Stage skill {0} action {1}; host projection follows only after clean commit and full gate.' -f [string]$Request.skill_name, [string]$Request.action); risk = 'high'; metadata = [pscustomobject]@{ allowed_paths = @('skills.json'); managed_link_includes = @($desired.includes) } }) -Preconditions @('review_request_exact_current', 'decision_exact_current', 'package_exact_current', 'catalog_exact_current', 'config_exact_current') -Verification @('cold build passes without host projection', 'clean commit and exact-current full gate precede project') -Rollback @('restore only the exact skills.json backup; host projection requires a later controlled project')
    $operation | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject][ordered]@{
        operation_kind = 'activation'
        skill_name = [string]$Request.skill_name
        activation_action = [string]$Request.action
        package_fingerprint = [string]$Request.subject_fingerprint
        catalog_fingerprint = $catalogFingerprint
        config_path = $configPath
        config_before_hash = [string]$Request.config_hash
        config_after_hash = $desiredHash
        desired_managed_link_includes = @($desired.includes)
        request_path = $requestFull
        request_hash = Get-SkillEvolutionFileHash $requestFull
        review_path = $decisionFull
        review_hash = Get-SkillEvolutionFileHash $decisionFull
        review_expires_at = $decisionExpiresAt
        allowed_paths = @('skills.json')
        projection_disposition = 'staged_then_project_after_clean_gate'
        host_mutation = $true
        projection_token = [string]$Request.projection_token
    })
    return $operation
}

function Invoke-SkillEvolutionActivationApply {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)][string]$Token, [Parameter(Mandatory = $true)][string]$ReceiptPath, [string]$RepoRoot = $script:SkillEvolutionRepoRoot)
    $life = $Plan.lifecycle
    $expectedToken = Get-SkillEvolutionReviewToken activation ([string]$life.activation_action)
    if ($Token -cne $expectedToken) { throw ('Activation apply requires {0}.' -f $expectedToken) }
    $contract = Test-OperationPlanContract $Plan
    if (-not $contract.pass -or [string]$Plan.domain -ne 'skill_lifecycle' -or [string]$life.operation_kind -ne 'activation') { throw ('Activation plan contract is invalid: {0}' -f (@($contract.findings.code) -join ',')) }
    $skillName = [string]$life.skill_name
    $targetState = Get-SkillEvolutionTargetState $RepoRoot $skillName
    if (-not $targetState.exists -or -not $targetState.pass -or $targetState.fingerprint -ne [string]$life.package_fingerprint) { throw 'Activation package drifted before apply.' }
    $catalogFingerprint = Get-SkillEvolutionCatalogFingerprint $RepoRoot
    if ($catalogFingerprint -ne [string]$life.catalog_fingerprint -or [string]$Plan.source_revision -ne $catalogFingerprint) { throw 'Activation catalog drifted before apply.' }
    $configPath = [System.IO.Path]::GetFullPath([string]$life.config_path)
    $expectedConfig = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot 'skills.json'))
    if ($configPath -ne $expectedConfig -or [System.IO.Path]::GetFullPath([string]$Plan.targets[0].path) -ne $expectedConfig) { throw 'Activation target escaped skills.json.' }
    if ((Get-SkillEvolutionFileHash $configPath) -ne [string]$life.config_before_hash -or [string]$Plan.targets[0].before_hash -ne [string]$life.config_before_hash -or [string]$Plan.targets[0].desired_hash -ne [string]$life.config_after_hash) { throw 'Activation config drifted before apply.' }
    $requestPath = Assert-SkillEvolutionReportPath ([string]$life.request_path) $RepoRoot
    $reviewPath = Assert-SkillEvolutionReportPath ([string]$life.review_path) $RepoRoot
    if ((Get-SkillEvolutionFileHash $requestPath) -ne [string]$life.request_hash -or (Get-SkillEvolutionFileHash $reviewPath) -ne [string]$life.review_hash) { throw 'Activation request or decision drifted before apply.' }
    try {
        $request = [System.IO.File]::ReadAllText($requestPath) | ConvertFrom-Json
        $decision = [System.IO.File]::ReadAllText($reviewPath) | ConvertFrom-Json
    }
    catch { throw ('Activation request or decision cannot be parsed: {0}' -f $_.Exception.Message) }
    $requestValidation = Test-SkillEvolutionReviewRequest $request $requestPath $RepoRoot
    if (-not $requestValidation.pass) { throw ('Activation request is no longer exact-current: {0}' -f (@($requestValidation.findings.code) -join ',')) }
    $decisionRequestPath = Assert-SkillEvolutionReportPath ([string]$decision.request_path) $RepoRoot
    $expectedToken = Get-SkillEvolutionReviewToken activation ([string]$life.activation_action)
    if ([string]$decision.decision -ne 'approve' -or [string]$decision.review_type -ne 'activation' -or [string]$decision.action -ne [string]$life.activation_action -or [string]$decision.skill_name -ne $skillName -or [string]$decision.subject_fingerprint -ne [string]$life.package_fingerprint -or $decisionRequestPath -ne $requestPath -or [string]$decision.request_hash -ne [string]$life.request_hash -or [string]$decision.authorization_token -cne $expectedToken -or [string]$request.action -ne [string]$life.activation_action -or [string]$request.skill_name -ne $skillName -or [string]$request.subject_fingerprint -ne [string]$life.package_fingerprint -or [string]$request.catalog_fingerprint -ne [string]$life.catalog_fingerprint) { throw 'Activation request or decision semantics do not match the plan.' }
    $expires = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$life.review_expires_at, [ref]$expires) -or $expires -le [datetimeoffset]::UtcNow -or (ConvertTo-SkillEvolutionRfc3339 $decision.expires_at) -ne [string]$life.review_expires_at) { throw 'Activation review expired or changed before apply.' }
    try { $configRaw = [System.IO.File]::ReadAllText($configPath); $config = $configRaw | ConvertFrom-Json }
    catch { throw ('Activation config cannot be parsed: {0}' -f $_.Exception.Message) }
    $desired = Get-SkillEvolutionDesiredActivationConfig $config $skillName ([string]$life.activation_action)
    if ((Get-OperationSha256 $desired.json) -ne [string]$life.config_after_hash -or (@($desired.includes) -join '|') -ne (@($life.desired_managed_link_includes) -join '|')) { throw 'Activation desired config no longer matches the plan.' }
    $receiptFull = Assert-SkillEvolutionReportPath $ReceiptPath $RepoRoot
    if (Test-Path -LiteralPath $receiptFull) { throw ('Activation receipt already exists: {0}' -f $receiptFull) }
    $backupPath = Join-Path (Split-Path -Parent $receiptFull) ('backup\skills.json.{0}.bak' -f ([guid]::NewGuid().ToString('N')))
    Write-SkillEvolutionTextAtomic $backupPath $configRaw
    $started = [datetimeoffset]::UtcNow.ToString('o')
    try {
        Write-SkillEvolutionTextAtomic $configPath $desired.json
        $afterHash = Get-SkillEvolutionFileHash $configPath
        if ($afterHash -ne [string]$life.config_after_hash) { throw 'Activation config hash mismatch after write.' }
        $receipt = New-OperationReceipt -OperationId ([string]$Plan.operation_id) -Status applied -StartedAt $started -CompletedAt ([datetimeoffset]::UtcNow.ToString('o')) -Actions @([pscustomobject]@{ action_id = [string]$Plan.actions[0].action_id; status = 'staged'; target_ref = 'skills.json'; before_hash = [string]$life.config_before_hash; after_hash = $afterHash }) -Backups @([pscustomobject]@{ path = $backupPath; before_hash = [string]$life.config_before_hash }) -Verification ([pscustomobject]@{ static_validated = 'pass'; repo_gates_passed = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }) -Rollback @('restore exact skills.json backup before any later project')
        $receipt | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject][ordered]@{ operation_kind = 'activation'; skill_name = $skillName; activation_action = [string]$life.activation_action; package_fingerprint = [string]$life.package_fingerprint; catalog_fingerprint_before = [string]$life.catalog_fingerprint; catalog_fingerprint_after = Get-SkillEvolutionCatalogFingerprint $RepoRoot; config_path = $configPath; config_before_hash = [string]$life.config_before_hash; config_after_hash = $afterHash; backup_path = $backupPath; request_path = $requestPath; request_hash = [string]$life.request_hash; review_path = $reviewPath; review_hash = [string]$life.review_hash; review_expires_at = [string]$life.review_expires_at; projection_token = [string]$life.projection_token; desired_managed_link_includes = @($life.desired_managed_link_includes); projection_state = 'staged_not_projected'; active_writes = $(if ([string]$life.config_before_hash -eq $afterHash) { 0 } else { 1 }); host_writes = 0; provider_calls = 0; projection_changed = $false })
        Write-SkillEvolutionJsonAtomic $receiptFull $receipt
        return $receipt
    }
    catch {
        Write-SkillEvolutionTextAtomic $configPath $configRaw
        if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force }
        throw
    }
}

function Invoke-SkillEvolutionActivationRollback {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Receipt, [Parameter(Mandatory = $true)][string]$Token, [string]$OutPath, [string]$RepoRoot = $script:SkillEvolutionRepoRoot)
    if ($Token -cne 'ROLLBACK_SKILL_ACTIVATION') { throw 'Activation rollback requires ROLLBACK_SKILL_ACTIVATION.' }
    $life = $Receipt.lifecycle
    if ([string]$Receipt.status -ne 'applied' -or [string]$life.operation_kind -ne 'activation' -or [string]$life.projection_state -ne 'staged_not_projected') { throw 'Only a staged, not-projected activation receipt can be rolled back.' }
    $configPath = [System.IO.Path]::GetFullPath([string]$life.config_path)
    if ($configPath -ne [System.IO.Path]::GetFullPath((Join-Path $RepoRoot 'skills.json'))) { throw 'Activation rollback target escaped skills.json.' }
    if ((Get-SkillEvolutionFileHash $configPath) -ne [string]$life.config_after_hash) { throw 'Activation config drifted after apply; rollback is fail closed.' }
    $backupPath = [System.IO.Path]::GetFullPath([string]$life.backup_path)
    if (-not (Test-SkillEvolutionPathWithin $backupPath (Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'reports\skill-evolution')) -or (Get-SkillEvolutionFileHash $backupPath) -ne [string]$life.config_before_hash) { throw 'Activation backup is missing, escaped, or drifted.' }
    $before = [System.IO.File]::ReadAllText($backupPath)
    Write-SkillEvolutionTextAtomic $configPath $before
    if ((Get-SkillEvolutionFileHash $configPath) -ne [string]$life.config_before_hash) { throw 'Activation rollback restoration hash mismatch.' }
    $rolled = New-OperationReceipt -OperationId ([string]$Receipt.operation_id) -Status rolled_back -StartedAt ([datetimeoffset]::UtcNow.ToString('o')) -CompletedAt ([datetimeoffset]::UtcNow.ToString('o')) -Actions @([pscustomobject]@{ action_id = 'skill-activation-rollback'; status = 'rolled_back'; target_ref = 'skills.json'; restored_hash = [string]$life.config_before_hash }) -Verification ([pscustomobject]@{ static_validated = 'pass'; repo_gates_passed = 'not_run'; host_loaded = 'not_run'; live_accepted = 'not_run' }) -Rollback @('host projection was not changed')
    $rolled | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject]@{ operation_kind = 'activation_rollback'; skill_name = [string]$life.skill_name; activation_action = [string]$life.activation_action; projection_changed = $false; host_writes = 0; active_writes = 1 })
    if (-not [string]::IsNullOrWhiteSpace($OutPath)) { $outFull = Assert-SkillEvolutionReportPath $OutPath $RepoRoot; Write-SkillEvolutionJsonAtomic $outFull $rolled }
    return $rolled
}

function Invoke-SkillEvolutionRejectedCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Decision, [Parameter(Mandatory = $true)][string]$Token, [Parameter(Mandatory = $true)][string]$OutPath, [string]$RepoRoot = $script:SkillEvolutionRepoRoot)
    if ($Token -cne 'DELETE_REJECTED_SKILL_CANDIDATE') { throw 'Rejected candidate cleanup requires DELETE_REJECTED_SKILL_CANDIDATE.' }
    if ([string]$Decision.review_type -ne 'promotion' -or [string]$Decision.decision -notin @('reject', 'reject_delete')) { throw 'Cleanup requires a rejected promotion decision.' }
    $requestPath = Assert-SkillEvolutionReportPath ([string]$Decision.request_path) $RepoRoot
    if ((Get-SkillEvolutionFileHash $requestPath) -ne [string]$Decision.request_hash) { throw 'Rejected candidate review request drifted before cleanup.' }
    try { $request = [System.IO.File]::ReadAllText($requestPath) | ConvertFrom-Json }
    catch { throw 'Rejected candidate review request is invalid JSON.' }
    if ([string]$request.review_type -ne 'promotion' -or [string]$request.skill_name -ne [string]$Decision.skill_name -or [string]$request.subject_path -ne [string]$Decision.candidate_directory -or [string]$request.subject_fingerprint -ne [string]$Decision.subject_fingerprint) { throw 'Rejected cleanup decision does not bind the original promotion request.' }
    $notBefore = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Decision.cleanup_not_before, [ref]$notBefore) -or $notBefore -gt [datetimeoffset]::UtcNow) { throw 'Rejected candidate retention period has not expired.' }
    $candidate = [System.IO.Path]::GetFullPath([string]$Decision.candidate_directory)
    $reportsRoot = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'reports\skill-evolution'
    if (-not (Test-SkillEvolutionPathWithin $candidate $reportsRoot)) { throw 'Rejected candidate escaped reports/skill-evolution.' }
    $state = Get-SkillEvolutionPackageState $candidate
    if (-not $state.pass -or $state.fingerprint -ne [string]$Decision.subject_fingerprint) { throw 'Rejected candidate drifted before cleanup.' }
    $targetState = Get-SkillEvolutionTargetState $RepoRoot ([string]$Decision.skill_name)
    if ($targetState.exists -and $targetState.fingerprint -eq $state.fingerprint) { throw 'Candidate fingerprint is present in the promoted source; cleanup is blocked.' }
    $outFull = Assert-SkillEvolutionReportPath $OutPath $RepoRoot
    if (Test-SkillEvolutionPathWithin $outFull $candidate) { throw 'Cleanup receipt cannot be written inside the deleted candidate.' }
    if (Test-Path -LiteralPath $outFull) { throw ('Cleanup receipt already exists: {0}' -f $outFull) }
    $started = [datetimeoffset]::UtcNow.ToString('o')
    Remove-Item -LiteralPath $candidate -Recurse -Force
    if (Test-Path -LiteralPath $candidate) { throw 'Rejected candidate cleanup did not remove the candidate directory.' }
    $receipt = [pscustomobject][ordered]@{ schema_version = 1; status = 'cleaned'; started_at = $started; completed_at = [datetimeoffset]::UtcNow.ToString('o'); skill_name = [string]$Decision.skill_name; candidate_directory = $candidate; candidate_fingerprint = [string]$Decision.subject_fingerprint; active_writes = 0; report_writes = 1; host_writes = 0; provider_calls = 0; protected_roots = @('overrides/custom', 'skills.json', 'agent', 'user_skill_root', 'host_projection') }
    Write-SkillEvolutionJsonAtomic $outFull $receipt
    return $receipt
}

function Test-SkillEvolutionProjectionAuthorization {
    param($ActivationReceipt, [string]$DecisionPath, [string]$Token, [string]$RepoRoot = $script:SkillEvolutionRepoRoot)
    $findings = [System.Collections.Generic.List[object]]::new()
    $life = $ActivationReceipt.lifecycle
    $decision = $null
    if ($Token -cne 'PROJECT_SKILL_TO_HOST') { $findings.Add((New-OperationFinding 'projection_token_invalid' 'error' '$.token' 'Projection requires PROJECT_SKILL_TO_HOST.')) | Out-Null }
    if ([string]$ActivationReceipt.status -ne 'applied' -or [string]$life.operation_kind -ne 'activation' -or [string]$life.projection_state -ne 'staged_not_projected') { $findings.Add((New-OperationFinding 'activation_receipt_invalid' 'error' '$.receipt' 'Projection requires a staged activation receipt.')) | Out-Null }
    try {
        $decisionFull = Assert-SkillEvolutionReportPath $DecisionPath $RepoRoot
        $expectedDecisionFull = Assert-SkillEvolutionReportPath ([string]$life.review_path) $RepoRoot
        if ($decisionFull -ne $expectedDecisionFull) { throw 'path mismatch' }
        if ((Get-SkillEvolutionFileHash $decisionFull) -ne [string]$life.review_hash) { throw 'hash mismatch' }
        $decision = [System.IO.File]::ReadAllText($decisionFull) | ConvertFrom-Json
    }
    catch { $findings.Add((New-OperationFinding 'projection_decision_path_invalid' 'error' '$.decision_path' 'Projection decision path must be the exact reviewed receipt path with the exact hash.')) | Out-Null }
    if ($null -eq $decision -or [string]$decision.decision -ne 'approve' -or [string]$decision.review_type -ne 'activation' -or [string]$decision.skill_name -ne [string]$life.skill_name -or [string]$decision.action -ne [string]$life.activation_action -or [string]$decision.subject_fingerprint -ne [string]$life.package_fingerprint) { $findings.Add((New-OperationFinding 'projection_decision_invalid' 'error' '$.decision' 'Projection decision does not approve the activation receipt.')) | Out-Null }
    if ($null -ne $decision -and [string]$decision.request_hash -ne [string]$life.request_hash) { $findings.Add((New-OperationFinding 'projection_request_binding_invalid' 'error' '$.request_hash' 'Projection decision does not bind the activation request.')) | Out-Null }
    try {
        $requestFull = Assert-SkillEvolutionReportPath ([string]$life.request_path) $RepoRoot
        $decisionRequestFull = Assert-SkillEvolutionReportPath ([string]$decision.request_path) $RepoRoot
        if ($decisionRequestFull -ne $requestFull -or (Get-SkillEvolutionFileHash $requestFull) -ne [string]$life.request_hash) { throw 'request mismatch' }
    }
    catch { $findings.Add((New-OperationFinding 'projection_request_path_invalid' 'error' '$.request_path' 'Projection request path/hash binding is invalid.')) | Out-Null }
    $expires = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$life.review_expires_at, [ref]$expires) -or $expires -le [datetimeoffset]::UtcNow -or $null -eq $decision -or (ConvertTo-SkillEvolutionRfc3339 $decision.expires_at) -ne [string]$life.review_expires_at) { $findings.Add((New-OperationFinding 'projection_review_expired' 'error' '$.review_expires_at' 'Activation authorization expired or changed before projection.')) | Out-Null }
    if ((Get-SkillEvolutionFileHash (Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'skills.json')) -ne [string]$life.config_after_hash) { $findings.Add((New-OperationFinding 'projection_config_drift' 'error' '$.config_after_hash' 'skills.json drifted before projection.')) | Out-Null }
    $target = Get-SkillEvolutionTargetState $RepoRoot ([string]$life.skill_name)
    if (-not $target.exists -or -not $target.pass -or $target.fingerprint -ne [string]$life.package_fingerprint) { $findings.Add((New-OperationFinding 'projection_package_drift' 'error' '$.package_fingerprint' 'Skill package drifted before projection.')) | Out-Null }
    if ((Get-SkillEvolutionCatalogFingerprint $RepoRoot) -ne [string]$life.catalog_fingerprint_after) { $findings.Add((New-OperationFinding 'projection_catalog_drift' 'error' '$.catalog_fingerprint_after' 'Catalog drifted after activation staging.')) | Out-Null }
    return [pscustomobject]@{ pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0); findings = @($findings.ToArray()); decision = $decision }
}
