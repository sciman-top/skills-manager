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
