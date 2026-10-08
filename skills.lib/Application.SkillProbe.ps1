function Test-NeedsSparseProbeFallback([string]$msg) {
    if ([string]::IsNullOrWhiteSpace($msg)) { return $false }
    return ($msg -match "unable to checkout working tree|checkout failed|git restore --source=HEAD :/|invalid path|Filename too long|文件名.*太长|路径.*过长")
}
function Get-PreferredSkillCandidates($candidates) {
    $ordered = @($candidates | Sort-Object rel)
    if ($ordered.Count -le 1) { return $ordered }
    $preferred = @($ordered | Where-Object {
            $relGit = (($_.rel -as [string]) -replace "\\", "/")
            $relGit -match "^(\.claude/skills|skills)(/|$)"
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
