function Should-ForceCleanTarget($cfg, $SkipForceClean, [string]$kind, [string]$name) {
    if ($null -eq $cfg -or -not $cfg.update_force) { return $false }
    if ($null -eq $SkipForceClean) { return $true }
    $key = "{0}|{1}" -f $kind, $name
    return (-not $SkipForceClean.ContainsKey($key))
}

function Get-UpdateParallelism($cfg) {
    $n = 1
    if ($null -ne $cfg -and $cfg.PSObject.Properties.Match("update_parallelism").Count -gt 0) {
        try { $n = [int]$cfg.update_parallelism } catch { $n = 1 }
    }
    if ($n -lt 1) { $n = 1 }
    return $n
}

function Test-WindowsInvalidPathIssue([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) { return $false }
    if ($message -notmatch "invalid path") { return $false }
    return ($message -match "git\s+(pull|checkout|reset)")
}

function Invoke-ParallelGitPrefetch($cfg, [int]$Parallelism = 1) {
    if ($DryRun) { return }
    if ($Parallelism -le 1) { return }
    if (-not (Get-Command Start-Job -ErrorAction SilentlyContinue)) { return }
    if ($null -eq $cfg) { return }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($v in @($cfg.vendors)) {
        $p = VendorPath $v.name
        if (Test-Path $p) { $paths.Add($p) | Out-Null }
    }
    foreach ($i in @($cfg.imports)) {
        if ($i.mode -ne "manual") { continue }
        $p = Join-Path $ImportDir $i.name
        if (Test-Path $p) { $paths.Add($p) | Out-Null }
    }
    $paths = @($paths | Select-Object -Unique)
    if ($paths.Count -eq 0) { return }

    $running = @()
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) {
        while (@($running).Count -ge $Parallelism) {
            $done = Wait-Job -Job $running -Any
            if ($null -eq $done) { break }
            $output = Receive-Job $done -ErrorAction SilentlyContinue
            Remove-Job $done -Force -ErrorAction SilentlyContinue
            $running = @($running | Where-Object { $_.Id -ne $done.Id })
            if ($output -and $output.ok -eq $false) { $errors.Add([string]$output.msg) | Out-Null }
        }
        $job = Start-Job -ScriptBlock {
            param($repoPath)
            try {
                $prevErrorActionPreference = $ErrorActionPreference
                try {
                    $ErrorActionPreference = "Continue"
                    & git -C $repoPath fetch --all --tags 2>$null | Out-Null
                }
                finally {
                    $ErrorActionPreference = $prevErrorActionPreference
                }
                if ($LASTEXITCODE -ne 0) {
                    return [pscustomobject]@{ ok = $false; msg = ("prefetch failed: {0}" -f $repoPath) }
                }
                return [pscustomobject]@{ ok = $true; msg = "" }
            }
            catch {
                return [pscustomobject]@{ ok = $false; msg = ("prefetch exception: {0} -> {1}" -f $repoPath, $_.Exception.Message) }
            }
        } -ArgumentList $p
        $running += $job
    }
    foreach ($j in @($running)) {
        Wait-Job $j | Out-Null
        $output = Receive-Job $j -ErrorAction SilentlyContinue
        Remove-Job $j -Force -ErrorAction SilentlyContinue
        if ($output -and $output.ok -eq $false) { $errors.Add([string]$output.msg) | Out-Null }
    }
    if ($errors.Count -gt 0) {
        Log ("并行预取完成（部分失败 {0} 项，后续将按原流程继续）。" -f $errors.Count) "WARN"
    }
    else {
        Log ("并行预取完成：{0} 个仓库路径（并发={1}）。" -f $paths.Count, $Parallelism)
    }
}

function Get-CurrentRepoCommit([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if (-not (Test-Path $path)) { return $null }
    Push-Location $path
    try {
        return (Invoke-GitCapture @("rev-parse", "HEAD"))
    }
    finally { Pop-Location }
}

function Resolve-RemoteCommit([string]$repo, [string]$ref) {
    $targetRef = if ([string]::IsNullOrWhiteSpace($ref)) { "main" } else { $ref }
    $candidates = @(
        $targetRef,
        ("refs/heads/{0}" -f $targetRef),
        ("refs/tags/{0}^{}" -f $targetRef),
        ("refs/tags/{0}" -f $targetRef)
    )
    foreach ($candidate in $candidates) {
        $line = Invoke-GitCapture @("ls-remote", $repo, $candidate)
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match "^[0-9a-fA-F]{40}") {
            return (($line -split "\s+")[0]).Trim()
        }
    }
    return $null
}

