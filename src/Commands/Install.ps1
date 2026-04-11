function Upsert-Import($cfg, $import) {
    $existing = $cfg.imports | Where-Object { $_.name -eq $import.name } | Select-Object -First 1
    if ($existing) {
        $existing.repo = $import.repo
        $existing.ref = $import.ref
        $existing.skill = $import.skill
        $existing.mode = $import.mode
        $existing.sparse = $import.sparse
    }
    else {
        $cfg.imports += $import
    }
}

function Ensure-ImportVendorMapping($cfg, [string]$vendorName, [string]$skillPath, [string]$targetName) {
    $skillPath = Normalize-SkillPath $skillPath
    $from = $skillPath
    if ($from -eq ".") { $from = "." }
    $exists = $cfg.mappings | Where-Object { $_.vendor -eq $vendorName -and $_.from -eq $from } | Select-Object -First 1
    if (-not $exists) {
        $cfg.mappings += @{ vendor = $vendorName; from = $from; to = $targetName }
    }
}
function Test-NeedsSparseProbeFallback([string]$msg) {
    if ([string]::IsNullOrWhiteSpace($msg)) { return $false }
    return ($msg -match "unable to checkout working tree|checkout failed|git restore --source=HEAD :/|invalid path|Filename too long|文件名.*太长|路径.*过长")
}
function Get-PreferredSkillCandidates($candidates) {
    $ordered = @($candidates | Sort-Object rel)
    if ($ordered.Count -le 1) { return $ordered }
    $preferred = @($ordered | Where-Object {
            $relGit = (($_.rel -as [string]) -replace "\\", "/")
            $relGit -match "^(\\.claude/skills|skills)(/|$)"
        })
    if ($preferred.Count -gt 0) { return $preferred }
    return $ordered
}
function Get-RelevantSkillCandidates($candidates, [string]$skillPath) {
    $ranked = @(Get-SkillCandidatesByRelevance $candidates $skillPath)
    if ($ranked.Count -eq 0) { return @($candidates | Sort-Object rel) }
    return $ranked
}
function Resolve-SkillsWithSparseProbe([string]$repo, [string]$ref, [string[]]$skillPaths) {
    $repoCandidates = Get-SkillCandidatesFromGitRepo $repo $ref
    Need ($repoCandidates.Count -gt 0) "仓库内未发现任何有效的技能标记文件（SKILL.md, AGENTS.md, GEMINI.md, CLAUDE.md）"
    $resolved = @()
    foreach ($p in $skillPaths) {
        $normalized = Normalize-SkillPath $p
        $matched = $null

        $exact = @($repoCandidates | Where-Object { $_.rel -eq $normalized })
        if ($exact.Count -eq 1) {
            $matched = $exact[0].rel
        }

        if ([string]::IsNullOrWhiteSpace($matched) -and $normalized -ne "." -and $normalized -notmatch "[\\/]") {
            $prefixed = Join-Path "skills" $normalized
            $prefixedMatch = @($repoCandidates | Where-Object { $_.rel -eq $prefixed })
            if ($prefixedMatch.Count -eq 1) { $matched = $prefixedMatch[0].rel }
        }

        if ([string]::IsNullOrWhiteSpace($matched)) {
            $leaf = Split-Path $normalized -Leaf
            $leafMatches = @($repoCandidates | Where-Object { $_.leaf -eq $leaf })
            if ($leafMatches.Count -eq 1) {
                $matched = $leafMatches[0].rel
            }
            elseif ($leafMatches.Count -gt 1) {
                $preferredLeaf = @(Get-PreferredSkillCandidates $leafMatches)
                if ($preferredLeaf.Count -eq 1) {
                    $matched = $preferredLeaf[0].rel
                }
                else {
                    $rankedLeaf = @(Get-RelevantSkillCandidates $preferredLeaf $normalized)
                    $top = @($rankedLeaf | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
                    throw ("技能路径预检失败：--skill {0}`n同名候选过多，请改为精确路径。`n{1}" -f $normalized, ($top -join "`n"))
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($matched)) {
            $leafNorm = Normalize-Name (Split-Path $normalized -Leaf)
            $leafCompact = Normalize-CompactName (Split-Path $normalized -Leaf)
            if (-not [string]::IsNullOrWhiteSpace($leafNorm)) {
                $fuzzy = @($repoCandidates | Where-Object {
                        $candNorm = Normalize-Name $_.leaf
                        if ([string]::IsNullOrWhiteSpace($candNorm)) { return $false }
                        return ($leafNorm -eq $candNorm) -or ($leafNorm.EndsWith("-$candNorm"))
                    })
                if ($fuzzy.Count -eq 1) {
                    $matched = $fuzzy[0].rel
                }
                elseif ($fuzzy.Count -gt 1) {
                    $preferredFuzzy = @(Get-PreferredSkillCandidates $fuzzy)
                    if ($preferredFuzzy.Count -eq 1) {
                        $matched = $preferredFuzzy[0].rel
                    }
                    else {
                        $rankedFuzzy = @(Get-RelevantSkillCandidates $preferredFuzzy $normalized)
                        $top = @($rankedFuzzy | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
                        throw ("技能路径预检失败：--skill {0}`n后缀候选过多，请改为精确路径。`n{1}" -f $normalized, ($top -join "`n"))
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($matched) -and -not [string]::IsNullOrWhiteSpace($leafCompact)) {
                $compact = @($repoCandidates | Where-Object {
                        $candCompact = Normalize-CompactName $_.leaf
                        if ([string]::IsNullOrWhiteSpace($candCompact)) { return $false }
                        return ($leafCompact -eq $candCompact) -or ($leafCompact.Contains($candCompact)) -or ($candCompact.Contains($leafCompact))
                    })
                if ($compact.Count -eq 1) {
                    $matched = $compact[0].rel
                }
                elseif ($compact.Count -gt 1) {
                    $preferredCompact = @(Get-PreferredSkillCandidates $compact)
                    $rankedCompact = @(Get-RelevantSkillCandidates $preferredCompact $normalized)
                    $top = @($rankedCompact | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
                    throw ("技能路径预检失败：--skill {0}`n紧凑匹配候选过多，请改为精确路径。`n{1}" -f $normalized, ($top -join "`n"))
                }
            }
            if ([string]::IsNullOrWhiteSpace($matched) -and -not [string]::IsNullOrWhiteSpace($leafNorm) -and $leafNorm -match "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)") {
                $semantic = @($repoCandidates | Where-Object {
                        $candNorm = Normalize-Name $_.leaf
                        if ([string]::IsNullOrWhiteSpace($candNorm)) { return $false }
                        return ($candNorm -match "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)")
                    })
                if ($semantic.Count -eq 1) {
                    $matched = $semantic[0].rel
                }
                elseif ($semantic.Count -gt 1) {
                    $preferredSemantic = @(Get-PreferredSkillCandidates $semantic)
                    $rankedSemantic = @(Get-RelevantSkillCandidates $preferredSemantic $normalized)
                    $top = @($rankedSemantic | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
                    throw ("技能路径预检失败：--skill {0}`n语义匹配候选过多，请改为精确路径。`n{1}" -f $normalized, ($top -join "`n"))
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($matched)) {
            $rankedAll = @(Get-RelevantSkillCandidates $repoCandidates $normalized)
            $top = @($rankedAll | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
            throw ("技能路径预检失败：--skill {0}`n仓库在当前系统上无法完成完整 checkout，且未找到该路径。请显式指定正确路径。`n{1}" -f $normalized, ($top -join "`n"))
        }

        if ($matched -ne $normalized) { Write-Host ("未找到指定路径，已自动修正为：{0}" -f $matched) }
        $resolved += $matched
    }
    return $resolved
}
function Resolve-SkillsWithProbe([string]$repo, [string]$ref, [string[]]$skillPaths, [bool]$forceClean) {
    $probeName = ("_probe_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    $probePath = Join-Path $ImportDir $probeName
    $resolved = @()
    try {
        try {
            Ensure-Repo $probePath $repo $ref $null $forceClean $false
        }
        catch {
            $probeError = $_.Exception.Message
            if (-not (Test-NeedsSparseProbeFallback $probeError)) { throw }
            Log ("完整 clone/checkout 预检失败，自动回退 sparse 预检：{0}" -f $probeError) "WARN"
            return (Resolve-SkillsWithSparseProbe $repo $ref $skillPaths)
        }
        if ($script:SkillCandidatesCache) { $script:SkillCandidatesCache.Remove($probePath) | Out-Null }
        foreach ($p in $skillPaths) {
            $normalized = Normalize-SkillPath $p
            try {
                $resolved += (Resolve-SkillPath $probePath $normalized)
            }
            catch {
                $candidates = @()
                try { $candidates = Get-SkillCandidates $probePath } catch {}
                $hint = @()
                if ($candidates.Count -gt 0) {
                    $rankedCandidates = @(Get-RelevantSkillCandidates $candidates $normalized)
                    $hint += ("可用技能路径候选（Top {0}）：" -f ([Math]::Min(12, $candidates.Count)))
                    foreach ($c in ($rankedCandidates | Select-Object -First 12)) {
                        $hint += ("- {0}" -f $c.rel)
                    }
                    if ($candidates.Count -gt 12) {
                        $hint += ("... 另有 {0} 项未显示" -f ($candidates.Count - 12))
                    }
                }
                $msg = ("技能路径预检失败：--skill {0}`n{1}" -f $normalized, $_.Exception.Message)
                if ($hint.Count -gt 0) { $msg += ("`n" + ($hint -join "`n")) }
                throw $msg
            }
        }
        return $resolved
    }
    finally {
        if (Test-Path $probePath) { Invoke-RemoveItemWithRetry $probePath -Recurse -IgnoreFailure | Out-Null }
        if ($script:SkillCandidatesCache) { $script:SkillCandidatesCache.Remove($probePath) | Out-Null }
    }
}
function Get-InstallErrorSuggestedSkillPath([string]$msg, [string[]]$skillPaths) {
    if (-not [string]::IsNullOrWhiteSpace($msg)) {
        $bulletMatches = [regex]::Matches($msg, "(?m)^-\s+(.+)$")
        foreach ($m in $bulletMatches) {
            $candidate = $m.Groups[1].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if ($candidate -eq ".") { continue }
            return ($candidate -replace "\\", "/")
        }
    }

    $sample = if ($skillPaths -and $skillPaths.Count -gt 0) { $skillPaths[0] } else { "<skill>" }
    $sample = ($sample -replace "\\", "/").Trim()
    if ([string]::IsNullOrWhiteSpace($sample)) { return "skills/<skill>" }
    if ($sample -eq ".") { return "." }
    if ($sample.Contains("/")) { return $sample }

    $leaf = Split-Path $sample -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "<skill>" }
    return ("skills/{0}" -f $leaf)
}
function Get-CrossRepoInstallFallbackPlan([string]$repo, [string[]]$skillPaths, [string]$msg) {
    if ([string]::IsNullOrWhiteSpace($msg) -or $msg -notmatch "未找到技能入口文件") { return $null }
    if (-not $skillPaths -or $skillPaths.Count -eq 0) { return $null }

    $repoText = if ([string]::IsNullOrWhiteSpace($repo)) { "" } else { $repo.ToLowerInvariant() }
    $firstSkill = [string]$skillPaths[0]
    $leaf = (Split-Path (Normalize-SkillPath $firstSkill) -Leaf).ToLowerInvariant()
    $leafNorm = Normalize-Name $leaf

    # High-frequency cross-repo aliases.
    $catalog = @(
        @{
            pattern = "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)"
            repoMatch = "mblode/agent-skills"
            repo = "https://github.com/mblode/agent-skills.git"
            skill = "motion"
        },
        @{
            pattern = "(^|-)uni(-)?app($|-)|(^|-)uni-helper($|-)"
            repoMatch = "uni-helper/skills"
            repo = "https://github.com/uni-helper/skills.git"
            skill = "uniapp"
        },
        @{
            pattern = "(^|-)remotion($|-)|(^|-)remotion-best-practices($|-)"
            repoMatch = "remotion-dev/skills"
            repo = "https://github.com/remotion-dev/skills.git"
            skill = "remotion"
        }
    )

    foreach ($entry in $catalog) {
        if ($leafNorm -notmatch $entry.pattern) { continue }
        if ($repoText -match [string]$entry.repoMatch) { continue }
        return [pscustomobject]@{
            repo = [string]$entry.repo
            skill = [string]$entry.skill
            command = (".\skills.ps1 add {0} --skill {1}" -f [string]$entry.repo, [string]$entry.skill)
        }
    }
    return $null
}
function Write-InstallErrorHint([string]$msg, [string]$repo, [string[]]$skillPaths) {
    if ([string]::IsNullOrWhiteSpace($msg)) { return }
    if ($msg -match "zip 文件当前被占用|由另一进程使用|being used by another process") {
        Write-Host "提示：检测到 zip 被占用。请关闭资源管理器预览/压缩软件/同步盘后重试；工具已自动采用“临时复制 + 重试解压”策略。" -ForegroundColor Yellow
        return
    }
    if ($msg -match "仓库不可访问或不存在|Repository not found|repository '.+' not found") {
        if (Test-LocalZipRepoInput $repo) {
            Write-Host "提示：你传入的是本地 zip，已按本地压缩包处理；若仍失败，请确认 zip 可读且未被占用。" -ForegroundColor Yellow
            return
        }
        Write-Host "提示：请先在浏览器确认仓库地址可访问，私有仓库需先配置 git 凭据。" -ForegroundColor Yellow
        return
    }
    if ($msg -match "仓库内未发现任何有效的技能标记文件") {
        Write-Host "提示：该仓库可能不是本工具支持的 skills 仓库（缺少 SKILL.md/AGENTS.md/GEMINI.md/CLAUDE.md）。" -ForegroundColor Yellow
        return
    }
    if ($msg -match "未找到技能入口文件") {
        $suggestedSkillPath = Get-InstallErrorSuggestedSkillPath $msg $skillPaths
        Write-Host ("提示：请改用真实路径，例如：--skill {0}" -f $suggestedSkillPath) -ForegroundColor Yellow
        Write-Host ("提示：当前 repo = {0}" -f $repo) -ForegroundColor Yellow
        $plan = Get-CrossRepoInstallFallbackPlan $repo $skillPaths $msg
        if ($plan -and -not [string]::IsNullOrWhiteSpace([string]$plan.command)) {
            Write-Host ("提示：当前仓库可能不包含该技能，可直接执行：{0}" -f $plan.command) -ForegroundColor Yellow
        }
    }
}

function Get-DeclaredSkillNameFromDir([string]$skillDir) {
    if ([string]::IsNullOrWhiteSpace($skillDir)) { return $null }
    $skillFile = Join-Path $skillDir "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $skillFile -TotalCount 80 -ErrorAction SilentlyContinue)) {
        if ($line -match "^\s*name:\s*(.+?)\s*$") {
            $declaredName = $Matches[1].Trim().Trim("'`"")
            if (-not [string]::IsNullOrWhiteSpace($declaredName)) {
                return $declaredName
            }
        }
    }
    return $null
}

function Add-ImportFromArgs([string[]]$tokens, [switch]$NoBuild) {
    Preflight
    $cfgRaw = ""
    $cfg = LoadCfg
    if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }

    $resolvedTokens = Resolve-AddTokensFromAnyFormat $tokens
    if ($resolvedTokens) { $tokens = $resolvedTokens }
    $parsed = Parse-AddArgs $tokens
    $repo = Normalize-RepoUrl $parsed.repo
    $ref = $parsed.ref
    $refIsAuto = $false
    if ([string]::IsNullOrWhiteSpace($ref)) {
        $ref = "main"
        $refIsAuto = $true
    }
    $mode = $parsed.mode
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "manual" }
    $mode = $mode.ToLowerInvariant()
    Need ($mode -eq "manual" -or $mode -eq "vendor") "mode 仅支持 manual 或 vendor"
    $registerVendorOnly = (-not [bool]$parsed.skillSpecified -and -not [bool]$parsed.modeSpecified)
    if ($registerVendorOnly) { $mode = "vendor" }

    $sparse = [bool]$parsed.sparse

    if ($DryRun) {
        if ($registerVendorOnly) {
            Write-Host ("DRYRUN：将新增技能库（vendor only）：{0} ({1})" -f $repo, $ref)
        }
        else {
            Write-Host ("DRYRUN：将从 {0} ({1}) 导入 {2} 个技能，模式：{3}，Sparse：{4}" -f $repo, $ref, $parsed.skills.Count, $mode, $sparse)
        }
        if (-not $NoBuild) { Write-Host "DRYRUN：将执行【构建生效】" }
        return $true
    }

    try {
        # Strict precheck: repo must be reachable.
        Assert-RepoReachable $repo

        if ($refIsAuto) {
            $ref = Get-RepoDefaultBranch $repo
            Log ("未指定 --ref，自动使用仓库默认分支：{0}" -f $ref)
        }

        $resolvedSkillPaths = $null

        # Auto-detect mode if not specified (or default manual)
        if ($mode -eq "manual") {
            Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL cannot be empty"
            $matchedVendor = Match-VendorByRepo $cfg $repo
            if ($matchedVendor) {
                $mode = "vendor"
                $vendorName = $matchedVendor.name
                $parsed.name = $vendorName # Override name to vendor name
                Log ("自动检测到已存在的 Vendor：{0}。切换为 Vendor 模式安装。" -f $vendorName)
            }
            elseif ($registerVendorOnly) {
                Log "未显式指定 --skill：按“仅新增技能库”处理（不安装仓库内技能）。"
                $mode = "vendor"
            }
        }

        # Strict precheck: resolve all skill paths before writing config.
        if ($registerVendorOnly) {
            $resolvedSkillPaths = @()
        }
        elseif ($null -eq $resolvedSkillPaths) {
            $resolvedSkillPaths = @(Resolve-SkillsWithProbe $repo $ref $parsed.skills $cfg.update_force)
        }
        else {
            $resolvedSkillPaths = @($resolvedSkillPaths)
        }

        if ($mode -eq "manual") {
            $baseName = $null
            if (-not [string]::IsNullOrWhiteSpace($parsed.name)) {
                $baseName = Normalize-NameWithNotice $parsed.name "导入名称"
            }
            foreach ($skillPath in $resolvedSkillPaths) {
                $name = $baseName
                $allowDeclaredName = [string]::IsNullOrWhiteSpace($name)
                if ($allowDeclaredName -or $resolvedSkillPaths.Count -gt 1) {
                    $leaf = if ($skillPath -eq ".") { Guess-VendorName $repo } else { Split-Path $skillPath -Leaf }
                    $curName = Normalize-Name $leaf
                    $name = if (-not [string]::IsNullOrWhiteSpace($name)) { "$name-$curName" } else { $curName }
                }
                $name = Normalize-NameWithNotice $name "导入名称"

                $cache = Join-Path $ImportDir $name
                $gitSkillPath = To-GitPath $skillPath
                $curSparse = $sparse
                if ($gitSkillPath -eq "." -and $curSparse) { $curSparse = $false }
                $sparsePath = if ($curSparse) { $gitSkillPath } else { $null }
                $usedArchiveFallback = $false

                try {
                    Ensure-Repo $cache $repo $ref $sparsePath $cfg.update_force $true
                }
                catch {
                    $importError = $_.Exception.Message
                    if (($skillPath -eq ".") -or (-not (Test-NeedsSparseProbeFallback $importError))) { throw }
                    Log ("导入阶段 clone/checkout 失败，自动回退 git archive 子目录导出：{0}" -f $importError) "WARN"
                    try {
                        Ensure-RepoFromGitArchive $cache $repo $ref $skillPath $cfg.update_force
                    }
                    catch {
                        $archiveError = $_.Exception.Message
                        if (-not (Test-NeedsSparseProbeFallback $archiveError)) { throw }
                        Log ("git archive 回退失败，自动回退 GitHub 子目录快照导入：{0}" -f $archiveError) "WARN"
                        Ensure-RepoFromGitHubTreeSnapshot $cache $repo $ref $skillPath $cfg.update_force
                    }
                    $usedArchiveFallback = $true
                }
                if ($script:SkillCandidatesCache) { $script:SkillCandidatesCache.Remove($cache) | Out-Null }

                if ($curSparse -and -not $usedArchiveFallback) {
                    Ensure-Repo $cache $repo $ref (To-GitPath $skillPath) $cfg.update_force $true
                }
                $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                Need (Test-IsSkillDir $src) "未找到技能入口文件（SKILL.md/AGENTS.md/GEMINI.md/CLAUDE.md）：$src"

                if ($allowDeclaredName) {
                    $declaredName = Get-DeclaredSkillNameFromDir $src
                    if (-not [string]::IsNullOrWhiteSpace($declaredName)) {
                        $preferredName = Normalize-NameWithNotice $declaredName "导入名称"
                        if ($preferredName -ne $name) {
                            $preferredCache = Join-Path $ImportDir $preferredName
                            if ($cache -ne $preferredCache -and -not (Test-Path $preferredCache)) {
                                Invoke-MoveItem $cache $preferredCache
                                $cache = $preferredCache
                                $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                            }
                            $name = $preferredName
                        }
                    }
                }

                $import = @{ name = $name; repo = $repo; ref = $ref; skill = $skillPath; mode = "manual"; sparse = $curSparse }
                Upsert-Import $cfg $import
            }
        }
        else {
            $vendorName = $parsed.name
            if ([string]::IsNullOrWhiteSpace($vendorName)) { $vendorName = Guess-VendorName $repo }
            $allowExistingVendor = ($cfg.vendors | Where-Object { $_.name -eq $vendorName -and (Is-SameRepository ([string]$_.repo) $repo) } | Select-Object -First 1) -ne $null
            $vendorName = Resolve-UniqueVendorName $cfg $vendorName $repo $allowExistingVendor
            $vendorPath = VendorPath $vendorName
      
            Ensure-Repo $vendorPath $repo $ref $null $cfg.update_force $true
            if (-not $registerVendorOnly) {
                foreach ($skillPath in $resolvedSkillPaths) {
                    if ($script:SkillCandidatesCache) { $script:SkillCandidatesCache.Remove($vendorPath) | Out-Null }
                    $src = if ($skillPath -eq ".") { $vendorPath } else { Join-Path $vendorPath $skillPath }
                    Need (Test-IsSkillDir $src) "未找到技能入口文件（SKILL.md/AGENTS.md/GEMINI.md/CLAUDE.md）：$src"

                    $targetSuffix = if ($skillPath -eq ".") { $vendorName } else { $skillPath }
                    $targetName = Make-TargetName $vendorName $targetSuffix
                    Ensure-ImportVendorMapping $cfg $vendorName $skillPath $targetName
                }

                $primarySkillPath = if ($resolvedSkillPaths -contains ".") { "." } else { [string]$resolvedSkillPaths[0] }
                $import = @{ name = $vendorName; repo = $repo; ref = $ref; skill = $primarySkillPath; mode = "vendor"; sparse = $sparse }
                Upsert-Import $cfg $import
            }
      
            $vendor = $cfg.vendors | Where-Object { $_.name -eq $vendorName } | Select-Object -First 1
            if (-not $vendor) {
                $cfg.vendors += @{ name = $vendorName; repo = $repo; ref = $ref }
            }
            else {
                $vendor.repo = $repo
                $vendor.ref = $ref
            }

            # Vendor-only registration should still reconcile already-installed manual skills from the same repo.
            if ($registerVendorOnly) {
                $migrated = Migrate-ManualToVendor $cfg $vendorName $repo
                if ($migrated -gt 0) {
                    Write-Host ("已自动迁移 {0} 个已安装技能到 vendor/{1}（仅关联，不新增其它技能）。" -f $migrated, $vendorName) -ForegroundColor Yellow
                }
            }
        }

        SaveCfgSafe $cfg $cfgRaw
        Clear-SkillsCache

        if (-not $NoBuild) {
            Write-Host "导入完成。开始【构建生效】..."
            构建生效
        }
        else {
            Write-Host "导入完成。"
        }
        return $true
    }
    catch {
        $errMsg = $_.Exception.Message
        $plan = Get-CrossRepoInstallFallbackPlan $repo $parsed.skills $errMsg
        if ($plan -and -not $script:CrossRepoAutoFallbackInProgress) {
            Log ("当前仓库未命中技能，自动回退到建议仓库重试：repo={0} --skill {1}" -f $plan.repo, $plan.skill) "WARN"
            $script:CrossRepoAutoFallbackInProgress = $true
            try {
                $fallbackTokens = @([string]$plan.repo, "--skill", [string]$plan.skill)
                if (-not [string]::IsNullOrWhiteSpace($parsed.ref)) { $fallbackTokens += @("--ref", [string]$parsed.ref) }
                if (-not [string]::IsNullOrWhiteSpace($parsed.mode) -and $parsed.mode -ne "manual") { $fallbackTokens += @("--mode", [string]$parsed.mode) }
                if ([bool]$parsed.sparse) { $fallbackTokens += "--sparse" }

                $autoOk = if ($NoBuild) { Add-ImportFromArgs $fallbackTokens -NoBuild } else { Add-ImportFromArgs $fallbackTokens }
                if ($autoOk) {
                    Write-Host ("已自动回退安装成功：{0}" -f $plan.command) -ForegroundColor Green
                    return $true
                }
            }
            finally {
                $script:CrossRepoAutoFallbackInProgress = $false
            }
        }
        if (-not $DryRun -and $cfgRaw) { Set-ContentUtf8 $CfgPath $cfgRaw }
        Write-Host ("❌ 导入失败: {0}" -f $errMsg) -ForegroundColor Red
        Write-InstallErrorHint $errMsg $repo $parsed.skills
        return $false
    }
}

function 初始化 {
    Preflight
    $cfg = LoadCfg

    foreach ($v in $cfg.vendors) {
        Need (-not [string]::IsNullOrWhiteSpace($v.name)) "vendor 缺少 name"
        Need (-not [string]::IsNullOrWhiteSpace($v.repo)) "vendor $($v.name) 缺少 repo"
        if ([string]::IsNullOrWhiteSpace($v.ref)) { $v.ref = "main" }

        $path = VendorPath $v.name
        if (Test-InstalledVendorPath $path $v.repo) {
            Write-Host "已存在：vendor/$($v.name)（来源匹配，跳过 clone）"
            continue
        }

        if (Test-Path $path) {
            $origin = $null
            try {
                Push-Location $path
                try { $origin = Invoke-GitCapture @("remote", "get-url", "origin") } finally { Pop-Location }
            }
            catch {}
            $originText = if ([string]::IsNullOrWhiteSpace($origin)) { "unknown" } else { $origin }
            throw ("vendor/{0} 已存在，但来源不匹配或不是 git 仓库：current={1}, expected={2}" -f $v.name, $originText, $v.repo)
        }

        Invoke-Git @("clone", $v.repo, $path)
        Push-Location $path
        Invoke-Git @("checkout", $v.ref)
        Pop-Location
    }

    # 初始化后建议先安装/卸载
    Write-Host "初始化完成。建议下一步：直接【安装】。"
    Clear-SkillsCache
}

function 新增技能库 {
    Preflight
    $repoInput = Read-Host "请输入技能库地址（留空=仅初始化已有 vendors）"
    if ([string]::IsNullOrWhiteSpace($repoInput)) {
        初始化
        return
    }
    $repo = Normalize-RepoUrl $repoInput
    $ref = Read-Host "可选：输入分支/Tag（留空默认 main）"
    if ([string]::IsNullOrWhiteSpace($ref)) { $ref = "main" }
    if ($ref -match "^\d+$") {
        $confirm = Read-Host "你输入的 ref 是纯数字，可能误填了菜单序号。继续使用该 ref？(y/N)"
        if (-not (Is-Yes $confirm)) { throw "已取消：请重新输入正确的分支/Tag。" }
    }
    $name = Read-Host "可选：输入自定义名称（留空自动从 URL 推断）"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = Guess-VendorName $repo }
    $name = Normalize-NameWithNotice $name "vendor 名称"

    $cfg = LoadCfg
    $sameNameVendor = $cfg.vendors | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($sameNameVendor) {
        if (Is-SameRepoIdentity ([string]$sameNameVendor.repo) $repo) {
            $installedPath = VendorPath $name
            if (Test-InstalledVendorPath $installedPath $repo) {
                Write-Host ("已存在：vendor/{0}（来源匹配，跳过新增）" -f $name)
                return
            }

            Write-Host ("已存在：vendor/{0}（来源匹配，检测到本地目录缺失或异常）" -f $name) -ForegroundColor Yellow
            Write-Host "将自动执行【初始化】补齐本地仓库..." -ForegroundColor Yellow
            初始化
            return
        }
        Need $false ("vendor 名称已存在：{0}（当前来源：{1}，期望来源：{2}）" -f $name, [string]$sameNameVendor.repo, $repo)
    }

    $sameRepoVendor = Match-VendorByRepo $cfg $repo
    if ($sameRepoVendor) {
        $installedPath = VendorPath $sameRepoVendor.name
        if (Test-InstalledVendorPath $installedPath $repo) {
            if ($sameRepoVendor.name -ne $name) {
                Write-Host ("该仓库已接入：vendor/{0}（忽略新名称：{1}，跳过新增）" -f $sameRepoVendor.name, $name)
            }
            else {
                Write-Host ("已存在：vendor/{0}（来源匹配，跳过新增）" -f $sameRepoVendor.name)
            }
            return
        }

        Write-Host ("该仓库已接入：vendor/{0}（检测到本地目录缺失或异常）" -f $sameRepoVendor.name) -ForegroundColor Yellow
        Write-Host "将自动执行【初始化】补齐本地仓库..." -ForegroundColor Yellow
        初始化
        return
    }

    $cfgRaw = ""
    if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }
    $tmp = Join-Path $VendorDir ("_tmp_" + $name)

    try {
        if (Test-Path $tmp) { Invoke-RemoveItem $tmp -Recurse }
        Invoke-Git @("clone", $repo, $tmp)
        Push-Location $tmp
        try {
            Invoke-Git @("checkout", $ref)
        }
        finally {
            Pop-Location
        }

        $cfg = LoadCfg
        if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }
        Need (-not ($cfg.vendors | Where-Object { $_.name -eq $name })) "vendor 名称已存在：$name"
        $cfg.vendors += @{ name = $name; repo = $repo; ref = $ref }
        SaveCfgSafe $cfg $cfgRaw

        $dst = VendorPath $name
        Need (-not (Test-Path $dst)) "vendor 已存在：$name"
        Invoke-MoveItem $tmp $dst

        Write-Host "新增完成。"
        
        # Auto-migrate orphan manual skills
        $migrated = Migrate-ManualToVendor $cfg $name $repo
        if ($migrated -gt 0) {
            SaveCfgSafe $cfg $cfgRaw # Save again with migrations
            Write-Host ("已自动迁移 {0} 个无需手动维护的技能到新 Vendor。" -f $migrated) -ForegroundColor Yellow
        }

        Clear-SkillsCache
    }
    catch {
        if (Test-Path $tmp) { Invoke-RemoveItem $tmp -Recurse }
        if (-not $DryRun -and $cfgRaw) { Set-ContentUtf8 $CfgPath $cfgRaw }
        Write-Host ("❌ 操作失败: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

function 删除技能库 {
    Preflight
    $cfg = LoadCfg
    Need ($cfg.vendors.Count -gt 0) "当前没有可删除的技能库。"

    $toRemove = Select-Items $cfg.vendors `
    { param($idx, $v) return ("{0,3}) {1} :: {2}" -f $idx, $v.name, $v.repo) } `
        "请选择要删除的技能库" `
        "未解析到有效序号（可能是分隔符或范围格式问题）。已取消删除。"
    if ($toRemove.Count -eq 0) {
        Write-Host "未选择任何技能库。"
        return
    }
    $preview = Format-VendorPreview $toRemove
    if (-not (Confirm-WithSummary "将删除以下技能库" $preview "确认删除所选技能库？" "Y")) {
        Write-Host "已取消删除。"
        return
    }
    $keepInstalledSkills = Confirm-Action "删除时是否保留该技能库下已安装技能（转换为 manual）？" "Y" -DefaultNo
    if (Skip-IfDryRun "删除技能库") { return }

    $cfgRaw = ""
    if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }
    try {
        $removeNames = New-Object System.Collections.Generic.HashSet[string]
        foreach ($v in $toRemove) { $removeNames.Add($v.name) | Out-Null }

        if ($keepInstalledSkills) {
            $totalConverted = 0
            $totalSkipped = 0
            foreach ($v in $toRemove) {
                $result = Convert-InstalledVendorSkillsToManual $cfg $v
                $totalConverted += [int]$result.converted
                $totalSkipped += [int]$result.skipped
            }
            if ($totalConverted -gt 0 -or $totalSkipped -gt 0) {
                Write-Host ("保留技能转换完成：converted={0}, skipped={1}" -f $totalConverted, $totalSkipped) -ForegroundColor Yellow
            }
        }

        $cfg.vendors = $cfg.vendors | Where-Object { -not $removeNames.Contains($_.name) }
        $cfg.mappings = $cfg.mappings | Where-Object { -not $removeNames.Contains($_.vendor) }
        $cfg.imports = $cfg.imports | Where-Object { -not ($_.mode -eq "vendor" -and $removeNames.Contains($_.name)) }
        SaveCfgSafe $cfg $cfgRaw

        foreach ($v in $toRemove) {
            $path = VendorPath $v.name
            if (Test-Path $path) { Invoke-RemoveItem $path -Recurse }
        }
        Write-Host ("已删除技能库：{0} 项。" -f $toRemove.Count)
        Clear-SkillsCache
        构建生效
    }
    catch {
        if (-not $DryRun -and $cfgRaw) { Set-ContentUtf8 $CfgPath $cfgRaw }
        Write-Host ("❌ 删除失败: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

function Get-SkillsUnder([string]$base, [string]$vendorName) {
    if (-not $script:SkillListCache) { $script:SkillListCache = @{} }
    $key = "{0}|{1}" -f $vendorName, $base
    if ($script:SkillListCache.ContainsKey($key)) {
        return $script:SkillListCache[$key]
    }
    $items = @()
    if (Test-Path $base) {
        # Search for all supported markers
        $found = Get-ChildItem $base -Recurse -File -Force -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match "^(SKILL|AGENTS|GEMINI|CLAUDE)\.md$" }
      
        $seenDirs = New-Object System.Collections.Generic.HashSet[string]
        foreach ($f in $found) {
            $dir = $f.Directory.FullName
            if (-not $seenDirs.Add($dir)) { continue }
      
            $rel = $dir.Substring($base.Length).TrimStart("\\")
            if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "." }
            $items += [pscustomobject]@{ vendor = $vendorName; from = $rel; full = $dir }
        }
    }
    $items = ($items | Sort-Object vendor, from)
    $script:SkillListCache[$key] = $items
    return $items
}

function 收集Skills([string]$filter, $cfg = $null, $manualItems = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $items = @()

    foreach ($v in $cfg.vendors) {
        $base = VendorPath $v.name
        if (-not (Test-Path $base)) { continue }
        $items += Get-SkillsUnder $base $v.name
    }

    if ($null -eq $manualItems) { $manualItems = 收集ManualSkills $cfg }
    $items += $manualItems

    if ($filter) {
        $items = Filter-Skills $items $filter
    }

    return ($items | Sort-Object vendor, from)
}

function Resolve-ManualImportSkillPath($cfg, [string]$importName, [switch]$AllowLegacyFallback) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    if ([string]::IsNullOrWhiteSpace($importName)) { return $null }
    $imp = $cfg.imports | Where-Object { $_.mode -eq "manual" -and $_.name -eq $importName } | Select-Object -First 1
    if ($imp) {
        $skillPath = Normalize-SkillPath $imp.skill
        $cache = Join-Path $ImportDir $imp.name
        $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
        if (Test-IsSkillDir $src) { return $src }
    }
    if ($AllowLegacyFallback) {
        $legacyPath = Join-Path $ManualDir $importName
        if (Test-IsSkillDir $legacyPath) { return $legacyPath }
    }
    return $null
}

function Get-ManualDisplayVendorFromRepo([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return "manual" }
    $r = [string]$repo
    $r = $r.Trim().Trim("'`"").TrimEnd("/")
    if ([string]::IsNullOrWhiteSpace($r)) { return "manual" }
    if ($r -match "^[A-Za-z]+://") {
        try {
            $uri = [Uri]$r
            $r = [string]$uri.AbsolutePath
        }
        catch {}
    }
    $r = $r.Trim().Trim("/")
    if ([string]::IsNullOrWhiteSpace($r)) { return "manual" }
    $r = $r -replace "\\", "/"
    $parts = @($r -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $leaf = if ($parts.Count -gt 0) { [string]$parts[$parts.Count - 1] } else { $r }
    if ($leaf.EndsWith(".git", [System.StringComparison]::OrdinalIgnoreCase)) {
        $leaf = $leaf.Substring(0, $leaf.Length - 4)
    }
    $leafNorm = Normalize-Name $leaf
    if ([string]::IsNullOrWhiteSpace($leafNorm)) { return "manual" }
    $first = @($leafNorm -split "-" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($first.Count -gt 0) { return [string]$first[0] }
    return $leafNorm
}

function 收集ManualSkills($cfg = $null, [switch]$IncludeLegacyManualDir) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $items = @()
    $seen = New-Object System.Collections.Generic.HashSet[string]

    foreach ($i in $cfg.imports) {
        if ($i.mode -ne "manual") { continue }
        if ([string]::IsNullOrWhiteSpace($i.name)) { continue }
        $src = Resolve-ManualImportSkillPath $cfg $i.name -AllowLegacyFallback
        if (-not $src) { continue }
        $from = [string]$i.name
        if ($seen.Add($from)) {
            $items += [pscustomobject]@{
                vendor = "manual"
                display_vendor = Get-ManualDisplayVendorFromRepo ([string]$i.repo)
                from = $from
                full = $src
                source = if ((Join-Path $ManualDir $from) -eq $src) { "legacy-manual-dir" } else { "imports" }
            }
        }
    }

    if ($IncludeLegacyManualDir) {
        foreach ($legacy in (Get-SkillsUnder $ManualDir "manual")) {
            if ($seen.Add($legacy.from)) {
                $items += [pscustomobject]@{
                    vendor = "manual"
                    display_vendor = "manual"
                    from = $legacy.from
                    full = $legacy.full
                    source = "legacy-manual-dir"
                }
            }
        }
    }

    return ($items | Sort-Object vendor, from)
}

function Get-OverridesDirs {
    if (-not (Test-Path $OverridesDir)) {
        return @()
    }
    return Get-ChildItem $OverridesDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne ".bak" }
}

function 收集OverridesSkills {
    $items = @()
    foreach ($d in (Get-OverridesDirs)) {
        $items += [pscustomobject]@{ vendor = "overrides"; from = $d.Name; full = $d.FullName }
    }
    return $items
}

function Get-InstalledSet($cfg, $manualItems = $null, $overrideItems = $null) {
    $installed = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in $cfg.mappings) {
        $installed.Add("$($m.vendor)|$($m.from)") | Out-Null
    }
    if ($null -eq $manualItems) { $manualItems = 收集ManualSkills $cfg }
    foreach ($m in $manualItems) {
        $installed.Add("manual|$($m.from)") | Out-Null
    }
    if ($null -eq $overrideItems) { $overrideItems = 收集OverridesSkills }
    foreach ($m in $overrideItems) {
        $installed.Add("overrides|$($m.from)") | Out-Null
    }
    return $installed
}

function Get-UniqueManualImportName($cfg, [string]$baseName, $reservedNames = $null) {
    $normalized = Normalize-NameWithNotice $baseName "manual 导入名称"
    if ($null -eq $reservedNames) {
        $reservedNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    }
    $existing = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in @($cfg.imports)) {
        if ($null -eq $i) { continue }
        $name = [string]$i.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $existing.Add($name) | Out-Null
    }

    $candidate = $normalized
    $suffix = 2
    while ($existing.Contains($candidate) -or $reservedNames.Contains($candidate) -or (Test-Path (Join-Path $ImportDir $candidate))) {
        $candidate = ("{0}-{1}" -f $normalized, $suffix)
        $suffix++
    }
    $reservedNames.Add($candidate) | Out-Null
    return $candidate
}

function Convert-InstalledVendorSkillsToManual($cfg, $vendorItem) {
    Need ($null -ne $cfg) "转换失败：配置对象为空。"
    Need ($null -ne $vendorItem) "转换失败：vendor 项为空。"

    $vendorName = [string]$vendorItem.name
    $vendorRepo = [string]$vendorItem.repo
    $vendorRef = [string]$vendorItem.ref
    Need (-not [string]::IsNullOrWhiteSpace($vendorName)) "转换失败：vendor 缺少名称。"

    $vendorPath = VendorPath $vendorName
    $vendorMappings = @($cfg.mappings | Where-Object { $_.vendor -eq $vendorName -and (Normalize-SkillPath ([string]$_.from)) -ne "." })
    if ($vendorMappings.Count -eq 0) {
        return [pscustomobject]@{ converted = 0; skipped = 0 }
    }

    Need (Test-Path $vendorPath) ("转换失败：vendor 目录不存在：{0}" -f $vendorPath)
    EnsureDir $ImportDir
    $reservedNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $converted = 0
    $skipped = 0
    foreach ($m in $vendorMappings) {
        $skillPath = Normalize-SkillPath ([string]$m.from)
        $src = Join-Path $vendorPath $skillPath
        if (-not (Test-IsSkillDir $src)) {
            Write-Host ("⚠️ 保留技能时跳过（源不存在或无技能标记）：vendor={0}, from={1}" -f $vendorName, $skillPath) -ForegroundColor Yellow
            $skipped++
            continue
        }

        $baseName = Split-Path $skillPath -Leaf
        if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $vendorName }
        $manualName = Get-UniqueManualImportName $cfg $baseName $reservedNames
        $dst = Join-Path $ImportDir $manualName
        Invoke-WithRetry { Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force } 3 250

        $manualImport = @{
            name = $manualName
            repo = $vendorRepo
            ref = $vendorRef
            skill = "."
            mode = "manual"
            sparse = $false
        }
        Upsert-Import $cfg $manualImport

        $cfg.mappings += @{
            vendor = "manual"
            from = $manualName
            to = [string]$m.to
        }
        $converted++
    }

    # Remove old vendor mappings now that manual mappings are created.
    $cfg.mappings = @($cfg.mappings | Where-Object { [string]$_.vendor -ne $vendorName })
    return [pscustomobject]@{ converted = $converted; skipped = $skipped }
}

function Hide-VendorRootSkills($items) {
    $arr = @($items)
    if ($arr.Count -eq 0) { return @() }

    $vendorsWithChildren = New-Object System.Collections.Generic.HashSet[string]
    foreach ($item in $arr) {
        if ($null -eq $item) { continue }
        $vendor = [string]$item.vendor
        $from = [string]$item.from
        if ([string]::IsNullOrWhiteSpace($vendor)) { continue }
        if ($from -ne ".") {
            $vendorsWithChildren.Add($vendor) | Out-Null
        }
    }

    if ($vendorsWithChildren.Count -eq 0) { return $arr }

    $filtered = @()
    foreach ($item in $arr) {
        if ($null -eq $item) { continue }
        $vendor = [string]$item.vendor
        $from = [string]$item.from
        if ($from -eq "." -and $vendorsWithChildren.Contains($vendor)) { continue }
        $filtered += $item
    }
    return $filtered
}

function Should-SyncMappingToAgent($mapping) {
    if ($null -eq $mapping) { return $false }
    $vendor = [string]$mapping.vendor
    $from = [string]$mapping.from
    # Vendor 根映射仅用于来源聚合与清单管理，不下发到各 CLI 用户级 skills 目录。
    if ($from -eq "." -and $vendor -ne "manual" -and $vendor -ne "overrides") { return $false }
    return $true
}

function Remove-VendorRootMappingOutputsFromAgent($cfg) {
    if ($null -eq $cfg) { return 0 }
    $removed = 0
    foreach ($m in @($cfg.mappings)) {
        if ($null -eq $m) { continue }
        if (Should-SyncMappingToAgent $m) { continue }
        $to = [string]$m.to
        if ([string]::IsNullOrWhiteSpace($to)) { continue }
        $dst = Join-Path $AgentDir $to
        if (-not (Is-PathInsideOrEqual $dst $AgentDir)) { continue }
        if (Test-Path -LiteralPath $dst) {
            Invoke-RemoveItemWithRetry $dst -Recurse -IgnoreFailure | Out-Null
            $removed++
            Log ("已剔除 vendor 根映射产物：{0}" -f $to)
        }
    }
    return $removed
}

function Parse-IndexSelection([string]$selText, [int]$max) {
    if ($null -eq $selText) { return @() }
    $selText = $selText.Trim()
    if ([string]::IsNullOrWhiteSpace($selText)) { return @() }
    $low = $selText.ToLowerInvariant()
    if ($low -eq "all") { return 1..$max }
    if ($low -eq "0") { return @() }
    if ($low -eq "none") { return @() }

    # Normalize common non-ASCII separators/dashes from IME input.
    $selText = $selText -replace "[，、；;/;\\s]+", ","
    $selText = $selText -replace "[－–—−]", "-"

    $set = New-Object System.Collections.Generic.HashSet[int]
    foreach ($part in $selText.Split(",") | ForEach-Object { $_.Trim() }) {
        if ($part -match "^\d+$") {
            $n = [int]$part
            if ($n -ge 1 -and $n -le $max) { $set.Add($n) | Out-Null }
        }
        elseif ($part -match "^(\d+)-(\d+)$") {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $tmp = $a; $a = $b; $b = $tmp }
            for ($i = $a; $i -le $b; $i++) {
                if ($i -ge 1 -and $i -le $max) { $set.Add($i) | Out-Null }
            }
        }
    }
    return $set | Sort-Object
}

function Write-SelectionHint {
    Write-Host ""
    Write-Host "输入多选：如 1,3,5-10；输入 all 全选；输入 0 取消。"
}

function Read-SelectionIndices([string]$prompt, [int]$count, [string]$invalidMsg) {
    $sel = Read-HostSafe $prompt
    $idx = Parse-IndexSelection $sel $count
    if ($idx.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($sel) -and $sel.ToLowerInvariant() -ne "0") {
        Write-Host $invalidMsg
        return [pscustomobject]@{ indices = @(); canceled = $false }
    }
    $canceled = -not [string]::IsNullOrWhiteSpace($sel) -and $sel.Trim().ToLowerInvariant() -eq "0"
    return [pscustomobject]@{ indices = $idx; canceled = $canceled }
}
function Select-Items($items, [scriptblock]$formatter, [string]$prompt, [string]$invalidMsg) {
    if ($items.Count -eq 0) { return [pscustomobject]@{ items = @(); canceled = $false } }
    Write-ItemsInColumns $items $formatter
    Write-SelectionHint
    $selection = Read-SelectionIndices $prompt $items.Count $invalidMsg
    if ($selection.canceled) { return [pscustomobject]@{ items = @(); canceled = $true } }
    $idx = $selection.indices
    if ($idx.Count -eq 0) { return [pscustomobject]@{ items = @(); canceled = $false } }
    $selected = @()
    foreach ($n in $idx) { $selected += $items[$n - 1] }
    return [pscustomobject]@{ items = $selected; canceled = $false }
}

function Filter-Skills($items, [string]$filter) {
    if ([string]::IsNullOrWhiteSpace($filter)) { return $items }
    $f = $filter.Trim()
    if ($f.StartsWith("/") -and $f.EndsWith("/") -and $f.Length -gt 2) {
        $pattern = $f.Trim("/")
        try {
            return $items | Where-Object { $_.vendor -match $pattern -or $_.from -match $pattern }
        }
        catch {
            Write-Warning "无效的正则表达式：$pattern"
            return @()
        }
    }
    $terms = $f.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    foreach ($t in $terms) {
        $safeT = [WildcardPattern]::Escape($t)
        $items = $items | Where-Object { $_.vendor -like "*$safeT*" -or $_.from -like "*$safeT*" }
    }
    return $items
}

function Write-ItemsInColumns($items, [scriptblock]$formatter) {
    $count = $items.Count
    if ($count -eq 0) { return }
    $width = 120
    try { $width = [int]$Host.UI.RawUI.WindowSize.Width } catch {}
    $sample = @()
    for ($i = 0; $i -lt $count; $i++) {
        $sample += (& $formatter ($i + 1) $items[$i])
    }
    $maxLen = ($sample | Measure-Object -Maximum -Property Length).Maximum
    if (-not $maxLen) { $maxLen = 40 }
    $colWidth = $maxLen + 2
    $cols = [Math]::Max(1, [Math]::Floor($width / $colWidth))
    $rows = [Math]::Ceiling($count / $cols)
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $i = $r + ($c * $rows)
            if ($i -ge $count) { continue }
            $text = (& $formatter ($i + 1) $items[$i])
            $pad = " " * ($colWidth - $text.Length)
            Write-Host -NoNewline ($text + $pad)
        }
        Write-Host ""
    }
}

function Make-TargetName([string]$vendor, [string]$from) {
    $suffix = ($from -replace "[\\\\/]", "-")
    return ("{0}-{1}" -f $vendor, $suffix)
}

function 安装 {
    Preflight
    $cfg = LoadCfg
    $manualItems = 收集ManualSkills $cfg
    $filter = Read-Host "可选：关键词过滤（空格=AND，或 /regex/）"
    $all = 收集Skills "" $cfg $manualItems
    Need ($all.Count -gt 0) "未发现任何 skills。请先【新增技能库】。"
    $list = Hide-VendorRootSkills (Filter-Skills $all $filter)
    if ($list.Count -eq 0) {
        Write-Host "未发现匹配项。"
        return
    }
    $installed = Get-InstalledSet $cfg $manualItems

    $available = $list | Where-Object { -not $installed.Contains("$($_.vendor)|$($_.from)") }
    if ($available.Count -eq 0) {
        Write-Host "没有可安装的新技能。将直接执行【构建生效】。"
        构建生效
        return
    }

    $newMappings = @()
    foreach ($m in $cfg.mappings) { $newMappings += $m }
    $existing = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in $cfg.mappings) { $existing.Add("$($m.vendor)|$($m.from)") | Out-Null }
    $previewAdded = @()
    $previewMappings = @()

    $added = 0
    $selection = Select-Items $available `
    { param($idx, $item)
        $displayVendor = Get-DisplayVendor $item
        $leaf = Split-Path $item.from -Leaf
        if ($item.from -eq ".") { $leaf = $displayVendor }
        return ("{0,3}) [{1}] {2}" -f $idx, $displayVendor, $leaf)
    } `
        "请选择要安装的技能（批量安装到白名单）" `
        "未解析到有效序号（可能是分隔符或范围格式问题）。已取消写入白名单。"
    if ($selection.canceled) {
        Write-Host "已取消安装。"
        return
    }
    $selected = $selection.items
    if ($selected.Count -eq 0) {
        Write-Host "未选择新增技能。将直接执行【构建生效】。"
        构建生效
        return
    }

    foreach ($item in $selected) {
        $key = "$($item.vendor)|$($item.from)"
        if ($existing.Contains($key)) { continue }
        $to = Make-TargetName $item.vendor $item.from

        $newMappings += @{ vendor = $item.vendor; from = $item.from; to = $to }
        $existing.Add($key) | Out-Null
        $added++
        $previewItem = [ordered]@{ vendor = $item.vendor; from = $item.from; to = $to }
        if ($item.PSObject.Properties.Match("display_vendor").Count -gt 0) {
            $previewItem.display_vendor = [string]$item.display_vendor
        }
        $previewMappings += [pscustomobject]$previewItem
    }

    if ($added -eq 0) {
        Write-Host "未新增任何技能。将直接执行【构建生效】。"
        构建生效
        return
    }

    $previewAdded = Format-MappingPreview $previewMappings
    if (-not (Confirm-WithSummary "将新增以下白名单映射" $previewAdded "确认写入白名单并构建生效？" "Y")) {
        Write-Host "已取消安装。"
        return
    }
    if (Skip-IfDryRun "安装技能") { return }

    $cfg.mappings = $newMappings
    SaveCfg $cfg

    Write-Host ("已追加安装：{0} 项。开始【构建生效】..." -f $added)
    构建生效
}

function 卸载 {
    Preflight
    $cfg = LoadCfg
    $manualItems = 收集ManualSkills $cfg
    $overrideItems = 收集OverridesSkills
    $filter = Read-Host "可选：关键词过滤（空格=AND，或 /regex/）"

    # 卸载范围：vendor 映射 + manual 目录 + overrides 目录（含已禁用）
    $installedSet = Get-InstalledSet $cfg $manualItems $overrideItems
    $all = 收集Skills "" $cfg $manualItems
    $all += $overrideItems
    Need ($all.Count -gt 0) "未发现任何 skills。请先【新增技能库】。"
    $list = Filter-Skills $all $filter
    if ($list.Count -eq 0) {
        Write-Host "未发现匹配项。"
        return
    }

    # 筛选已安装的技能
    $onlyInstalled = $list | Where-Object { $installedSet.Contains("$($_.vendor)|$($_.from)") }
    $onlyInstalled = Hide-VendorRootSkills $onlyInstalled
    if ($onlyInstalled.Count -eq 0) {
        Write-Host "没有已安装的技能可卸载。"
        return
    }

    $selection = Select-Items $onlyInstalled `
    { param($idx, $item)
        $label = Get-DisplayVendor $item
        $leaf = Split-Path $item.from -Leaf
        if ($item.from -eq ".") { $leaf = $label }
        return ("{0,3}) [{1}] {2}" -f $idx, $label, $leaf)
    } `
        "请选择要卸载的技能（从白名单移除）" `
        "未解析到有效序号（可能是分隔符或范围格式问题）。已取消操作。"
    if ($selection.canceled) {
        Write-Host "已取消卸载。"
        return
    }
    $selectedItems = $selection.items
    if ($selectedItems.Count -eq 0) {
        Write-Host "未选择任何技能。"
        return
    }

    # 区分处理：vendor 移除白名单；manual 删除 imports 条目（兼容清理 legacy manual 目录）；overrides 备份后删除
    $preview = Format-SkillPreview $selectedItems
    if (-not (Confirm-WithSummary "将卸载以下技能" $preview "确认卸载所选技能？" "Y")) {
        Write-Host "已取消卸载。"
        return
    }
    if (Skip-IfDryRun "卸载技能") { return }

    $removedMappings = 0
    $removedVendorImports = 0
    $deletedManualImports = 0
    $deletedLegacyManualDirs = 0
    $deletedOverrides = 0
    $backedOverrides = 0
    foreach ($item in $selectedItems) {
        if ($item.vendor -eq "manual") {
            $before = @($cfg.imports).Count
            $cfg.imports = @($cfg.imports | Where-Object { -not ($_.mode -eq "manual" -and $_.name -eq $item.from) })
            $deletedManualImports += ($before - @($cfg.imports).Count)

            $legacyPath = Join-Path $ManualDir $item.from
            if (Test-Path $legacyPath) {
                Invoke-RemoveItem $legacyPath -Recurse
                $deletedLegacyManualDirs++
            }
            $cfg.mappings = $cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "manual|$($item.from)") }
        }
        elseif ($item.vendor -eq "overrides") {
            $bak = Backup-OverrideDir $item.from
            if ($bak) { $backedOverrides++ }
            $deletedOverrides++
        }
        else {
            # mapping 技能：从 mappings 移除
            $cfg.mappings = @($cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "$($item.vendor)|$($item.from)") })
            $removedMappings++

            $skillPath = Normalize-SkillPath ([string]$item.from)
            $hasSameMapping = @($cfg.mappings | Where-Object { $_.vendor -eq $item.vendor -and $_.from -eq $skillPath }).Count -gt 0
            if (-not $hasSameMapping) {
                $beforeImports = @($cfg.imports).Count
                $cfg.imports = @($cfg.imports | Where-Object {
                        $mode = if ($_.PSObject.Properties.Match("mode").Count -gt 0) { [string]$_.mode } else { "manual" }
                        if ($mode -ne "vendor") { return $true }
                        if ([string]$_.name -ne [string]$item.vendor) { return $true }
                        $importSkill = Normalize-SkillPath ([string]$_.skill)
                        return ($importSkill -ne $skillPath)
                    })
                $removedVendorImports += ($beforeImports - @($cfg.imports).Count)
            }
        }
    }

    SaveCfg $cfg
    $parts = @()
    if ($removedMappings -gt 0) { $parts += "移除白名单 $removedMappings 项" }
    if ($removedVendorImports -gt 0) { $parts += "删除 vendor 导入 $removedVendorImports 项" }
    if ($deletedManualImports -gt 0) { $parts += "删除 manual 导入 $deletedManualImports 项" }
    if ($deletedLegacyManualDirs -gt 0) { $parts += "清理 legacy manual 目录 $deletedLegacyManualDirs 项" }
    if ($deletedOverrides -gt 0) { $parts += "删除 overrides $deletedOverrides 项（已备份 $backedOverrides 项）" }
    Write-Host ("已完成：{0}。开始【构建生效】..." -f ($parts -join "，"))
    if ($backedOverrides -gt 0) {
        Write-Host "提示：overrides 备份已保存到 overrides/.bak/，如需彻底清理可手动删除该目录或其中备份。"
    }
    Clear-SkillsCache
    构建生效
}

