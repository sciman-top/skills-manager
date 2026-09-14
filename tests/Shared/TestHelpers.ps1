# Shared test helpers dot-sourced from BeforeAll in unit and E2E containers.
# Keep these dependency-free: helpers may run before skills.ps1 is loaded and
# must only rely on cmdlets and loaded test-scope state.

function Get-TestSha256([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Get-TestPackageSha256([string]$SkillDirectory) {
    $base = [IO.Path]::GetFullPath($SkillDirectory).TrimEnd('\', '/')
    $parts = foreach ($file in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($base.Length).TrimStart('\', '/').Replace('\', '/')
        if ($relative -eq 'catalog.json') { continue }
        '{0}|{1}' -f $relative, ([string](Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash).ToLowerInvariant()
    }
    return Get-TestSha256 ($parts -join "`n")
}

function Get-FunctionBody {
    param(
        [string]$Text,
        [string]$FunctionName
    )

    $start = $Text.IndexOf("function $FunctionName {")
    if ($start -lt 0) {
        throw "Failed to locate function $FunctionName"
    }

    $cursor = $Text.IndexOf("{", $start)
    if ($cursor -lt 0) {
        throw "Failed to locate opening brace for $FunctionName"
    }

    $depth = 0
    for ($i = $cursor; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($ch -eq "{") {
            $depth++
        }
        elseif ($ch -eq "}") {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $i - $start + 1)
            }
        }
    }

    throw "Failed to extract function body for $FunctionName"
}

function New-AuditValidatedWorkflowReceiptFixture([string]$RecommendationsPath, [string]$RunId = 'r-test') {
    $resolved = [IO.Path]::GetFullPath($RecommendationsPath)
    $state = Get-AuditWorkflowInputState $resolved
    $snapshotPath = Join-Path (Split-Path -Parent $resolved) 'snapshot.json'
    Need (Test-Path -LiteralPath $snapshotPath -PathType Leaf) ("fixture 依赖 snapshot.json 先于 receipt 存在：{0}" -f $snapshotPath)
    $receipt = [pscustomobject][ordered]@{
        schema_version = 1
        workflow = 'recommendations_validate_dry_run'
        generated_at = [datetimeoffset]::UtcNow.ToString('o')
        success = $true
        persisted = $false
        run_id = $RunId
        recommendations_path = $resolved
        recommendations_sha256 = Get-FileContentHash $resolved
        stages = [pscustomobject]@{
            recommendations_validation = [pscustomobject]@{ status = 'passed' }
            preflight = [pscustomobject]@{ status = 'passed' }
            dry_run = [pscustomobject]@{ status = 'passed' }
            input_stability = [pscustomobject]@{ status = 'passed' }
        }
        scan = [pscustomobject]@{ snapshot_sha256 = Get-FileContentHash $snapshotPath }
        input_stability = [pscustomobject]@{ matched = $true; after_dry_run = $state }
    }
    Write-AuditReceiptSection $resolved "workflow" $receipt | Out-Null
}

function Set-TestWorkspace([string]$root) {
        $values = @{
            Root = $root
            CfgPath = Join-Path $root "skills.json"
            LogPath = Join-Path $root "build.log"
            VendorDir = Join-Path $root "vendor"
            AgentDir = Join-Path $root "agent"
            OverridesDir = Join-Path $root "overrides"
            ManualDir = Join-Path $root "manual"
            ImportDir = Join-Path $root "imports"
            DryRun = $false
        }
        foreach ($entry in $values.GetEnumerator()) {
            Set-Variable -Name $entry.Key -Scope 1 -Value $entry.Value
            Set-Variable -Name $entry.Key -Scope Script -Value $entry.Value
            Set-Variable -Name $entry.Key -Scope Global -Value $entry.Value
        }
        EnsureDir $VendorDir
        EnsureDir $AgentDir
        EnsureDir $OverridesDir
        EnsureDir $ManualDir
        EnsureDir $ImportDir
    }
