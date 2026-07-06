function Normalize-RepoUrl([string]$repo) {
    $r = $repo.Trim()
    if ($r -match "^(git@github.com:).+") {
        if (-not $r.EndsWith(".git")) { return ($r + ".git") }
        return $r
    }
    if ($r -match "^https?://github.com/.+") {
        if (-not $r.EndsWith(".git")) { return ($r + ".git") }
        return $r
    }
    if ($r -match "^github.com/.+") {
        $u = "https://{0}" -f $r
        if (-not $u.EndsWith(".git")) { $u += ".git" }
        return $u
    }
    if ($r -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
        return ("https://github.com/{0}.git" -f $r)
    }
    return $r
}
function Remove-GitHubTreeSuffix([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $repo }
    $r = $repo.Trim().Trim("'`"")
    if ($r -match "^(https?://github\.com/[^/]+/[^/]+?)(?:\.git)?/tree/[^/]+/.+$") {
        return ($Matches[1] + ".git")
    }
    return $r
}
function Guess-VendorName([string]$repo) {
    $r = $repo.Trim().TrimEnd("/")
    if ($r.EndsWith(".git")) { $r = $r.Substring(0, $r.Length - 4) }
    $leaf = Split-Path $r -Leaf
    $name = Normalize-Name $leaf
    if ([string]::IsNullOrWhiteSpace($name)) {
        if ($repo -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@.+$") {
            throw "无法从 URL 推断 vendor 名称。检测到 repo@skill 写法，请改用：<repo> --skill <name>（例如：vercel-labs/skills --skill skills/find-skills）"
        }
        throw "无法从 URL 推断 vendor 名称，请手动输入名称。"
    }
    return $name
}
function Invoke-Git([string[]]$GitArgs) {
    if ($DryRun) {
        Log ("DRYRUN git {0}" -f ($GitArgs -join " "))
        return
    }
    $cmdText = ("git {0}" -f ($GitArgs -join " "))
    $retriedAfterLockRecovery = $false
    $canTuneNativeErrPref = ($PSVersionTable.PSVersion.Major -ge 7)
    while ($true) {
        Log $cmdText
        $prevNativeErrorPref = $null
        $prevErrorActionPreference = $ErrorActionPreference
        try {
            if ($canTuneNativeErrPref) {
                $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
                $PSNativeCommandUseErrorActionPreference = $false
            }
            $ErrorActionPreference = "Continue"
            $output = & git @GitArgs 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $prevErrorActionPreference
            if ($canTuneNativeErrPref) {
                $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
            }
        }
        if ($output) {
            foreach ($line in @($output)) {
                $text = Convert-GitOutputLineToText $line
                if ([string]::IsNullOrWhiteSpace($text)) { continue }
                Write-Host $text
            }
        }
        if ($exitCode -eq 0) { return }
        if (-not $retriedAfterLockRecovery) {
            $repaired = $false
            if (Repair-StaleGitLockFromOutput $output) {
                $repaired = $true
            }
            elseif (Repair-StaleGitLockAfterFailure (Get-Location).Path $output) {
                $repaired = $true
            }
            if ($repaired) {
                $retriedAfterLockRecovery = $true
                continue
            }
        }
        $summary = Get-GitOutputSummary $output
        if ([string]::IsNullOrWhiteSpace($summary)) {
            throw ("git 失败：{0}" -f $cmdText)
        }
        throw ("git 失败：{0}；详情：{1}" -f $cmdText, $summary)
    }
}
function Invoke-GitCapture([string[]]$GitArgs) {
    if ($DryRun) {
        Log ("DRYRUN git {0}" -f ($GitArgs -join " "))
        return ""
    }
    Log ("git {0}" -f ($GitArgs -join " "))
    $canTuneNativeErrPref = ($PSVersionTable.PSVersion.Major -ge 7)
    $prevNativeErrorPref = $null
    $prevErrorActionPreference = $ErrorActionPreference
    try {
        if ($canTuneNativeErrPref) {
            $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
        }
        $ErrorActionPreference = "Continue"
        $out = & git @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
    }
    finally {
        $ErrorActionPreference = $prevErrorActionPreference
        if ($canTuneNativeErrPref) {
            $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
        }
    }
    if ($null -eq $out) { return "" }
    return (($out | Select-Object -First 1).ToString().Trim())
}
function Invoke-GitCaptureLines([string[]]$GitArgs) {
    if ($DryRun) {
        Log ("DRYRUN git {0}" -f ($GitArgs -join " "))
        return @()
    }
    Log ("git {0}" -f ($GitArgs -join " "))
    $canTuneNativeErrPref = ($PSVersionTable.PSVersion.Major -ge 7)
    $prevNativeErrorPref = $null
    $prevErrorActionPreference = $ErrorActionPreference
    try {
        if ($canTuneNativeErrPref) {
            $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
        }
        $ErrorActionPreference = "Continue"
        $out = & git @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
    }
    finally {
        $ErrorActionPreference = $prevErrorActionPreference
        if ($canTuneNativeErrPref) {
            $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
        }
    }
    $lines = @()
    foreach ($line in @($out)) {
        $text = Convert-GitOutputLineToText $line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $lines += $text
    }
    return ,$lines
}
function Get-SkillCandidatesFromGitRepo([string]$repo, [string]$ref) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"
    Need (-not [string]::IsNullOrWhiteSpace($ref)) "ref 不能为空。"

    $tmpName = ("_tree_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    $tmpBase = Join-Path $ImportDir $tmpName
    $barePath = Join-Path $tmpBase "repo.git"
    EnsureDir $tmpBase
    try {
        Invoke-Git @("clone", "--bare", $repo, $barePath)
        $gitDirArg = "--git-dir={0}" -f $barePath
        $allFiles = Invoke-GitCaptureLines @($gitDirArg, "ls-tree", "-r", "--name-only", $ref)
        $seenDirs = New-Object System.Collections.Generic.HashSet[string]
        $candidates = @()
        foreach ($f in $allFiles) {
            if ([string]::IsNullOrWhiteSpace($f)) { continue }
            if ($f -notmatch "(^|/)(SKILL|AGENTS|GEMINI|CLAUDE)\.md$") { continue }
            $dir = Split-Path ($f -replace "/", "\") -Parent
            if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
            $dirGit = ($dir -replace "\\", "/")
            if ($dirGit -match "(^|/)_archive(/|$)") { continue }
            if (-not $seenDirs.Add($dir)) { continue }
            $candidates += [pscustomobject]@{
                rel = $dir
                leaf = (Split-Path $dir -Leaf)
            }
        }
        return ,@($candidates | Sort-Object rel)
    }
    finally {
        Invoke-RemoveItemWithRetry $tmpBase -Recurse -IgnoreFailure | Out-Null
    }
}
function Assert-RepoReachable([string]$repo) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"
    if (Test-LocalZipRepoInput $repo) {
        return
    }
    $out = Invoke-GitCapture @("ls-remote", "--exit-code", $repo, "HEAD")
    if ([string]::IsNullOrWhiteSpace($out)) {
        throw ("仓库不可访问或不存在：{0}。请检查 owner/repo 是否正确，或确认仓库是否私有且当前 git 凭据可访问。" -f $repo)
    }
}
function Test-LocalZipRepoInput([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $false }
    $r = $repo.Trim().Trim("'`"")
    if ($r -notmatch "(?i)\.zip$") { return $false }
    return (Test-Path -LiteralPath $r -PathType Leaf)
}
function Invoke-WithRetry([scriptblock]$Action, [int]$MaxAttempts = 3, [int]$DelayMs = 250) {
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            & $Action
            return
        }
        catch {
            if ($attempt -ge $MaxAttempts) { throw }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}
function Resolve-ZipExtractionRoot([string]$extractDir) {
    Need (Test-Path $extractDir) ("解压目录不存在：{0}" -f $extractDir)
    $children = @(Get-ChildItem -LiteralPath $extractDir -Force -ErrorAction SilentlyContinue)
    $dirs = @($children | Where-Object { $_.PSIsContainer })
    $files = @($children | Where-Object { -not $_.PSIsContainer })
    if ($files.Count -eq 0 -and $dirs.Count -eq 1) {
        return $dirs[0].FullName
    }
    return $extractDir
}
function Ensure-RepoFromZip([string]$path, [string]$zipPath, [bool]$forceClean = $true) {
    $zip = $zipPath.Trim().Trim("'`"")
    Need (Test-Path -LiteralPath $zip -PathType Leaf) ("zip 文件不存在：{0}" -f $zipPath)

    if (Test-Path $path) {
        Need $forceClean ("缓存目录已存在且 update_force=false：{0}" -f $path)
        Invoke-RemoveItemWithRetry $path -Recurse
    }
    EnsureDir (Split-Path $path -Parent)

    $tmpName = ("_zip_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    $tmpBase = Join-Path $ImportDir $tmpName
    $tmpZip = Join-Path $tmpBase "source.zip"
    $extractDir = Join-Path $tmpBase "extract"
    EnsureDir $tmpBase
    try {
        Log ("Copy-Item {0} -> {1}" -f $zip, $tmpZip)
        Invoke-WithRetry { Copy-Item -LiteralPath $zip -Destination $tmpZip -Force } 3 250

        Log ("Expand-Archive {0} -> {1}" -f $tmpZip, $extractDir)
        Invoke-WithRetry { Expand-Archive -LiteralPath $tmpZip -DestinationPath $extractDir -Force } 3 250

        $sourceRoot = Resolve-ZipExtractionRoot $extractDir
        Invoke-MoveItem $sourceRoot $path
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match "由另一进程使用|being used by another process") {
            throw ("zip 文件当前被占用：{0}。请关闭占用进程后重试。" -f $zipPath)
        }
        throw
    }
    finally {
        Invoke-RemoveItemWithRetry $tmpBase -Recurse -IgnoreFailure
    }
}
function Ensure-RepoFromGitArchive([string]$path, [string]$repo, [string]$ref, [string]$skillPath, [bool]$forceClean = $true) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"
    Need (-not [string]::IsNullOrWhiteSpace($ref)) "ref 不能为空。"
    $normalizedSkill = Normalize-SkillPath $skillPath
    Need ($normalizedSkill -ne ".") "git archive 回退模式不支持根路径 '.'，请指定具体子目录。"

    if (Test-Path $path) {
        Need $forceClean ("缓存目录已存在且 update_force=false：{0}" -f $path)
        Invoke-RemoveItemWithRetry $path -Recurse
    }
    EnsureDir (Split-Path $path -Parent)
    EnsureDir $path

    $tmpName = ("_archive_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    $tmpBase = Join-Path $ImportDir $tmpName
    $barePath = Join-Path $tmpBase "repo.git"
    $zipPath = Join-Path $tmpBase "export.zip"
    EnsureDir $tmpBase
    try {
        Invoke-Git @("clone", "--bare", $repo, $barePath)
        $gitDirArg = "--git-dir={0}" -f $barePath
        $gitPath = To-GitPath $normalizedSkill
        Invoke-Git @($gitDirArg, "archive", "--format=zip", "--output", $zipPath, $ref, $gitPath)
        Expand-Archive -LiteralPath $zipPath -DestinationPath $path -Force
    }
    finally {
        Invoke-RemoveItemWithRetry $tmpBase -Recurse -IgnoreFailure
    }
}
function Resolve-GitHubOwnerRepo([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $null }
    $r = Remove-GitHubTreeSuffix $repo
    $r = $r.Trim().Trim("'`"")
    if ($r -match "^git@github\.com:(.+?)/(.+?)(?:\.git)?$") {
        return [pscustomobject]@{ owner = $Matches[1]; name = $Matches[2] }
    }
    if ($r -match "^https?://github\.com/(.+?)/(.+?)(?:\.git)?/?$") {
        return [pscustomobject]@{ owner = $Matches[1]; name = $Matches[2] }
    }
    if ($r -match "^github\.com/(.+?)/(.+?)(?:\.git)?/?$") {
        return [pscustomobject]@{ owner = $Matches[1]; name = $Matches[2] }
    }
    return $null
}
function Ensure-RepoFromGitHubTreeSnapshot([string]$path, [string]$repo, [string]$ref, [string]$skillPath, [bool]$forceClean = $true) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"
    Need (-not [string]::IsNullOrWhiteSpace($ref)) "ref 不能为空。"
    $normalizedSkill = Normalize-SkillPath $skillPath
    Need ($normalizedSkill -ne ".") "GitHub 快照回退不支持根路径 '.'，请指定具体子目录。"

    $ownerRepo = Resolve-GitHubOwnerRepo $repo
    Need ($null -ne $ownerRepo) ("GitHub 快照回退仅支持 github.com 仓库：{0}" -f $repo)

    if (Test-Path $path) {
        Need $forceClean ("缓存目录已存在且 update_force=false：{0}" -f $path)
        Invoke-RemoveItemWithRetry $path -Recurse
    }
    EnsureDir (Split-Path $path -Parent)
    EnsureDir $path

    $headers = @{
        "User-Agent" = "skills-manager"
        "Accept" = "application/vnd.github+json"
    }
    $encodedRef = [System.Uri]::EscapeDataString($ref)
    $treeUrl = ("https://api.github.com/repos/{0}/{1}/git/trees/{2}?recursive=1" -f $ownerRepo.owner, $ownerRepo.name, $encodedRef)
    $treeResp = Invoke-RestMethod -Uri $treeUrl -Headers $headers -Method Get -ErrorAction Stop
    Need ($treeResp -and $treeResp.tree) ("GitHub 树接口返回为空：{0}" -f $treeUrl)

    $prefix = (To-GitPath $normalizedSkill).Trim("/")
    Need (-not [string]::IsNullOrWhiteSpace($prefix)) "技能路径无效。"
    $prefixSlash = "$prefix/"

    $blobs = @($treeResp.tree | Where-Object {
            $_.type -eq "blob" -and $_.path -is [string] -and ($_.path -eq $prefix -or $_.path.StartsWith($prefixSlash))
        })
    Need ($blobs.Count -gt 0) ("GitHub 快照回退未找到目标路径：{0}" -f $normalizedSkill)

    foreach ($blob in $blobs) {
        $blobPath = [string]$blob.path
        if ([string]::IsNullOrWhiteSpace($blobPath)) { continue }
        $relPath = $blobPath -replace "/", "\"
        $dstPath = Join-Path $path $relPath
        EnsureDir (Split-Path $dstPath -Parent)

        $rawUrl = ("https://raw.githubusercontent.com/{0}/{1}/{2}/{3}" -f $ownerRepo.owner, $ownerRepo.name, $ref, $blobPath)
        Invoke-WebRequest -Uri $rawUrl -Headers @{ "User-Agent" = "skills-manager" } -OutFile $dstPath -ErrorAction Stop | Out-Null
    }
}
function Parse-DefaultBranchFromSymref([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
    $text = $line.Trim()
    if ($text -match "^ref:\s+refs/heads/(.+?)\s+HEAD$") {
        $branch = $Matches[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($branch)) { return $branch }
    }
    return $null
}
function Get-RepoDefaultBranch([string]$repo) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"

    $symrefLine = Invoke-GitCapture @("ls-remote", "--symref", $repo, "HEAD")
    $branch = Parse-DefaultBranchFromSymref $symrefLine
    if (-not [string]::IsNullOrWhiteSpace($branch)) { return $branch }

    foreach ($fallback in @("main", "master")) {
        $probe = Invoke-GitCapture @("ls-remote", "--exit-code", $repo, ("refs/heads/{0}" -f $fallback))
        if (-not [string]::IsNullOrWhiteSpace($probe)) {
            Log ("未能从 symref 解析默认分支，回退为已存在分支：{0}" -f $fallback)
            return $fallback
        }
    }

    Log "未能探测仓库默认分支，回退为 main。"
    return "main"
}
function Get-GitHeadBranch {
    $head = Invoke-GitCapture @("rev-parse", "--abbrev-ref", "HEAD")
    if ([string]::IsNullOrWhiteSpace($head) -or $head -eq "HEAD") { return $null }
    return $head
}
function Get-RepoIdentity([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $null }
    $r = Remove-GitHubTreeSuffix $repo
    $r = $r.Trim().Trim("'`"")
    if ($r -match "^ssh://git@github\.com/(.+?)/(.+?)(?:\.git)?/?$") {
        return ("github.com/{0}/{1}" -f $Matches[1], $Matches[2]).ToLowerInvariant()
    }
    if ($r -match "^git@github\.com:(.+)$") {
        $r = "https://github.com/$($Matches[1])"
    }
    $n = Normalize-RepoUrl $r
    if ([string]::IsNullOrWhiteSpace($n)) { return $r.ToLowerInvariant() }
    if ($n -match "^https?://github\.com/(.+)$") {
        $path = $Matches[1]
        $path = $path.TrimEnd("/")
        if ($path.EndsWith(".git")) { $path = $path.Substring(0, $path.Length - 4) }
        $parts = $path.Split("/") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($parts.Count -ge 2) {
            return ("github.com/{0}/{1}" -f $parts[0], $parts[1]).ToLowerInvariant()
        }
        return ("github.com/{0}" -f $path).ToLowerInvariant()
    }
    if ($n.EndsWith(".git")) { $n = $n.Substring(0, $n.Length - 4) }
    return $n.TrimEnd("/").ToLowerInvariant()
}
function Get-RepoIdentityKey([string]$repo) {
    return (Get-RepoIdentity $repo)
}
function Is-SameRepoIdentity([string]$a, [string]$b) {
    $ia = Get-RepoIdentity $a
    $ib = Get-RepoIdentity $b
    if ([string]::IsNullOrWhiteSpace($ia) -or [string]::IsNullOrWhiteSpace($ib)) { return $false }
    return ($ia -eq $ib)
}
function Is-SameRepository([string]$a, [string]$b) {
    return (Is-SameRepoIdentity $a $b)
}
function Test-LooksLikeRepoUrl([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    $v = $value.Trim().Trim("'`"")
    if ($v -match "^(git@github\.com:|https?://github\.com/|github\.com/)") { return $true }
    if ($v -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$") { return $true }
    return $false
}
function Test-InstalledVendorPath([string]$path, [string]$repo) {
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($repo)) { return $false }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $path ".git") -PathType Container)) { return $false }

    $origin = $null
    Push-Location $path
    try {
        $origin = Invoke-GitCapture @("remote", "get-url", "origin")
    }
    catch {
        return $false
    }
    finally {
        Pop-Location
    }

    if ([string]::IsNullOrWhiteSpace($origin)) { return $false }
    return (Is-SameRepoIdentity $origin $repo)
}
function Has-GitUpstream {
    $up = Invoke-GitCapture @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    return -not [string]::IsNullOrWhiteSpace($up)
}
function Test-GitUnrelatedHistoriesIssue([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) { return $false }
    return ($message -match "unrelated histories|拒绝合并无关的历史")
}
function Update-CurrentBranchFromUpstream([bool]$AllowNetworkFetch = $true) {
    $branch = Get-GitHeadBranch
    if (-not $branch -or -not (Has-GitUpstream)) {
        Log "跳过 git pull：当前为 detached HEAD 或无 upstream。"
        return
    }
    if ($AllowNetworkFetch) {
        try {
            Invoke-Git @("pull")
        }
        catch {
            if (Test-GitUnrelatedHistoriesIssue $_.Exception.Message) {
                Log ("检测到本地历史与上游无共同祖先，已强制对齐：{0}" -f $branch) "WARN"
                Invoke-Git @("reset", "--hard", "@{u}")
                return
            }
            throw
        }
        return
    }
    try {
        Invoke-Git @("merge", "--ff-only", "@{u}")
        Log ("已基于本地 refs 快进分支：{0}" -f $branch)
    }
    catch {
        if (Test-GitUnrelatedHistoriesIssue $_.Exception.Message) {
            Log ("检测到本地历史与上游无共同祖先，已强制对齐：{0}" -f $branch) "WARN"
            Invoke-Git @("reset", "--hard", "@{u}")
            return
        }
        Log ("本地快进失败，已强制对齐上游：{0}；原因：{1}" -f $branch, $_.Exception.Message) "WARN"
        Invoke-Git @("reset", "--hard", "@{u}")
    }
}
function Has-GitChanges {
    $out = Invoke-GitCapture @("status", "--porcelain")
    return -not [string]::IsNullOrWhiteSpace($out)
}
function Get-GitLockPathFromOutputLine([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
    $m = [regex]::Match($line, "Unable to create '([^']+index\.lock)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($line, '无法创建[“"]([^“"'']+index\.lock)[”"]')
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($line, "unable to unlink '([^']+index\.lock)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($line, '无法取消链接[“"]([^“"'']+index\.lock)[”"]')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}
function Test-GitIndexLockIssue($outputLines) {
    foreach ($line in @($outputLines)) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match "index\.lock|Could not write new index file|无法写入新的索引文件") {
            return $true
        }
    }
    return $false
}
function Convert-GitOutputLineToText($line) {
    if ($null -eq $line) { return $null }
    if ($line -is [System.Management.Automation.ErrorRecord]) {
        if ($line.Exception -and -not [string]::IsNullOrWhiteSpace($line.Exception.Message)) {
            return $line.Exception.Message.Trim()
        }
        $fallback = $line.ToString()
        if ([string]::IsNullOrWhiteSpace($fallback)) { return $null }
        if ($fallback -eq "System.Management.Automation.RemoteException") { return $null }
        return $fallback.Trim()
    }
    $text = ([string]$line).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text -eq "System.Management.Automation.RemoteException") { return $null }
    return $text
}
function Get-GitOutputSummary($outputLines) {
    $lines = @()
    foreach ($line in @($outputLines)) {
        $text = Convert-GitOutputLineToText $line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $lines += $text
    }
    if ($lines.Count -eq 0) { return $null }
    $permissionLines = @($lines | Where-Object { $_ -match "failed to remove|Permission denied|拒绝访问|Directory not empty" } | Select-Object -Unique)
    if ($permissionLines.Count -gt 0) {
        return ($permissionLines -join " | ")
    }
    return (($lines | Select-Object -Last 2) -join " | ")
}
function Get-GitCleanFailurePathsFromMessage([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) { return @() }
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($message -split "\|")) {
        $text = [string]$segment
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $trimmed = $text.Trim()
        $match = [regex]::Match($trimmed, "failed to remove(?: directory)?\s+'([^']+)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) {
            $match = [regex]::Match($trimmed, "failed to remove(?: directory)?\s+([^:]+?)(?::|$)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        if (-not $match.Success) { continue }
        $pathText = $match.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($pathText)) { continue }
        $paths.Add($pathText.Trim()) | Out-Null
    }
    return @($paths | Select-Object -Unique)
}
function Resolve-GitCleanFailurePath([string]$repoPath, [string]$rawPath) {
    if ([string]::IsNullOrWhiteSpace($repoPath) -or [string]::IsNullOrWhiteSpace($rawPath)) { return $null }
    $candidate = $rawPath.Trim().Trim("'`"").Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    $candidate = $candidate -replace "/", "\"
    try {
        $repoFull = [System.IO.Path]::GetFullPath($repoPath)
    }
    catch {
        return $null
    }

    $fullPath = $null
    try {
        if ([System.IO.Path]::IsPathRooted($candidate)) {
            $fullPath = [System.IO.Path]::GetFullPath($candidate)
        }
        else {
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoFull $candidate))
        }
    }
    catch {
        return $null
    }
    if (-not (Is-PathInsideOrEqual $fullPath $repoFull)) { return $null }
    return $fullPath
}
function Clear-ReadOnlyAttribute([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            $item.Attributes = ($item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly))
        }
    }
    catch {}
}
function Clear-ReadOnlyAttributesRecursively([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (-not (Test-Path -LiteralPath $path)) { return }
    Clear-ReadOnlyAttribute $path
    try {
        foreach ($child in @(Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue)) {
            Clear-ReadOnlyAttribute $child.FullName
        }
    }
    catch {}
}
function Repair-GitFailedRemovePaths([string]$repoPath, [string[]]$rawPaths, [string]$contextLabel) {
    if ([string]::IsNullOrWhiteSpace($repoPath)) { return $false }
    if ($null -eq $rawPaths -or $rawPaths.Count -eq 0) { return $false }
    if ([string]::IsNullOrWhiteSpace($contextLabel)) { $contextLabel = "git" }

    $repaired = $false
    foreach ($raw in @($rawPaths)) {
        $fullPath = Resolve-GitCleanFailurePath $repoPath $raw
        if ([string]::IsNullOrWhiteSpace($fullPath)) {
            Log ("{0} 修复跳过（路径超出仓库边界或无效）：{1}" -f $contextLabel, $raw) "WARN"
            continue
        }
        if (-not (Test-Path -LiteralPath $fullPath)) { continue }
        Clear-ReadOnlyAttributesRecursively $fullPath
        $removed = Invoke-RemoveItemWithRetry $fullPath -Recurse -IgnoreFailure -SilentIgnore
        if ($removed -or -not (Test-Path -LiteralPath $fullPath)) {
            Log ("{0} 权限修复完成：{1}" -f $contextLabel, $fullPath) "WARN"
            $repaired = $true
        }
        else {
            Log ("{0} 权限修复未完成：{1}" -f $contextLabel, $fullPath) "WARN"
        }
    }
    return $repaired
}
function Repair-GitCleanPermissionDenied([string]$repoPath, [string]$errorMessage) {
    if ([string]::IsNullOrWhiteSpace($errorMessage)) { return $false }
    if ($errorMessage -notmatch "git clean\s+-f") { return $false }
    if ($errorMessage -notmatch "failed to remove|Permission denied|拒绝访问|Directory not empty") { return $false }

    $rawPaths = @(Get-GitCleanFailurePathsFromMessage $errorMessage)
    return (Repair-GitFailedRemovePaths $repoPath $rawPaths "git clean")
}
function Test-GitProcessRunning {
    try {
        $gitProcesses = @(Get-Process -Name git,git-remote-http,git-remote-https,git-lfs,ssh,sh -ErrorAction SilentlyContinue)
        return ($gitProcesses.Count -gt 0)
    }
    catch {
        return $false
    }
}
function Remove-GitLockFile([string]$lockPath) {
    if ([string]::IsNullOrWhiteSpace($lockPath)) { return $false }
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return $false }
    try {
        [System.IO.File]::SetAttributes($lockPath, [System.IO.FileAttributes]::Normal)
    }
    catch {}
    Invoke-RemoveItemWithRetry $lockPath -MaxAttempts 6 -DelayMs 200 | Out-Null
    return (-not (Test-Path -LiteralPath $lockPath -PathType Leaf))
}
function Resolve-GitAdminDir([string]$repoPath) {
    if ([string]::IsNullOrWhiteSpace($repoPath)) { return $null }
    $gitEntry = Join-Path $repoPath ".git"
    if (Test-Path -LiteralPath $gitEntry -PathType Container) { return $gitEntry }
    if (-not (Test-Path -LiteralPath $gitEntry -PathType Leaf)) { return $null }

    $raw = Get-ContentUtf8 $gitEntry
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $firstLine = (($raw -split "\r?\n" | Select-Object -First 1) -as [string])
    if ([string]::IsNullOrWhiteSpace($firstLine)) { return $null }
    $match = [regex]::Match($firstLine, '^\s*gitdir:\s*(.+?)\s*$')
    if (-not $match.Success) { return $null }

    $gitDirPath = $match.Groups[1].Value.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($gitDirPath)) { return $null }
    try {
        if ([System.IO.Path]::IsPathRooted($gitDirPath)) {
            return [System.IO.Path]::GetFullPath($gitDirPath)
        }
        $gitBase = Split-Path -Parent $gitEntry
        return [System.IO.Path]::GetFullPath((Join-Path $gitBase $gitDirPath))
    }
    catch {
        return $null
    }
}
function Repair-StaleGitLockFromOutput($outputLines) {
    $lockPath = $null
    foreach ($line in @($outputLines)) {
        $lockPath = Get-GitLockPathFromOutputLine ([string]$line)
        if (-not [string]::IsNullOrWhiteSpace($lockPath)) { break }
    }
    if ([string]::IsNullOrWhiteSpace($lockPath)) { return $false }
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return $false }
    Log ("检测到陈旧 Git 锁文件，已自动移除：{0}" -f $lockPath) "WARN"
    if (Remove-GitLockFile $lockPath) { return $true }
    if (Test-GitProcessRunning) {
        throw ("检测到 Git 锁文件且自动移除失败（可能仍有 git 进程占用），请先等待或结束相关进程后重试：{0}" -f $lockPath)
    }
    throw ("检测到 Git 锁文件，但自动移除失败：{0}" -f $lockPath)
}
function Repair-StaleGitLockInRepo([string]$repoPath) {
    if ([string]::IsNullOrWhiteSpace($repoPath)) { return $false }
    $gitAdminDir = Resolve-GitAdminDir $repoPath
    if ([string]::IsNullOrWhiteSpace($gitAdminDir)) { return $false }
    $lockPath = Join-Path $gitAdminDir "index.lock"
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return $false }
    Log ("检测到仓库残留 Git 锁文件，已自动移除：{0}" -f $lockPath) "WARN"
    if (Remove-GitLockFile $lockPath) { return $true }
    if (Test-GitProcessRunning) {
        throw ("检测到 Git 锁文件且自动移除失败（可能仍有 git 进程占用），请先等待或结束相关进程后重试：{0}" -f $lockPath)
    }
    throw ("检测到 Git 锁文件，但自动移除失败：{0}" -f $lockPath)
}
function Repair-InProgressGitOperation([string]$repoPath) {
    if ([string]::IsNullOrWhiteSpace($repoPath)) { return $false }
    $gitAdminDir = Resolve-GitAdminDir $repoPath
    if ([string]::IsNullOrWhiteSpace($gitAdminDir)) { return $false }

    $operations = @(
        @{ marker = "rebase-merge"; args = @("rebase", "--abort"); label = "rebase" },
        @{ marker = "rebase-apply"; args = @("rebase", "--abort"); label = "rebase" },
        @{ marker = "MERGE_HEAD"; args = @("merge", "--abort"); label = "merge" },
        @{ marker = "CHERRY_PICK_HEAD"; args = @("cherry-pick", "--abort"); label = "cherry-pick" },
        @{ marker = "REVERT_HEAD"; args = @("revert", "--abort"); label = "revert" }
    )
    $repaired = $false
    foreach ($op in $operations) {
        $markerPath = Join-Path $gitAdminDir ([string]$op.marker)
        if (-not (Test-Path -LiteralPath $markerPath)) { continue }
        try {
            Invoke-Git @($op.args)
            Log ("检测到未完成 Git {0}，已自动中止。" -f ([string]$op.label)) "WARN"
            $repaired = $true
        }
        catch {
            throw ("检测到未完成 Git {0}，自动中止失败：{1}" -f ([string]$op.label), $_.Exception.Message)
        }
    }
    return $repaired
}
function Confirm-CleanRepo([string]$path) {
    if (-not (Test-Path $path)) { return $true }
    Push-Location $path
    try {
        if (-not (Has-GitChanges)) { return $true }
    }
    finally { Pop-Location }
    if (-not (Confirm-Action "检测到本地改动，继续将丢弃这些改动吗？" "CLEAN" -DefaultNo)) { return $false }
    return $true
}
function Git-HardResetClean([bool]$forceClean) {
    if (-not $forceClean) { return }
    $repoPath = (Get-Location).Path
    Repair-StaleGitLockInRepo $repoPath | Out-Null
    Repair-InProgressGitOperation $repoPath | Out-Null
    Invoke-Git @("reset", "--hard")
    Repair-StaleGitLockInRepo $repoPath | Out-Null
    $maxCleanAttempts = 12
    for ($attempt = 1; $attempt -le $maxCleanAttempts; $attempt++) {
        try {
            Invoke-Git @("clean", "-ffdx")
            return
        }
        catch {
            if ($attempt -ge $maxCleanAttempts) { throw }
            if (-not (Repair-GitCleanPermissionDenied $repoPath $_.Exception.Message)) { throw }
            Log ("git clean 失败，已执行权限修复并重试（{0}/{1}）" -f $attempt, $maxCleanAttempts) "WARN"
        }
    }
}
function Normalize-GitSparsePath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    $p = (To-GitPath $path).Trim().Trim("/")
    if ([string]::IsNullOrWhiteSpace($p) -or $p -eq ".") { return $null }
    return $p
}
function Get-NormalizedGitSparsePaths([string[]]$sparsePaths) {
    $set = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in @($sparsePaths)) {
        $p = Normalize-GitSparsePath $path
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $set.Add($p) | Out-Null
    }
    return @($set)
}
function Test-GitPathCoveredBySparsePath([string]$gitPath, [string[]]$sparsePaths) {
    if ([string]::IsNullOrWhiteSpace($gitPath)) { return $false }
    $p = (To-GitPath $gitPath).Trim().Trim("/")
    foreach ($sparsePath in @($sparsePaths)) {
        if ($p.Equals($sparsePath, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($p.StartsWith(($sparsePath + "/"), [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
function Test-GitSparseCandidateContainsKeptPath([string]$candidate, [string[]]$sparsePaths) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $false }
    foreach ($sparsePath in @($sparsePaths)) {
        if ($sparsePath.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($sparsePath.StartsWith(($candidate + "/"), [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
function Get-GitSparsePruneCandidates([string[]]$trackedPaths, [string[]]$sparsePaths) {
    $normalizedSparsePaths = @(Get-NormalizedGitSparsePaths $sparsePaths)
    if ($normalizedSparsePaths.Count -eq 0) { return @() }

    $candidates = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($trackedPath in @($trackedPaths)) {
        $gitPath = Normalize-GitSparsePath $trackedPath
        if ([string]::IsNullOrWhiteSpace($gitPath)) { continue }
        if (Test-GitPathCoveredBySparsePath $gitPath $normalizedSparsePaths) { continue }

        $parts = @($gitPath -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count -eq 0) { continue }
        $maxAncestorDepth = [Math]::Max(1, $parts.Count - 1)
        for ($depth = 1; $depth -le $maxAncestorDepth; $depth++) {
            $candidate = ($parts[0..($depth - 1)] -join "/")
            if (Test-GitSparseCandidateContainsKeptPath $candidate $normalizedSparsePaths) { continue }
            $candidates.Add($candidate) | Out-Null
            break
        }
    }
    return @($candidates | Sort-Object { $_.Length } -Descending)
}
function Remove-GitSparseCheckoutResiduals([string[]]$sparsePaths) {
    $normalizedSparsePaths = @(Get-NormalizedGitSparsePaths $sparsePaths)
    if ($normalizedSparsePaths.Count -eq 0) { return }

    $repoPath = (Get-Location).Path
    try {
        $repoFull = [System.IO.Path]::GetFullPath($repoPath)
    }
    catch {
        return
    }
    $trackedPaths = @(Invoke-GitCaptureLines @("ls-files"))
    $candidates = @(Get-GitSparsePruneCandidates $trackedPaths $normalizedSparsePaths)
    foreach ($candidate in $candidates) {
        $candidatePath = $candidate -replace "/", "\"
        $fullPath = $null
        try {
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoFull $candidatePath))
        }
        catch {
            continue
        }
        if (-not (Is-PathInsideOrEqual $fullPath $repoFull) -or $fullPath.Equals($repoFull, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not (Test-Path -LiteralPath $fullPath)) { continue }
        Clear-ReadOnlyAttributesRecursively $fullPath
        $removed = Invoke-RemoveItemWithRetry $fullPath -Recurse -IgnoreFailure -SilentIgnore
        if ($removed -or -not (Test-Path -LiteralPath $fullPath)) {
            Log ("sparse-checkout 预清理残留目录：{0}" -f $candidate) "INFO"
        }
        else {
            Log ("sparse-checkout 残留目录预清理失败（已交由 git 后续处理）：{0}" -f $candidate) "WARN"
        }
    }
}
function Repair-GitSparseCheckoutRemoveWarnings([string]$repoPath, $outputLines) {
    $warningLines = @()
    foreach ($line in @($outputLines)) {
        $text = Convert-GitOutputLineToText $line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match "warning:\s+failed to remove directory") { $warningLines += $text }
    }
    if ($warningLines.Count -eq 0) { return $false }

    $rawPaths = @(Get-GitCleanFailurePathsFromMessage ($warningLines -join " | "))
    if ($rawPaths.Count -eq 0) { return $false }
    return (Repair-GitFailedRemovePaths $repoPath $rawPaths "sparse-checkout")
}
function Invoke-GitSparseCheckoutCommand([string[]]$GitArgs) {
    if ($DryRun) {
        Log ("DRYRUN git {0}" -f ($GitArgs -join " "))
        return
    }
    $cmdText = ("git {0}" -f ($GitArgs -join " "))
    Log $cmdText
    $canTuneNativeErrPref = ($PSVersionTable.PSVersion.Major -ge 7)
    $prevNativeErrorPref = $null
    $prevErrorActionPreference = $ErrorActionPreference
    try {
        if ($canTuneNativeErrPref) {
            $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
        }
        $ErrorActionPreference = "Continue"
        $output = & git @GitArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prevErrorActionPreference
        if ($canTuneNativeErrPref) {
            $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
        }
    }

    $deferredRemoveWarnings = @()
    foreach ($line in @($output)) {
        $text = Convert-GitOutputLineToText $line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match "warning:\s+failed to remove directory") {
            $deferredRemoveWarnings += $text
            continue
        }
        Write-Host $text
    }

    if ($exitCode -ne 0) {
        foreach ($text in $deferredRemoveWarnings) { Write-Host $text }
        $summary = Get-GitOutputSummary $output
        if ([string]::IsNullOrWhiteSpace($summary)) {
            throw ("git 失败：{0}" -f $cmdText)
        }
        throw ("git 失败：{0}；详情：{1}" -f $cmdText, $summary)
    }

    if ($deferredRemoveWarnings.Count -gt 0) {
        $repoPath = (Get-Location).Path
        if (-not (Repair-GitSparseCheckoutRemoveWarnings $repoPath $deferredRemoveWarnings)) {
            foreach ($text in $deferredRemoveWarnings) { Write-Host $text }
        }
    }
}
function Set-GitSparseCheckout([string[]]$sparsePaths) {
    $normalizedSparsePaths = @(Get-NormalizedGitSparsePaths $sparsePaths)
    if ($normalizedSparsePaths.Count -eq 0) {
        try { Invoke-Git @("sparse-checkout", "disable") } catch {}
        return
    }
    Remove-GitSparseCheckoutResiduals $normalizedSparsePaths
    Invoke-GitSparseCheckoutCommand @("sparse-checkout", "init", "--cone")
    Remove-GitSparseCheckoutResiduals $normalizedSparsePaths
    Invoke-GitSparseCheckoutCommand (@("sparse-checkout", "set") + $normalizedSparsePaths)
}
function Repair-StaleGitLockAfterFailure([string]$repoPath, $outputLines) {
    if (-not (Test-GitIndexLockIssue $outputLines)) { return $false }
    return (Repair-StaleGitLockInRepo $repoPath)
}
function Ensure-Repo([string]$path, [string]$repo, [string]$ref, [string]$sparsePath, [bool]$forceClean = $true, [bool]$confirmClean = $false, [bool]$doFetch = $true) {
    if ($DryRun) {
        Log ("DRYRUN Ensure-Repo {0} <= {1} ({2})" -f $path, $repo, $ref)
        return
    }
    if (Test-LocalZipRepoInput $repo) {
        Need (-not $sparsePath -or $sparsePath -eq ".") "zip 导入不支持 --sparse，请去掉 --sparse 后重试。"
        Ensure-RepoFromZip $path $repo $forceClean
        return
    }
    if (-not (Test-Path $path)) {
        if ($sparsePath -and $sparsePath -ne ".") {
            Invoke-Git @("clone", "--filter=blob:none", "--no-checkout", $repo, $path)
            Push-Location $path
            try {
                Set-GitSparseCheckout @($sparsePath)
                Invoke-Git @("checkout", $ref)
            }
            finally { Pop-Location }
        }
        else {
            Invoke-Git @("clone", $repo, $path)
            Push-Location $path
            try { Invoke-Git @("checkout", $ref) } finally { Pop-Location }
        }
    }
    else {
        $gitDir = Join-Path $path ".git"
        if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
            Need $forceClean ("缓存目录已存在但不是 git 仓库且 update_force=false：{0}" -f $path)
            Log ("缓存目录不是 git 仓库，已重建：{0}" -f $path) "WARN"
            Invoke-RemoveItemWithRetry $path -Recurse
            Ensure-Repo $path $repo $ref $sparsePath $forceClean $confirmClean $doFetch
            return
        }
        $existingOrigin = $null
        Push-Location $path
        try {
            $existingOrigin = Invoke-GitCapture @("remote", "get-url", "origin")
        }
        finally { Pop-Location }
        if (-not (Is-SameRepoIdentity $existingOrigin $repo)) {
            Need $forceClean ("缓存目录已存在但来源仓库不匹配且 update_force=false：{0}" -f $path)
            Log ("检测到缓存目录来源不匹配，已重建：{0} (old={1}, new={2})" -f $path, $existingOrigin, $repo) "WARN"
            Invoke-RemoveItemWithRetry $path -Recurse
            Ensure-Repo $path $repo $ref $sparsePath $forceClean $confirmClean $doFetch
            return
        }
        Push-Location $path
        try {
            if ($forceClean -and $confirmClean) {
                if (-not (Confirm-CleanRepo $path)) { throw "已取消：存在本地改动，未执行清理。" }
            }
            Git-HardResetClean $forceClean
            Set-GitSparseCheckout @($sparsePath)
            if ($doFetch) {
                Invoke-Git @("fetch", "--all", "--tags")
            }
            Invoke-Git @("checkout", $ref)
            # We already fetched explicitly when needed; prefer local fast-forward first
            # to avoid duplicate network round-trips per repo.
            Update-CurrentBranchFromUpstream $false
        }
        finally { Pop-Location }
    }
}
