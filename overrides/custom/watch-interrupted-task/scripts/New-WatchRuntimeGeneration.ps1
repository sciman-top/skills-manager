[CmdletBinding()]
param(
    [string]$InstalledHookPath = '',
    [string]$InstalledPolicyPath = '',
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'WatchPromptCommon.ps1')

$repoRoot = Get-WatchRepositoryRoot
$sourceCommit = Invoke-WatchGitText -RepositoryRoot $repoRoot -Arguments @('rev-parse', 'HEAD')
if ($sourceCommit -notmatch '^[0-9a-f]{40,64}$') { throw 'head_commit_invalid' }
$null = Invoke-WatchGitText -RepositoryRoot $repoRoot -Arguments @('cat-file', '-e', "$sourceCommit^{commit}")

& git -C $repoRoot diff --quiet --ignore-submodules --
if ($LASTEXITCODE -ne 0) { throw 'tracked_worktree_dirty' }
& git -C $repoRoot diff --cached --quiet --ignore-submodules --
if ($LASTEXITCODE -ne 0) { throw 'tracked_index_dirty' }

$committedHashes = Get-WatchCommittedSourceHashes -RepositoryRoot $repoRoot -Commit $sourceCommit
foreach ($relativePath in @($committedHashes.Keys)) {
    $currentPath = Join-Path $repoRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.File]::Exists($currentPath)) { throw "source_file_missing:$relativePath" }
    $committedObjectId = Invoke-WatchGitText -RepositoryRoot $repoRoot -Arguments @('rev-parse', "$sourceCommit`:$relativePath")
    $currentObjectId = Invoke-WatchGitText -RepositoryRoot $repoRoot -Arguments @('hash-object', "--path=$relativePath", $currentPath)
    if ($currentObjectId -cne $committedObjectId) { throw "source_blob_mismatch:$relativePath" }
}

$generationId = Get-WatchRuntimeGenerationId -RepositoryRoot $repoRoot -Commit $sourceCommit -CommittedOnly
$targetGenerator = Join-Path $PSScriptRoot 'New-WatchHeartbeatPrompt.ps1'
$fleetGenerator = Join-Path $PSScriptRoot 'New-WatchFleetSupervisorPrompt.ps1'
$target = (& $targetGenerator -TargetThreadId 'runtime-generation-probe' -AsJson) | ConvertFrom-Json -ErrorAction Stop
$shutdownTarget = (& $targetGenerator -TargetThreadId 'runtime-generation-probe' -ShutdownManaged -AsJson) | ConvertFrom-Json -ErrorAction Stop
$fleet = (& $fleetGenerator -SupervisorThreadId 'runtime-generation-probe' -AsJson) | ConvertFrom-Json -ErrorAction Stop
$shutdownFleet = (& $fleetGenerator -SupervisorThreadId 'runtime-generation-probe' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json -ErrorAction Stop
$hookRelativePath = 'scripts/hooks/block-cross-thread-send.ps1'
$policyRelativePath = 'scripts/hooks/CrossThreadGuardPolicy.ps1'
$hookSourceHash = [string]$committedHashes[$hookRelativePath]
$policySourceHash = [string]$committedHashes[$policyRelativePath]
$installedHookHash = if (-not [string]::IsNullOrWhiteSpace($InstalledHookPath) -and (Test-Path -LiteralPath $InstalledHookPath -PathType Leaf)) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $InstalledHookPath).Hash.ToLowerInvariant()
}
else { '' }
$installedPolicyHash = if (-not [string]::IsNullOrWhiteSpace($InstalledPolicyPath) -and (Test-Path -LiteralPath $InstalledPolicyPath -PathType Leaf)) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $InstalledPolicyPath).Hash.ToLowerInvariant()
}
else { '' }

$bindingRows = [System.Collections.Generic.List[string]]::new()
$bindingRows.Add("watch_runtime_generation_id=$generationId") | Out-Null
$bindingRows.Add("source_commit=$($sourceCommit.ToLowerInvariant())") | Out-Null
foreach ($path in @($committedHashes.Keys | Sort-Object)) { $bindingRows.Add("source:$path=$($committedHashes[$path])") | Out-Null }
$promptBindings = [ordered]@{
    target_prompt_sha256 = [string]$target.prompt_sha256
    shutdown_target_prompt_sha256 = [string]$shutdownTarget.prompt_sha256
    fleet_prompt_sha256 = [string]$fleet.prompt_sha256
    fleet_shutdown_prompt_sha256 = [string]$shutdownFleet.prompt_sha256
    installed_hook_sha256 = $installedHookHash
    installed_policy_sha256 = $installedPolicyHash
}
foreach ($entry in $promptBindings.GetEnumerator()) { $bindingRows.Add("$($entry.Key)=$($entry.Value)") | Out-Null }

$result = [pscustomobject][ordered]@{
    schema_version = 2
    watch_runtime_generation_id = $generationId
    source_commit = $sourceCommit.ToLowerInvariant()
    policy_revision = $script:WatchRuntimePolicyRevision
    repo_clean = $true
    source_blobs_verified = $true
    committed_source_hashes = [pscustomobject]$committedHashes
    target_prompt_sha256 = [string]$target.prompt_sha256
    shutdown_target_prompt_sha256 = [string]$shutdownTarget.prompt_sha256
    fleet_prompt_sha256 = [string]$fleet.prompt_sha256
    fleet_shutdown_prompt_sha256 = [string]$shutdownFleet.prompt_sha256
    hook_source_sha256 = $hookSourceHash
    hook_policy_source_sha256 = $policySourceHash
    installed_hook_sha256 = $installedHookHash
    installed_policy_sha256 = $installedPolicyHash
    generation_binding_sha256 = Get-WatchPromptSha256 -Body ([string]::Join("`n", $bindingRows.ToArray()))
}

if ($AsJson) { $result | ConvertTo-Json -Depth 10 -Compress } else { $result }