function Get-UpdatePlanItems($cfg) {
    $items = @()
    foreach ($v in @($cfg.vendors)) {
        $ref = if ([string]::IsNullOrWhiteSpace([string]$v.ref)) { "main" } else { [string]$v.ref }
        $current = Get-CurrentRepoCommit (VendorPath $v.name)
        $remote = Resolve-RemoteCommit ([string]$v.repo) $ref
        $items += [pscustomobject]@{
            type = "vendor"
            name = [string]$v.name
            ref = $ref
            current = if ([string]::IsNullOrWhiteSpace($current)) { "missing" } else { $current }
            target = if ([string]::IsNullOrWhiteSpace($remote)) { "unknown" } else { $remote }
            changed = (-not [string]::IsNullOrWhiteSpace($remote)) -and ($remote -ne $current)
        }
    }

    foreach ($i in @($cfg.imports)) {
        if ($i.mode -eq "vendor") { continue }
        $name = [string]$i.name
        $ref = if ([string]::IsNullOrWhiteSpace([string]$i.ref)) { "main" } else { [string]$i.ref }
        $path = Join-Path $ImportDir $name
        $current = Get-CurrentRepoCommit $path
        $remote = Resolve-RemoteCommit ([string]$i.repo) $ref
        $items += [pscustomobject]@{
            type = "import"
            name = $name
            ref = $ref
            current = if ([string]::IsNullOrWhiteSpace($current)) { "missing" } else { $current }
            target = if ([string]::IsNullOrWhiteSpace($remote)) { "unknown" } else { $remote }
            changed = (-not [string]::IsNullOrWhiteSpace($remote)) -and ($remote -ne $current)
        }
    }
    return @($items)
}

function Show-UpdatePlan($cfg) {
    Write-Host "=== 更新预览（--plan）==="
    $items = Get-UpdatePlanItems $cfg
    if ($items.Count -eq 0) {
        Write-Host "未发现可规划项（vendors/imports 为空）。"
        return @()
    }
    $changed = @($items | Where-Object { $_.changed })
    foreach ($it in $items) {
        $mark = if ($it.changed) { "UPGRADE" } else { "UNCHANGED" }
        Write-Host ("[{0}] {1}/{2} ref={3}" -f $mark, $it.type, $it.name, $it.ref)
        Write-Host ("  current: {0}" -f $it.current)
        Write-Host ("  target : {0}" -f $it.target)
    }
    Write-Host ("计划摘要：total={0}, upgrade={1}, unchanged={2}" -f $items.Count, $changed.Count, ($items.Count - $changed.Count))
    return $items
}

function 更新Vendor($cfg = $null, [switch]$SkipPreflight, $SkipForceClean = $null, [switch]$SkipFetch) {
    return (Invoke-WithMetric "update_vendor" {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        $failures = New-Object System.Collections.Generic.List[string]

        foreach ($v in $cfg.vendors) {
            try {
                $path = VendorPath $v.name
                if (-not (Test-Path $path)) {
                    Write-Host ("❌ 未找到 vendor/{0} (跳过)" -f $v.name) -ForegroundColor Red
                    continue 
                }
                if ([string]::IsNullOrWhiteSpace($v.ref)) { $v.ref = "main" }

                Push-Location $path
                try {
                    $forceClean = Should-ForceCleanTarget $cfg $SkipForceClean "vendor" $v.name
                    Git-HardResetClean $forceClean
                    if (-not $SkipFetch) {
                        Invoke-Git @("fetch", "--all", "--tags")
                    }
                    $sparsePaths = @()
                    foreach ($i in $cfg.imports) {
                        if ($i.mode -ne "vendor") { continue }
                        if ($i.name -ne $v.name) { continue }
                        if (-not $i.sparse) { continue }
                        $p = To-GitPath (Normalize-SkillPath $i.skill)
                        if ($p -and $p -ne ".") { $sparsePaths += $p }
                    }
                    foreach ($m in $cfg.mappings) {
                        if ($m.vendor -ne $v.name) { continue }
                        $p = To-GitPath (Normalize-SkillPath $m.from)
                        if ($p -and $p -ne ".") { $sparsePaths += $p }
                    }
                    $sparsePaths = $sparsePaths | Select-Object -Unique
                    if ($sparsePaths.Count -gt 0) {
                        Invoke-Git @("sparse-checkout", "init", "--cone")
                        Invoke-Git (@("sparse-checkout", "set") + $sparsePaths)
                    }
                    else {
                        try { Invoke-Git @("sparse-checkout", "disable") } catch {}
                    }
                    Invoke-Git @("checkout", $v.ref)
                    $branch = Get-GitHeadBranch
                    if ($branch -and (Has-GitUpstream)) {
                        Invoke-Git @("pull")
                    }
                    else {
                        Log ("跳过 git pull：{0} 处于 detached HEAD 或无 upstream。" -f $v.name)
                    }
                }
                finally {
                    Pop-Location
                }
            }
            catch {
                Write-Host ("❌ 更新失败 [{0}]: {1}" -f $v.name, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("vendor:{0} => {1}" -f $v.name, $_.Exception.Message)) | Out-Null
            }
        }
        if ($failures.Count -eq 0) {
            Write-Host "上游仓库更新完成。"
        }
        else {
            Write-Host ("上游仓库更新完成（部分失败：{0} 项）。" -f $failures.Count) -ForegroundColor Yellow
        }
        Clear-SkillsCache
        return $failures.ToArray()
    } @{ command = "更新Vendor" } -NoHost)
}

