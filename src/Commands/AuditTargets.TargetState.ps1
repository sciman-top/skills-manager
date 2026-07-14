function Get-AuditTargetRepoScans([string]$recommendationDir) {
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $singlePath = Join-Path $recommendationDir "repo-scan.json"
    if (Test-Path -LiteralPath $singlePath -PathType Leaf) {
        try { return @((Get-ContentUtf8 $singlePath | ConvertFrom-Json)) }
        catch { throw ("repo-scan JSON 解析失败：{0}" -f $_.Exception.Message) }
    }

    $multiPath = Join-Path $recommendationDir "repo-scans.json"
    if (-not (Test-Path -LiteralPath $multiPath -PathType Leaf)) { return @() }
    try { $bundle = Get-ContentUtf8 $multiPath | ConvertFrom-Json }
    catch { throw ("repo-scans JSON 解析失败：{0}" -f $_.Exception.Message) }
    $scans = Get-CfgObjectProperty $bundle "scans"
    if ($null -eq $scans) { return @() }
    return @($scans)
}

function Get-AuditTargetRepoStateFingerprint($targets) {
    $pairs = @()
    foreach ($target in @($targets)) {
        if ($null -eq $target) { continue }
        $pairs += ("{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}" -f
            [string]$target.name,
            [string]$target.resolved_path,
            ([bool]$target.exists).ToString().ToLowerInvariant(),
            ([bool]$target.is_repo).ToString().ToLowerInvariant(),
            [string]$target.branch,
            [string]$target.commit,
            ([bool]$target.dirty).ToString().ToLowerInvariant(),
            [string]$target.status_count,
            [string]$target.status_fingerprint)
    }
    return (Get-AuditFingerprintFromVendorFromPairs $pairs $true)
}

function Get-AuditTargetRepoSnapshotState([string]$recommendationDir) {
    $targets = @()
    foreach ($scan in @(Get-AuditTargetRepoScans $recommendationDir)) {
        $targetData = Get-CfgObjectProperty $scan "target"
        $gitData = Get-CfgObjectProperty $scan "git"
        $name = [string](Get-CfgObjectProperty $targetData "name")
        $resolvedPath = [string](Get-CfgObjectProperty $targetData "resolved_path")
        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            $inputPath = [string](Get-CfgObjectProperty $targetData "path")
            if (-not [string]::IsNullOrWhiteSpace($inputPath)) { $resolvedPath = Resolve-AuditTargetPath $inputPath }
        }
        $statusFingerprint = [string](Get-CfgObjectProperty $gitData "status_fingerprint")
        $statusCountValue = Get-CfgObjectProperty $gitData "status_count"
        $targets += [pscustomobject]([ordered]@{
                name = $name
                resolved_path = $resolvedPath
                exists = [bool](Get-CfgObjectProperty $targetData "exists")
                is_repo = [bool](Get-CfgObjectProperty $gitData "is_repo")
                branch = [string](Get-CfgObjectProperty $gitData "branch")
                commit = [string](Get-CfgObjectProperty $gitData "commit")
                dirty = [bool](Get-CfgObjectProperty $gitData "dirty")
                status_count = if ($null -eq $statusCountValue) { -1 } else { [int]$statusCountValue }
                status_fingerprint = $statusFingerprint
                worktree_fingerprint_available = (-not [string]::IsNullOrWhiteSpace($statusFingerprint))
                automatic_evidence_count = [int](Get-CfgObjectProperty $gitData "automatic_evidence_count")
                automatic_evidence_fingerprint = [string](Get-CfgObjectProperty $gitData "automatic_evidence_fingerprint")
            })
    }
    return [pscustomobject]([ordered]@{
            captured_from = "repo_scan"
            target_count = @($targets).Count
            fingerprint = Get-AuditTargetRepoStateFingerprint $targets
            targets = @($targets)
        })
}

function Get-AuditTargetRepoLiveState($snapshotState) {
    $targets = @()
    foreach ($snapshotTarget in @($snapshotState.targets)) {
        $resolvedPath = [string]$snapshotTarget.resolved_path
        $exists = Test-Path -LiteralPath $resolvedPath -PathType Container
        $git = Get-AuditGitInfo $resolvedPath
        $targets += [pscustomobject]([ordered]@{
                name = [string]$snapshotTarget.name
                resolved_path = $resolvedPath
                exists = [bool]$exists
                is_repo = [bool]$git.is_repo
                branch = [string]$git.branch
                commit = [string]$git.commit
                dirty = [bool]$git.dirty
                status_count = [int]$git.status_count
                status_fingerprint = [string]$git.status_fingerprint
                worktree_fingerprint_available = $true
                automatic_evidence_count = [int]$git.automatic_evidence_count
                automatic_evidence_fingerprint = [string]$git.automatic_evidence_fingerprint
            })
    }
    return [pscustomobject]([ordered]@{
            captured_at = (Get-Date).ToString("o")
            target_count = @($targets).Count
            fingerprint = Get-AuditTargetRepoStateFingerprint $targets
            targets = @($targets)
        })
}

function Get-AuditTargetRepoStaleness($snapshotState, $liveState) {
    $drifted = @()
    $liveByName = @{}
    foreach ($target in @($liveState.targets)) { $liveByName[[string]$target.name] = $target }
    foreach ($snapshotTarget in @($snapshotState.targets)) {
        $name = [string]$snapshotTarget.name
        $changes = New-Object System.Collections.Generic.List[string]
        $liveTarget = $liveByName[$name]
        if ($null -eq $liveTarget) {
            $changes.Add("missing") | Out-Null
        }
        else {
            if ([bool]$snapshotTarget.exists -ne [bool]$liveTarget.exists) { $changes.Add("exists") | Out-Null }
            if ([bool]$snapshotTarget.is_repo -ne [bool]$liveTarget.is_repo) { $changes.Add("is_repo") | Out-Null }
            if ([string]$snapshotTarget.branch -ne [string]$liveTarget.branch) { $changes.Add("branch") | Out-Null }
            if ([string]$snapshotTarget.commit -ne [string]$liveTarget.commit) { $changes.Add("head") | Out-Null }
            if ([bool]$snapshotTarget.dirty -ne [bool]$liveTarget.dirty) { $changes.Add("dirty") | Out-Null }
            if ([bool]$snapshotTarget.worktree_fingerprint_available -and
                [string]$snapshotTarget.status_fingerprint -ne [string]$liveTarget.status_fingerprint) {
                $changes.Add("worktree") | Out-Null
            }
        }
        if ($changes.Count -gt 0) {
            $drifted += [pscustomobject]([ordered]@{
                    name = $name
                    changes = @($changes)
                    snapshot = $snapshotTarget
                    live = $liveTarget
                })
        }
    }
    foreach ($liveTarget in @($liveState.targets)) {
        if (@($snapshotState.targets | Where-Object { [string]$_.name -eq [string]$liveTarget.name }).Count -eq 0) {
            $drifted += [pscustomobject]([ordered]@{
                    name = [string]$liveTarget.name
                    changes = @("unexpected")
                    snapshot = $null
                    live = $liveTarget
                })
        }
    }
    return [pscustomobject]([ordered]@{
            is_stale = (@($drifted).Count -gt 0)
            matched = (@($drifted).Count -eq 0)
            snapshot_fingerprint = [string]$snapshotState.fingerprint
            live_fingerprint = [string]$liveState.fingerprint
            drifted_targets = @($drifted)
        })
}