function 选择 {
    Write-Host "提示：已改为独立【安装/卸载】菜单。"
    安装
}


function 发现 {
    Invoke-WithMetric "discover" {
        Preflight
        $cfg = LoadCfg
        $manualItems = 收集ManualSkills $cfg
        $f = $Filter
        if ([string]::IsNullOrWhiteSpace($f)) {
            $f = Read-Host "可选：关键词过滤（空格=AND，或 /regex/）"
        }
        $all = 收集Skills "" $cfg $manualItems
        Need ($all.Count -gt 0) "未发现任何 skills。请先【新增技能库】。"
        $list = Hide-VendorRootSkills (Filter-Skills $all $f)
        if ($list.Count -eq 0) {
            Write-Host "未发现匹配项。"
            return
        }
        $installed = Get-InstalledSet $cfg $manualItems
        Write-ItemsInColumns $list { param($idx, $item)
            $mark = if ($installed.Contains("$($item.vendor)|$($item.from)")) { "*" } else { " " }
            $displayVendor = Get-DisplayVendor $item
            $leaf = Split-Path $item.from -Leaf
            if ($item.from -eq ".") { $leaf = $displayVendor }
            return ("{0,3}) [{1}] [{2}] {3}" -f $idx, $mark, $displayVendor, $leaf)
        }
    } @{ command = "发现" } -NoHost
}