function 更新Imports($cfg = $null, [switch]$SkipPreflight, $SkipForceClean = $null, [switch]$SkipFetch) {
    return (Invoke-WithMetric "update_imports" {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        $cfgRaw = if (Test-Path $CfgPath) { Get-Content $CfgPath -Raw } else { "" }
        $cfgChanged = $false

        # Optimization/Migration before update
        Optimize-Imports $cfg

        if ($cfg.imports.Count -eq 0) { return @() }
        $failures = New-Object System.Collections.Generic.List[string]
        foreach ($i in $cfg.imports) {
            if ($i.mode -ne "manual") { continue }
            try {
                $name = $i.name
                $repo = Normalize-RepoUrl $i.repo
                $ref = $i.ref
                if ([string]::IsNullOrWhiteSpace($ref)) { $ref = "main" }
                $skillPath = Normalize-SkillPath $i.skill
                $gitSkillPath = To-GitPath $skillPath
                $sparse = [bool]$i.sparse
                if ($gitSkillPath -eq "." -and $sparse) { $sparse = $false }
                $sparsePath = $null
                if ($sparse) { $sparsePath = $gitSkillPath }
                $cache = Join-Path $ImportDir $name

                $forceClean = Should-ForceCleanTarget $cfg $SkipForceClean "import" $i.name
                try {
                    $null = Ensure-Repo $cache $repo $ref $sparsePath $forceClean $false (-not $SkipFetch)
                }
                catch {
                    if ((Test-WindowsInvalidPathIssue $_.Exception.Message) -and $gitSkillPath -ne ".") {
                        $invalidPathForceClean = $forceClean
                        if (-not $invalidPathForceClean -and (Test-Path -LiteralPath $cache)) {
                            $expectedSrc = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                            if (-not (Test-IsSkillDir $expectedSrc)) {
                                $invalidPathForceClean = $true
                                Log ("导入缓存已不可用，非法路径回退临时启用强制清理：{0} [{1}]" -f $name, $repo) "WARN"
                            }
                        }
                        $fallbackDone = $false
                        $sparseFallbackError = $null
                        if (-not $sparse) {
                            try {
                                $fallbackSparsePath = $gitSkillPath
                                Log ("导入更新检测到 Windows 非法路径，先回退为 sparse checkout：{0} [{1}] -> {2}" -f $name, $repo, $fallbackSparsePath) "WARN"
                                $null = Ensure-Repo $cache $repo $ref $fallbackSparsePath $invalidPathForceClean $false (-not $SkipFetch)
                                $sparse = $true
                                $sparsePath = $fallbackSparsePath
                                if (-not [bool]$i.sparse) {
                                    $i.sparse = $true
                                    $cfgChanged = $true
                                }
                                $fallbackDone = $true
                            }
                            catch {
                                $sparseFallbackError = $_.Exception.Message
                                Log ("sparse checkout 回退失败，改用归档回退：{0} [{1}]；原因：{2}" -f $name, $repo, $sparseFallbackError) "WARN"
                            }
                        }
                        if (-not $fallbackDone) {
                            try {
                                Ensure-RepoFromGitArchive $cache $repo $ref $skillPath $invalidPathForceClean | Out-Null
                                Log ("导入更新已回退为 git archive：{0} [{1}] -> {2}" -f $name, $repo, $skillPath) "WARN"
                                $fallbackDone = $true
                            }
                            catch {
                                $archiveError = $_.Exception.Message
                                try {
                                    Ensure-RepoFromGitHubTreeSnapshot $cache $repo $ref $skillPath $invalidPathForceClean | Out-Null
                                    Log ("导入更新已回退为 GitHub tree 快照：{0} [{1}] -> {2}" -f $name, $repo, $skillPath) "WARN"
                                    $fallbackDone = $true
                                }
                                catch {
                                    $snapshotError = $_.Exception.Message
                                    $prefix = if ([string]::IsNullOrWhiteSpace($sparseFallbackError)) { "" } else { ("sparse={0} | " -f $sparseFallbackError) }
                                    throw ("Windows 非法路径回退失败：{0}archive={1} | snapshot={2}" -f $prefix, $archiveError, $snapshotError)
                                }
                            }
                        }
                        if (-not $fallbackDone) { throw }
                    }
                    else {
                        $lockPath = Join-Path $cache ".git\index.lock"
                        $fallbackSkillPath = Resolve-SkillPath $cache $skillPath
                        $fallbackSrc = if ($fallbackSkillPath -eq ".") { $cache } else { Join-Path $cache $fallbackSkillPath }
                        if ((Test-Path -LiteralPath $lockPath -PathType Leaf) -and (Test-IsSkillDir $fallbackSrc)) {
                            Log ("导入更新遇到 Git 索引锁异常，已保留现有缓存：{0} [{1}]；原因：{2}" -f $name, $repo, $_.Exception.Message) "WARN"
                            if ($fallbackSkillPath -ne $skillPath) {
                                $i.skill = $fallbackSkillPath
                                $cfgChanged = $true
                                $skillPath = $fallbackSkillPath
                            }
                        }
                        else {
                            throw
                        }
                    }
                }
                $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                if (-not (Test-IsSkillDir $src)) {
                    $resolvedSkillPath = Resolve-SkillPath $cache $skillPath
                    if ($resolvedSkillPath -ne $skillPath) {
                        $i.skill = $resolvedSkillPath
                        $cfgChanged = $true
                        $skillPath = $resolvedSkillPath
                        $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                        Log ("导入技能路径已自动修正：{0} -> {1} [{2}]" -f [string]$i.name, $skillPath, $repo) "WARN"
                    }
                }
                Need (Test-IsSkillDir $src) "未找到技能入口文件（SKILL.md/AGENTS.md/GEMINI.md/CLAUDE.md）：$src"
                Write-Host ("已更新导入技能缓存：{0}" -f $name)
            }
            catch {
                Write-Host ("❌ 导入更新失败 [{0}]: {1}" -f $i.name, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("import:{0} => {1}" -f $i.name, $_.Exception.Message)) | Out-Null
            }
        }
        if ($cfgChanged) {
            SaveCfgSafe $cfg $cfgRaw
        }
        Clear-SkillsCache
        return $failures.ToArray()
    } @{ command = "更新Imports" } -NoHost)
}

