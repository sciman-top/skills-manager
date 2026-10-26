function Get-AuditTargetRepoScans([string]$recommendationDir) {
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $snapshot = Read-AuditSnapshot $recommendationDir
    $scans = Get-CfgObjectProperty $snapshot "target_scans"
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
        # 从顶层 scan 一次性取出对象，保留 scan_coverage 的包装与 confidence_ceiling。
        $scanCoverage = Get-CfgObjectProperty $scan "scan_coverage"
        $confidenceCeiling = [string](Get-CfgObjectProperty $scanCoverage "confidence_ceiling")
        $dirtySkip = Get-CfgObjectProperty $scan "dirty_skip"
        $dirtySkipDeclared = ($null -ne $dirtySkip -and
            [string](Get-CfgObjectProperty $dirtySkip "scope") -eq "whole_repository" -and
            [string](Get-CfgObjectProperty $dirtySkip "reason") -eq "worktree_dirty" -and
            -not [string]::IsNullOrWhiteSpace([string](Get-CfgObjectProperty $dirtySkip "declared_at")))
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
                scan_skipped_dirty = ($confidenceCeiling -eq "skipped_dirty" -and $dirtySkipDeclared)
            })
    }
    return [pscustomobject]([ordered]@{
            captured_from = "snapshot.json"
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
        # Get-AuditGitInfo 将每条 Git 命令绑定到目标路径；不依赖切换 cwd，
        # 这样目标仓在扫描后被移走时仍能返回 exists=false 并报告 stale。
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
            })
    }
    return [pscustomobject]([ordered]@{
            captured_at = (Get-Date).ToString("o")
            target_count = @($targets).Count
            fingerprint = Get-AuditTargetRepoStateFingerprint $targets
            targets = @($targets)
        })
}

function Get-AuditTargetRepoStaleness($snapshotState, $liveState, [switch]$AcceptDeclaredDirtyAtScan) {
    $drifted = @()
    $ignoredSnapshotChanges = @()
    $acceptedSkippedDirty = @()
    $idleSkippedDirty = @()
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
            if (([string]$snapshotTarget.commit) -cne ([string]$liveTarget.commit)) { $changes.Add("head") | Out-Null }
            if ([bool]$snapshotTarget.dirty -ne [bool]$liveTarget.dirty) { $changes.Add("dirty") | Out-Null }
            if ([bool]$snapshotTarget.worktree_fingerprint_available -and
                ([string]$snapshotTarget.status_fingerprint) -cne ([string]$liveTarget.status_fingerprint)) {
                $changes.Add("worktree") | Out-Null
            }
            if ([bool]$AcceptDeclaredDirtyAtScan -and [bool]$snapshotTarget.scan_skipped_dirty) {
                $ignoredWorktreeChanges = @($changes | Where-Object { $_ -eq "dirty" -or $_ -eq "worktree" })
                $unexpectedChanges = @($changes | Where-Object { $_ -ne "dirty" -and $_ -ne "worktree" })
                if ($unexpectedChanges.Count -eq 0 -and $ignoredWorktreeChanges.Count -eq 0) {
                    $idleSkippedDirty += $name
                }
                elseif ($unexpectedChanges.Count -eq 0) {
                    $acceptedSkippedDirty += [pscustomobject]([ordered]@{
                            name = $name
                            changes = @($ignoredWorktreeChanges)
                            snapshot_confidence_ceiling = "skipped_dirty"
                        })
                    $ignoredSnapshotChanges += [pscustomobject]([ordered]@{
                            name = $name
                            snapshot = $snapshotTarget
                            live = $liveTarget
                            changes = @($ignoredWorktreeChanges)
                        })
                }
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
    $eligibleSkippedDirtyNames = @{}
    if ([bool]$AcceptDeclaredDirtyAtScan) {
        foreach ($target in @($snapshotState.targets | Where-Object { [bool]$_.scan_skipped_dirty })) { $eligibleSkippedDirtyNames[[string]$target.name] = $true }
        $drifted = @($drifted | Where-Object {
                if (-not $eligibleSkippedDirtyNames.ContainsKey([string]$_.name)) {
                    $_; return
                }
                # accepted 前的 dirty/worktree 差异已显式接受；之后出现的 HEAD
                # 或其他非工作树变化仍在这里保留并阻断。
                $unaccepted = @($_.changes | Where-Object { $_ -ne "dirty" -and $_ -ne "worktree" })
                if ($unaccepted.Count -eq 0) { return }
                [pscustomobject]([ordered]@{
                        name = [string]$_.name
                        changes = @($unaccepted)
                        snapshot = $_.snapshot
                        live = $_.live
                    })
            })
    }
    return [pscustomobject]([ordered]@{
            # 已声明的 dirty/worktree 差异由 accepted 记录并保留原文；
            # is_stale 只表示未被接受的 HEAD/branch/内容变化。
            # snapshot_changes 表示扫描后内容已变化；preflight 必须拒绝它。
            is_stale = (@($drifted).Count -gt 0)
            matched = (@($drifted).Count -eq 0 -and @($ignoredSnapshotChanges).Count -eq 0)
            snapshot_changes = @($ignoredSnapshotChanges)
            snapshot_fingerprint = [string]$snapshotState.fingerprint
            live_fingerprint = [string]$liveState.fingerprint
            accept_declared_dirty_at_scan = [bool]$AcceptDeclaredDirtyAtScan
            accept_declared_dirty_scope = if ([bool]$AcceptDeclaredDirtyAtScan) { "current_snapshot_only" } else { "none" }
            previous_dry_run_matched = ((@($drifted).Count -eq 0) -and (@($ignoredSnapshotChanges).Count -eq 0))
            accepted_skipped_dirty_targets = @($acceptedSkippedDirty)
            idle_skipped_dirty_targets = @($idleSkippedDirty)
            drifted_targets = @($drifted)
        })
}