function 清空Agent目录 {
    if (Test-Path $AgentDir) {
        Invoke-RemoveItemWithRetry $AgentDir -Recurse | Out-Null
    }
    EnsureDir $AgentDir
}

function Resolve-SourceBase([string]$vendorName, $cfg) {
    if ($vendorName -eq "manual") { return $null }
    $v = $cfg.vendors | Where-Object { $_.name -eq $vendorName } | Select-Object -First 1
    if (-not $v) { throw "白名单引用了不存在的 vendor：$vendorName" }
    return (VendorPath $v.name)
}

function Get-BuildCachePath {
    return (Join-Path $Root ".build-cache.json")
}

function ConvertTo-Hashtable($obj) {
    $table = @{}
    if ($null -eq $obj) { return $table }
    if ($obj -is [hashtable]) { return $obj }
    if ($obj -is [pscustomobject]) {
        foreach ($p in $obj.PSObject.Properties) { $table[[string]$p.Name] = $p.Value }
    }
    return $table
}

function Load-BuildCache {
    $path = Get-BuildCachePath
    if (-not (Test-Path $path)) { return @{} }
    try {
        $raw = Get-Content $path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        $obj = $raw | ConvertFrom-Json
        return (ConvertTo-Hashtable $obj)
    }
    catch {
        Log ("构建缓存读取失败，已忽略并重建：{0}" -f $_.Exception.Message) "WARN"
        return @{}
    }
}