function 更新 {
    Invoke-WithMetric "update_total" {
        $cfg = LoadCfg
        if ($Locked -and ($Plan -or $Upgrade)) {
            throw "-Locked 不能与 -Plan 或 -Upgrade 同时使用。"
        }
        Invoke-PrebuildCheck
        if ($Plan) {
            Preflight
            Show-UpdatePlan $cfg | Out-Null
            return
        }
        if ($Locked) {
            $lock = Load-LockData
            Assert-LockMatchesCfg $cfg $lock
            Apply-LockToWorkspace $cfg $lock
            构建生效
            Write-Host "已按锁文件固定版本完成更新与构建。"
            return
        }
        $skipForceClean = @{}
        if (-not (Confirm-UpdateForce $cfg ([ref]$skipForceClean))) { return }
        if (Skip-IfDryRun "更新") { return }
        Preflight
        $parallelism = Get-UpdateParallelism $cfg
        $didPrefetch = $false
        if ($parallelism -gt 1) {
            Invoke-ParallelGitPrefetch $cfg $parallelism
            $didPrefetch = $true
        }
        $failures = @()
        $importFailures = 更新Imports $cfg -SkipPreflight -SkipForceClean $skipForceClean -SkipFetch:$didPrefetch
        if ($importFailures) { $failures += $importFailures }
        $vendorFailures = 更新Vendor $cfg -SkipPreflight -SkipForceClean $skipForceClean -SkipFetch:$didPrefetch
        if ($vendorFailures) { $failures += $vendorFailures }
        构建生效
        if ($Upgrade -and $failures.Count -eq 0) {
            Save-LockData $cfg | Out-Null
            Write-Host ("已刷新锁文件：{0}" -f (Get-LockPath))
        }
        if ($failures.Count -gt 0) {
            Write-FailureSummary "更新部分失败" $failures "请查看上方错误并重试。"
        }
        else {
            Write-Host "更新完成。若某 CLI 未立即识别新技能，重启该 CLI 会话即可。"
        }
    } @{ command = "更新" } -NoHost
}