function Save-BuildCache($cache) {
    if ($DryRun) { return }
    try {
        $json = $cache | ConvertTo-Json -Depth 20
        Set-ContentUtf8 (Get-BuildCachePath) $json
    }
    catch {
        Log ("构建缓存保存失败（已忽略）：{0}" -f $_.Exception.Message) "WARN"
    }
}

function Get-DirectoryFingerprint([string]$dir) {
    if (-not (Test-Path $dir)) { return "missing" }
    $files = Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($dir.Length).TrimStart("\")
        $parts.Add(("{0}|{1}|{2}" -f $rel, [string]$f.Length, [string]$f.LastWriteTimeUtc.Ticks)) | Out-Null
    }
    $input = $parts -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Mirror-SkillWithCache(
    [string]$src,
    [string]$dst,
    [string]$cacheKey,
    [hashtable]$oldCache,
    [hashtable]$newCache,
    $stats
) {
    $fp = Get-DirectoryFingerprint $src
    $newCache[$cacheKey] = $fp
    $old = if ($oldCache.ContainsKey($cacheKey)) { [string]$oldCache[$cacheKey] } else { "" }
    if ((Test-Path $dst) -and $old -eq $fp) {
        $expanded = Expand-RelativeSkillPlaceholders $dst
        if ($expanded -gt 0) {
            Log ("命中构建缓存后补展开相对路径 SKILL 占位文件：{0} 项 [{1}]" -f $expanded, $cacheKey)
        }
        $stats.skipped++
        Log ("命中构建缓存，跳过复制：{0}" -f $cacheKey)
        return
    }
    RoboMirror $src $dst
    $expanded = Expand-RelativeSkillPlaceholders $dst
    if ($expanded -gt 0) {
        Log ("已展开相对路径 SKILL 占位文件：{0} 项 [{1}]" -f $expanded, $cacheKey)
    }
    $stats.mirrored++
}

function Get-SkillNameConflictBuckets([string]$agentRoot) {
    $nameToPaths = @{}
    foreach ($skillFile in (Get-ChildItem $agentRoot -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue)) {
        $declaredName = $null
        foreach ($line in (Get-Content $skillFile.FullName -TotalCount 80 -ErrorAction SilentlyContinue)) {
            if ($line -match "^\s*name:\s*(.+?)\s*$") {
                $declaredName = $Matches[1].Trim().Trim("'`"")
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($declaredName)) { continue }
        if (-not $nameToPaths.ContainsKey($declaredName)) {
            $nameToPaths[$declaredName] = New-Object System.Collections.Generic.List[string]
        }
        $nameToPaths[$declaredName].Add($skillFile.FullName) | Out-Null
    }
    return $nameToPaths
}

function Test-SkillNameDuplicateContentAllowed([string[]]$paths) {
    if ($null -eq $paths -or $paths.Count -le 1) { return $true }
    $hashes = New-Object System.Collections.Generic.HashSet[string]
    foreach ($path in $paths) {
        $hash = Get-FileContentHash $path
        if ([string]::IsNullOrWhiteSpace($hash)) { return $false }
        $hashes.Add($hash) | Out-Null
    }
    return ($hashes.Count -le 1)
}

function Test-SkillNameSystemOverrideAllowed([string[]]$paths) {
    if ($null -eq $paths -or $paths.Count -le 1) { return $false }
    $hasSystemPath = $false
    $hasNonSystemPath = $false
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($path -match "[\\/]\.system[\\/]") { $hasSystemPath = $true }
        else { $hasNonSystemPath = $true }
    }
    return ($hasSystemPath -and $hasNonSystemPath)
}

function Start-BuildTransaction {
    $txnRoot = Join-Path $Root ".txn"
    $txnId = [Guid]::NewGuid().ToString("N").Substring(0, 10)
    $path = Join-Path $txnRoot ("build-{0}" -f $txnId)
    $backupAgent = Join-Path $path "agent.backup"
    $state = [ordered]@{
        path = $path
        backup_agent = $backupAgent
        has_backup_agent = $false
        backup_error = $null
    }
    if ($DryRun) { return [pscustomobject]$state }
    EnsureDir $txnRoot
    EnsureDir $path
    if (Test-Path $AgentDir) {
        try {
            Invoke-MoveItem $AgentDir $backupAgent
            $state.has_backup_agent = $true
        }
        catch {
            if (Test-Path $backupAgent) { Invoke-RemoveItemWithRetry $backupAgent -Recurse -IgnoreFailure -SilentIgnore | Out-Null }
            $state.backup_error = $_.Exception.Message
            Log ("旧 agent/ 无法挪入事务备份，后续将直接在原目录上构建：{0}" -f $_.Exception.Message)
        }
    }
    return [pscustomobject]$state
}

function Rollback-BuildTransaction($txn) {
    if ($DryRun -or $null -eq $txn) { return }
    try {
        if (Test-Path $AgentDir) { Invoke-RemoveItemWithRetry $AgentDir -Recurse -IgnoreFailure -SilentIgnore | Out-Null }
        if ($txn.has_backup_agent -and (Test-Path $txn.backup_agent)) {
            Invoke-MoveItem $txn.backup_agent $AgentDir
            Write-Host "已回滚 agent/ 到构建前状态。" -ForegroundColor Yellow
        }
    }
    finally {
        if (Test-Path $txn.path) { Invoke-RemoveItemWithRetry $txn.path -Recurse -IgnoreFailure -SilentIgnore | Out-Null }
    }
}

function Complete-BuildTransaction($txn) {
    if ($DryRun -or $null -eq $txn) { return }
    if (Test-Path $txn.path) { Invoke-RemoveItemWithRetry $txn.path -Recurse -IgnoreFailure -SilentIgnore | Out-Null }
}

function 构建Agent($cfg = $null, [switch]$SkipPreflight, $Txn = $null) {
    return (Invoke-WithMetric "build_agent" {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        Log "开始构建 Agent..."
        $reusedExistingAgent = $false
        $cleanAgentError = $null
        try {
            清空Agent目录
        }
        catch {
            $reusedExistingAgent = $true
            $cleanAgentError = $_.Exception.Message
            EnsureDir $AgentDir
            Log ("清空 agent/ 失败，将在现有目录上继续覆盖构建：{0}" -f $_.Exception.Message)
        }
        $failures = New-Object System.Collections.Generic.List[string]
        if ($null -ne $Txn -and $Txn.PSObject.Properties.Match("backup_error").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Txn.backup_error)) {
            $failures.Add(("build-txn:agent-backup => {0}" -f $Txn.backup_error)) | Out-Null
        }
        $stats = [pscustomobject]@{ mirrored = 0; skipped = 0; reused = $reusedExistingAgent }
        $oldCache = if ($DryRun) { @{} } else { Load-BuildCache }
        $newCache = @{}

        $count = 0
        foreach ($m in $cfg.mappings) {
            try {
                if (-not (Should-SyncMappingToAgent $m)) {
                    Log ("跳过 vendor 根映射（不参与同步）：{0}/{1}" -f $m.vendor, $m.from)
                    continue
                }
                Need (Test-SafeRelativePath $m.from -AllowDot) ("非法 mapping.from：{0}" -f $m.from)
                Need (Test-SafeRelativePath $m.to) ("非法 mapping.to：{0}" -f $m.to)
                $base = Resolve-SourceBase $m.vendor $cfg
                if ($m.vendor -eq "manual") {
                    $src = Resolve-ManualImportSkillPath $cfg $m.from -AllowLegacyFallback
                    Need (-not [string]::IsNullOrWhiteSpace($src)) ("manual 导入不存在或无效：{0}" -f $m.from)
                }
                else {
                    $src = Join-Path $base $m.from
                    Need (Is-PathInsideOrEqual $src $base) ("mapping.from 越界：{0}" -f $m.from)
                }
                $dst = Join-Path $AgentDir $m.to
                Need (Is-PathInsideOrEqual $dst $AgentDir) ("mapping.to 越界：{0}" -f $m.to)

                if (-not (Test-IsSkillDir $src)) {
                    Write-Host ("❌ 跳过无效技能（缺少标记文件）：{0}" -f $src) -ForegroundColor Red
                    continue
                }
                $cacheKey = ("mapping|{0}|{1}|{2}" -f $m.vendor, $m.from, $m.to)
                Mirror-SkillWithCache $src $dst $cacheKey $oldCache $newCache $stats
                $count++
            }
            catch {
                Write-Host ("❌ 处理技能失败 [{0}/{1}]: {2}" -f $m.vendor, $m.from, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("mapping:{0}/{1} => {2}" -f $m.vendor, $m.from, $_.Exception.Message)) | Out-Null
            }
        }

        $manualItems = 收集ManualSkills $cfg
        if ($manualItems.Count -gt 0) {
            $manualMapped = New-Object System.Collections.Generic.HashSet[string]
            $existingTo = New-Object System.Collections.Generic.HashSet[string]
            foreach ($m in $cfg.mappings) {
                $existingTo.Add($m.to) | Out-Null
                if ($m.vendor -eq "manual") { $manualMapped.Add($m.from) | Out-Null }
            }

            foreach ($item in $manualItems) {
                try {
                    if ($manualMapped.Contains($item.from)) {
                        Log ("跳过手动技能（已存在 manual 映射）：{0}" -f $item.from) "WARN"
                        continue
                    }
                    $toSuffix = ($item.from -replace "[\\\\/]", "-")
                    $to = "manual-$toSuffix"
                    if ($existingTo.Contains($to)) {
                        Log ("跳过手动技能（to 冲突）：{0} -> {1}" -f $item.from, $to) "WARN"
                        continue
                    }
                    $src = $item.full
                    $dst = Join-Path $AgentDir $to

                    if (-not (Test-IsSkillDir $src)) {
                        Write-Host ("❌ 跳过无效技能（缺少标记文件）：{0}" -f $src) -ForegroundColor Red
                        continue
                    }
                    $cacheKey = ("manual|{0}|{1}" -f $item.from, $to)
                    Mirror-SkillWithCache $src $dst $cacheKey $oldCache $newCache $stats
                    $count++
                }
                catch {
                    Write-Host ("❌ 处理手动技能失败 [{0}]: {1}" -f $item.from, $_.Exception.Message) -ForegroundColor Red
                    $failures.Add(("manual:{0} => {1}" -f $item.from, $_.Exception.Message)) | Out-Null
                }
            }
        }

        # overrides 覆盖层（可选）：同名目录将覆盖 agent 中对应技能
        foreach ($d in (Get-OverridesDirs)) {
            try {
                $dst = Join-Path $AgentDir $d.Name
                $cacheKey = ("override|{0}" -f $d.Name)
                Mirror-SkillWithCache $d.FullName $dst $cacheKey $oldCache $newCache $stats
                Log ("应用覆盖层: {0}" -f $d.Name)
            }
            catch {
                Write-Host ("❌ 应用覆盖层失败 [{0}]: {1}" -f $d.Name, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("override:{0} => {1}" -f $d.Name, $_.Exception.Message)) | Out-Null
            }
        }

        $removedVendorRoots = Remove-VendorRootMappingOutputsFromAgent $cfg
        if ($removedVendorRoots -gt 0) {
            Log ("已剔除 {0} 个 vendor 根映射目录（不参与同步）。" -f $removedVendorRoots)
        }

        $normalizedSkillMd = Normalize-SkillMarkdownFiles $AgentDir
        if ($normalizedSkillMd.normalized -gt 0) {
            Log ("已归一化 SKILL.md 编码（移除 UTF-8 BOM）：{0} 项" -f $normalizedSkillMd.normalized)
        }
        if ($normalizedSkillMd.failed -gt 0) {
            foreach ($path in $normalizedSkillMd.failed_paths) {
                $failures.Add(("build-skill-md-normalize:{0}" -f $path)) | Out-Null
            }
        }

        $invalidSkillCleanup = Remove-InvalidSkillMarkdownFiles $AgentDir
        if ($invalidSkillCleanup.removed -gt 0) {
            Log ("已清理无效 SKILL.md（缺少 YAML frontmatter）：{0} 项" -f $invalidSkillCleanup.removed) "WARN"
        }
        if ($invalidSkillCleanup.failed -gt 0) {
            foreach ($path in $invalidSkillCleanup.failed_paths) {
                $failures.Add(("build-invalid-skill-md-cleanup:{0}" -f $path)) | Out-Null
            }
        }

        $nameToPaths = Get-SkillNameConflictBuckets $AgentDir
        foreach ($name in $nameToPaths.Keys | Sort-Object) {
            $paths = @($nameToPaths[$name])
            if ($paths.Count -le 1) { continue }
            if (Test-SkillNameDuplicateContentAllowed $paths) {
                Log ("检测到同名同内容技能别名，已跳过冲突：{0}" -f $name)
                continue
            }
            if (Test-SkillNameSystemOverrideAllowed $paths) {
                Log ("检测到系统技能与普通技能同名，已保留系统技能优先：{0}" -f $name)
                continue
            }
            Write-Host ("❌ 技能名冲突：{0}" -f $name) -ForegroundColor Red
            foreach ($p in $paths) {
                Write-Host ("   - {0}" -f $p) -ForegroundColor Red
            }
            $failures.Add(("skill-name-conflict:{0} => {1}" -f $name, ($paths -join " | "))) | Out-Null
        }

        if (-not $DryRun) { Save-BuildCache $newCache }
        if ($stats.skipped -gt 0) {
            Log ("增量构建：复用缓存 {0} 项，实际复制 {1} 项。" -f $stats.skipped, $stats.mirrored)
        }
        if ($stats.reused) {
            Log "本次构建未能清空旧 agent/，已按目录增量覆盖；若仍有陈旧技能残留，可在释放相关文件占用后重试。"
            Write-Host "❌ 检测到在旧 agent/ 上增量覆盖构建，已升级为失败。" -ForegroundColor Red
            Write-Host "   建议：先执行【解除关联】并关闭占用进程，再重试【构建生效】。" -ForegroundColor Red
            if ([string]::IsNullOrWhiteSpace($cleanAgentError)) { $cleanAgentError = "unknown error" }
            $failures.Add(("build-agent-reused-existing-dir => {0}" -f $cleanAgentError)) | Out-Null
        }
        $count = @((Get-ChildItem -LiteralPath $AgentDir -Directory -ErrorAction SilentlyContinue)).Count
        Log ("构建完成：agent/ (共 {0} 项技能)" -f $count)
        return $failures.ToArray()
    } @{ command = "构建Agent" } -NoHost)
}

function Resolve-TargetDir([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if ($path.StartsWith("~")) {
        $homeDir = [Environment]::GetFolderPath("UserProfile")
        $path = $path -replace "^~", $homeDir
    }
    # Normalize slashes for Windows CMD compatibility
    $path = $path.Replace("/", "\")
  
    if ([System.IO.Path]::IsPathRooted($path)) {
        return $path
    }
    return (Join-Path $Root $path)
}

function 应用到ClaudeCodex($cfg = $null, [switch]$SkipPreflight) {
    return (Invoke-WithMetric "apply_targets" {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        $mode = $cfg.sync_mode
        if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "link" }
        $failures = New-Object System.Collections.Generic.List[string]

        foreach ($t in $cfg.targets) {
            try {
                $target = Resolve-TargetDir $t.path
                if (-not $target) { continue }
                Assert-SafeTargetDir $target

                if ($mode -eq "sync") {
                    EnsureDir $target
                    RoboMirror $AgentDir $target
                    Log ("已同步（拷贝）：{0}" -f $t.path)
                }
                else {
                    New-Junction $target $AgentDir
                    Log ("已关联（链接）：{0} -> agent/" -f $t.path)
                }
            }
            catch {
                Write-Host ("❌ 同步目标失败 [{0}]: {1}" -f $t.path, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("target:{0} => {1}" -f $t.path, $_.Exception.Message)) | Out-Null
            }
        }
        return $failures.ToArray()
    } @{ command = "应用到ClaudeCodex" } -NoHost)
}
function Write-FailureSummary([string]$title, [string[]]$failures, [string]$detailHint = "") {
    if ($null -eq $failures -or $failures.Count -eq 0) { return }
    $msg = ("{0}（{1} 项）" -f $title, $failures.Count)
    if (-not [string]::IsNullOrWhiteSpace($detailHint)) {
        $msg = ("{0}，{1}" -f $msg, $detailHint)
    }
    Write-Host $msg -ForegroundColor Yellow
    foreach ($f in ($failures | Select-Object -First 10)) {
        Write-Host ("- {0}" -f $f) -ForegroundColor Yellow
    }
    if ($failures.Count -gt 10) {
        Write-Host ("... 另有 {0} 项未显示" -f ($failures.Count - 10)) -ForegroundColor Yellow
    }
}

function 构建生效 {
    Invoke-WithMetric "build_apply_total" {
        Preflight
        Invoke-PrebuildCheck
        $cfg = LoadCfg
        if ($Locked) {
            Ensure-LockedState $cfg | Out-Null
        }
        $txn = Start-BuildTransaction
        $needRollback = $false

        # Optimization/Migration check
        Optimize-Imports $cfg

        Write-BuildSummary $cfg
        Log "=== 启动构建生效流程 ==="
        Start-DryRunMirrorCollect
        try {
            $failures = @()
            $buildFailures = 构建Agent $cfg -SkipPreflight -Txn $txn
            if ($buildFailures) { $failures += $buildFailures }
            if ($buildFailures -and $buildFailures.Count -gt 0) {
                Log "检测到构建失败，已跳过同步阶段。" "WARN"
                Write-Host "⚠️ 构建失败，未执行同步。请先修复上方错误后重试【构建生效】。" -ForegroundColor Yellow
            }
            else {
                $syncFailures = 应用到ClaudeCodex $cfg -SkipPreflight
                if ($syncFailures) { $failures += $syncFailures }
            }
            Write-FailureSummary "构建生效部分失败" $failures
            if ($failures.Count -gt 0) { $needRollback = $true }
            Write-DryRunMirrorSummary "DRYRUN Robocopy 预览（构建生效）"
        }
        finally {
            Stop-DryRunMirrorCollect
        }
        if ($needRollback) {
            Rollback-BuildTransaction $txn
            Write-Host "⚠️ 已回滚本次构建产物（agent/）。同步目标可能仍需手动重建。" -ForegroundColor Yellow
        }
        else {
            Complete-BuildTransaction $txn
        }
        Log "=== 构建生效流程完成 ==="
    } @{ command = "构建生效" } -NoHost
}

function 命令导入安装 {
    Write-Host "可一次性粘贴一条或多条命令，空行结束。示例："
    Write-Host "  add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
    Write-Host "  npx skills add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
    Write-Host "说明："
    Write-Host "  - 支持连续粘贴多条 add / npx skills add / npx add-skill 命令"
    Write-Host "  - 未指定 --skill 时：仅新增技能库（vendor），不自动安装仓库内技能"
    Write-Host "  - 行尾用 \\ 可续行，脚本会自动拼接为一条命令"
    $lines = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $line = Read-Host "输入命令"
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $trim = $line.Trim()
        if ($trim.StartsWith("#") -or $trim.StartsWith("//")) { continue }
        $lines.Add($line) | Out-Null
    }
    if ($lines.Count -eq 0) {
        Write-Host "未输入参数，已取消。"
        return
    }

    $commands = New-Object System.Collections.Generic.List[string]
    $pending = ""
    foreach ($raw in $lines) {
        $part = [string]$raw
        $trimmed = $part.TrimEnd()
        $continued = $trimmed.EndsWith("\")
        if ($continued) {
            $trimmed = $trimmed.Substring(0, $trimmed.Length - 1).TrimEnd()
        }
        if ([string]::IsNullOrWhiteSpace($pending)) { $pending = $trimmed }
        else { $pending = ("{0} {1}" -f $pending, $trimmed).Trim() }
        if (-not $continued) {
            if (-not [string]::IsNullOrWhiteSpace($pending)) { $commands.Add($pending) | Out-Null }
            $pending = ""
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($pending)) {
        Write-Host "警告：检测到末行续行符 '\\'，已按当前内容尝试执行。" -ForegroundColor Yellow
        $commands.Add($pending) | Out-Null
    }

    $successCount = 0
    foreach ($line in $commands) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lineTrim = $line.Trim()
        if ($lineTrim.StartsWith("#") -or $lineTrim.StartsWith("//")) { continue }
        $tokens = Split-Args $line
        if ($tokens.Count -eq 0) { continue }
        try {
            $tokens = Get-AddTokensFromCommandLineTokens $tokens
            if ($tokens.Count -eq 0) { continue }
            if (Add-ImportFromArgs $tokens -NoBuild) { $successCount++ }
        }
        catch {
            Write-Host ("❌ 解析失败（已跳过）：{0}" -f $_.Exception.Message) -ForegroundColor Red
            if ($line -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@.+$") {
                Write-Host "提示：你可能使用了 repo@skill 语法。可改为：npx ""skills add <repo> --skill <path>""" -ForegroundColor Yellow
            }
        }
    }
    if ($successCount -gt 0) {
        Write-Host ("多行导入完成：{0} 项。开始【构建生效】..." -f $successCount)
        Clear-SkillsCache
        构建生效
    }
}

function 单技能安装 {
    命令导入安装
}
