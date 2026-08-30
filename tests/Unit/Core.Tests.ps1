BeforeAll {
    # Dot-source the main script to load functions
    . $PSScriptRoot\..\..\skills.ps1

}
Describe "Core Functions" {
    Context "Normalize-Name" {
        It "Normalizes typical names" {
            Normalize-Name " My Skill " | Should -Be "my-skill"
            Normalize-Name "foo_bar" | Should -Be "foo-bar"
            Normalize-Name "foo/bar" | Should -Be "foo-bar"
        }

        It "Removes invalid characters" {
            Normalize-Name "foo@bar!" | Should -Be "foo-bar"
        }

        It "Collapses multiple dashes" {
            Normalize-Name "foo--bar" | Should -Be "foo-bar"
        }
    }

    Context "Junction handling" {
        It "Replaces a broken target junction" {
            if ($env:OS -ne "Windows_NT") { return }

            $link = Join-Path $TestDrive "skills-link"
            $oldTarget = Join-Path $TestDrive "old-agent"
            $newTarget = Join-Path $TestDrive "new-agent"

            New-Item -ItemType Directory -Path $oldTarget -Force | Out-Null
            & cmd /c mklink /J "$link" "$oldTarget" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "test mklink failed" }

            Remove-Item -LiteralPath $oldTarget -Recurse -Force

            (Test-PathEntry $link) | Should -Be $true
            (Is-ReparsePoint $link) | Should -Be $true

            New-Junction $link $newTarget

            $item = Get-Item -LiteralPath $link -Force
            $item.LinkType | Should -Be "Junction"
            $item.Target | Should -Be $newTarget
        }
    }

    Context "Literal path filesystem helpers" {
        It "Moves paths containing wildcard characters literally" {
            $src = Join-Path $TestDrive "skill[one]"
            $dst = Join-Path $TestDrive "skill[one]-moved"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $src "SKILL.md") -Value "x"

            Invoke-MoveItem $src $dst

            (Test-Path -LiteralPath $src) | Should -Be $false
            (Test-Path -LiteralPath (Join-Path $dst "SKILL.md")) | Should -Be $true
        }

        It "Removes paths containing wildcard characters literally" {
            $dir = Join-Path $TestDrive "remove[me]"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir "SKILL.md") -Value "x"

            Invoke-RemoveItemWithRetry $dir -Recurse | Should -Be $true

            (Test-Path -LiteralPath $dir) | Should -Be $false
        }

        It "Removes stale git index locks from worktree gitdir files" {
            $repo = Join-Path $TestDrive "repo-worktree"
            $gitAdmin = Join-Path $TestDrive "git-admin"
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            New-Item -ItemType Directory -Path $gitAdmin -Force | Out-Null
            Set-ContentUtf8 (Join-Path $repo ".git") ("gitdir: {0}" -f $gitAdmin)
            Set-ContentUtf8 (Join-Path $gitAdmin "index.lock") "stale"

            Mock Test-GitProcessRunning { $false }
            $removed = Repair-StaleGitLockInRepo $repo

            $removed | Should -Be $true
            (Test-Path -LiteralPath (Join-Path $gitAdmin "index.lock")) | Should -Be $false
        }
    }

    Context "Split-Args" {
        It "Splits simple arguments" {
            $tokens = Split-Args "foo bar baz"
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "foo"
        }

        It "External quotes are consumed" {
            $tokens = Split-Args 'foo "bar baz"'
            $tokens.Count | Should -Be 2
            $tokens[1] | Should -Be "bar baz"
        }

        It "Nested quotes are preserved" {
            # In PowerShell: Split-Args 'foo "bar \"baz\""' -> foo, bar "baz"
            $tokens = Split-Args 'foo "bar \"baz\""'
            $tokens.Count | Should -Be 2
            $tokens[1] | Should -Be 'bar "baz"'
        }

        It "Throws on unclosed double quote" {
            $thrown = $false
            try {
                Split-Args 'foo "bar baz' | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Throws on unclosed single quote" {
            $thrown = $false
            try {
                Split-Args "foo 'bar baz" | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }
    }

    Context "Get-InstallErrorSuggestedSkillPath" {
        It "Prefers candidate path from error message" {
            $repoRoot = Join-Path $TestDrive "skills-manager"
            $msg = @"
技能路径预检失败：--skill remotion-best-practices
未找到技能入口文件：$([System.IO.Path]::Combine($repoRoot, 'imports\_probe_xxx\remotion-best-practices'))
可选路径（共 2）：
- .
- skills\remotion
"@
            Get-InstallErrorSuggestedSkillPath $msg @("remotion-best-practices") | Should -Be "skills/remotion"
        }

        It "Falls back to input when candidate is unavailable" {
            $msg = "未找到技能入口文件：X"
            Get-InstallErrorSuggestedSkillPath $msg @("remotion-best-practices") | Should -Be "skills/remotion-best-practices"
        }
    }

    Context "Get-SkillCandidates" {
        It "Returns array with correct count when exactly one candidate exists" {
            $base = Join-Path $TestDrive "repo"
            $skillDir = Join-Path $base "skills\\remotion"
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $skillDir "SKILL.md") -Force | Out-Null

            Clear-SkillsCache
            $items = Get-SkillCandidates $base

            ($items.Count -gt 0) | Should -Be $true
            @($items).Count | Should -Be 1
            @($items)[0].rel | Should -Be "skills\remotion"
            @($items)[0].leaf | Should -Be "remotion"
        }
    }

    Context "Resolve-SkillPath" {
        It "Auto-resolves compact name variants like uni-app -> skills\uniapp" {
            $base = Join-Path $TestDrive "repo-compact"
            $skillDir = Join-Path $base "skills\\uniapp"
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $skillDir "AGENTS.md") -Force | Out-Null

            Clear-SkillsCache
            Resolve-SkillPath $base "uni-app" | Should -Be "skills\uniapp"
        }
    }

    Context "Parse-DefaultBranchFromSymref" {
        It "Parses main branch from ls-remote symref output" {
            Parse-DefaultBranchFromSymref "ref: refs/heads/main`tHEAD" | Should -Be "main"
        }

        It "Parses master branch from ls-remote symref output" {
            Parse-DefaultBranchFromSymref "ref: refs/heads/master`tHEAD" | Should -Be "master"
        }

        It "Returns null for non-symref output" {
            Parse-DefaultBranchFromSymref "4292f000a15ecf07a6d0900ab495b80864de2a15`tHEAD" | Should -Be $null
        }
    }

    Context "Update-CurrentBranchFromUpstream" {
        It "redacts credentials and sensitive query values from Git command text" {
            $masked = Mask-SensitiveGitText 'https://user:pass@example.invalid/repo.git?token=secret-value Authorization: Bearer github_pat_abc123 token spaced-secret'
            $masked | Should -Not -Match 'user|pass|secret-value|github_pat_abc123|spaced-secret'
            $masked | Should -Match '<redacted>'
        }

        It "redacts sparse-checkout dry-run arguments before logging" {
            $oldDryRun = $DryRun
            try {
                $DryRun = $true
                $script:sparseLog = $null
                Mock Log { param($msg) $script:sparseLog = $msg }

                Invoke-GitSparseCheckoutCommand @('sparse-checkout', 'set', 'https://user:pass@example.invalid/repo?token=sparse-secret')

                $script:sparseLog | Should -Match '<redacted>'
                $script:sparseLog | Should -Not -Match 'user:pass|sparse-secret'
            }
            finally {
                $DryRun = $oldDryRun
            }
        }

        It "Uses git pull --ff-only when network fetch is allowed" {
            Mock Get-GitHeadBranch { "main" }
            Mock Has-GitUpstream { $true }
            Mock Invoke-Git {}

            Update-CurrentBranchFromUpstream $true

            Should -Invoke Invoke-Git -Times 1 -Exactly -Scope It -ParameterFilter {
                (@($GitArgs) -join ' ') -eq "pull --ff-only"
            }
        }

        It "Uses local ff-only merge when network fetch is disabled" {
            Mock Get-GitHeadBranch { "main" }
            Mock Has-GitUpstream { $true }
            Mock Invoke-Git {}

            Update-CurrentBranchFromUpstream $false

            Should -Invoke Invoke-Git -Times 1 -Exactly -Scope It -ParameterFilter {
                @($GitArgs)[0] -eq "merge" -and @($GitArgs)[1] -eq "--ff-only"
            }
        }

        It "fails closed without reset when ff-only merge fails for an unknown reason" {
            Mock Get-GitHeadBranch { "main" }
            Mock Has-GitUpstream { $true }
            $script:syncCalls = New-Object System.Collections.Generic.List[string]
            Mock Invoke-Git {
                param($GitArgs)
                $script:syncCalls.Add([string]@($GitArgs)[0]) | Out-Null
                if (@($GitArgs)[0] -eq "merge") { throw "ff-only failed" }
            }

            { Update-CurrentBranchFromUpstream $false } | Should -Throw

            ($script:syncCalls -join ",") | Should -Be "merge"
        }

        It "fails closed without reset when histories are unrelated" {
            Mock Get-GitHeadBranch { "main" }
            Mock Has-GitUpstream { $true }
            $script:syncCalls = New-Object System.Collections.Generic.List[string]
            Mock Invoke-Git {
                param($GitArgs)
                $script:syncCalls.Add([string]@($GitArgs)[0]) | Out-Null
                if (@($GitArgs)[0] -eq "merge") {
                    throw "git 失败：git merge --ff-only @{u}；详情：fatal: refusing to merge unrelated histories"
                }
            }

            { Update-CurrentBranchFromUpstream $false } | Should -Throw

            ($script:syncCalls -join ",") | Should -Be "merge"
        }

        It "fails closed without reset when network pull reports unrelated histories" {
            Mock Get-GitHeadBranch { "main" }
            Mock Has-GitUpstream { $true }
            $script:syncCalls = New-Object System.Collections.Generic.List[string]
            Mock Invoke-Git {
                param($GitArgs)
                $script:syncCalls.Add((@($GitArgs) -join ' ')) | Out-Null
                throw "fatal: refusing to merge unrelated histories"
            }

            { Update-CurrentBranchFromUpstream $true } | Should -Throw

            $script:syncCalls.Count | Should -Be 1
            $script:syncCalls[0] | Should -Be 'pull --ff-only'
        }
    }

    Context "Zip Repo Input" {
        It "Recognizes existing local zip as repo input" {
            $zip = Join-Path $TestDrive "sample.zip"
            Set-Content -Path $zip -Value "x"
            Test-LocalZipRepoInput $zip | Should -Be $true
        }

        It "Extracts local zip via Ensure-Repo and keeps skill directory discoverable" {
            $oldImportDir = $ImportDir
            try {
                $ImportDir = Join-Path $TestDrive "imports-zip"
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null

                $srcRoot = Join-Path $TestDrive "myskills"
                $skillDir = Join-Path $srcRoot "downloaded-skills\\d3-viz"
                New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
                Set-Content -Path (Join-Path $skillDir "SKILL.md") -Value "# test"

                $zip = Join-Path $TestDrive "myskills.zip"
                Compress-Archive -Path (Join-Path $srcRoot "*") -DestinationPath $zip -Force

                $dest = Join-Path $TestDrive "cache"
                Ensure-Repo $dest $zip "main" $null $true $false

                (Test-IsSkillDir (Join-Path $dest "d3-viz")) | Should -Be $true
            }
            finally {
                $ImportDir = $oldImportDir
            }
        }

        It "Rejects sparse checkout when repo input is local zip" {
            $oldImportDir = $ImportDir
            try {
                $ImportDir = Join-Path $TestDrive "imports-zip-2"
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null

                $srcRoot = Join-Path $TestDrive "myskills2"
                $skillDir = Join-Path $srcRoot "demo"
                New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
                Set-Content -Path (Join-Path $skillDir "SKILL.md") -Value "# test"

                $zip = Join-Path $TestDrive "myskills2.zip"
                Compress-Archive -Path (Join-Path $srcRoot "*") -DestinationPath $zip -Force

                $thrown = $false
                try {
                    Ensure-Repo (Join-Path $TestDrive "cache2") $zip "main" "demo" $true $false
                }
                catch {
                    $thrown = $true
                }
                $thrown | Should -Be $true
            }
            finally {
                $ImportDir = $oldImportDir
            }
        }
    }

    Context "GitHub tree snapshot identity" {
        It "binds tree and raw downloads to immutable SHAs and verifies each blob" {
            $oldImportDir = $ImportDir
            try {
                $ImportDir = Join-Path $TestDrive "github-snapshot-imports"
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null
                $contentPath = Join-Path $TestDrive "github-blob-content"
                [IO.File]::WriteAllText($contentPath, 'hello', [Text.UTF8Encoding]::new($false))
                $blobSha = Get-GitBlobSha1ForFile $contentPath
                $commitSha = 'a' * 40
                $treeSha = 'b' * 40
                Mock Invoke-RestMethod {
                    param($Uri)
                    if ([string]$Uri -like '*/commits/*') { return [pscustomobject]@{ sha=$commitSha; commit=[pscustomobject]@{ tree=[pscustomobject]@{ sha=$treeSha } } } }
                    return [pscustomobject]@{ truncated=$false; tree=@([pscustomobject]@{ type='blob'; path='skills/demo/SKILL.md'; sha=$blobSha; size=5 }) }
                }
                Mock Invoke-WebRequest {
                    param($Uri,$Headers,$OutFile)
                    [IO.File]::WriteAllText($OutFile, 'hello', [Text.UTF8Encoding]::new($false))
                }
                $target = Join-Path $TestDrive "github-snapshot-target"

                Ensure-RepoFromGitHubTreeSnapshot $target 'https://github.com/owner/repo.git' 'main' 'skills/demo' $true

                Get-Content -LiteralPath (Join-Path $target 'skills/demo/SKILL.md') | Should -Be hello
                Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { [string]$Uri -like "*/git/trees/$treeSha*" }
                Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { [string]$Uri -like "*/$commitSha/skills/demo/SKILL.md" }
            }
            finally { $ImportDir = $oldImportDir }
        }
    }

    Context "Parse-AddArgs" {
        It "Rejects single token without slashes or git/http protocol as invalid GitHub format" {
            $thrown = $false
            try {
                Parse-AddArgs @("claude-mem", "--skill", "foo") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "并非有效的 GitHub 仓库格式"
            }
            $thrown | Should -Be $true
        }

        It "Leaves ref empty when --ref is not provided" {
            $parsed = Parse-AddArgs @("https://github.com/othmanadi/planning-with-files", "--skill", "planning-with-files")
            [string]::IsNullOrWhiteSpace($parsed.ref) | Should -Be $true
        }

        It "Uses provided ref when --ref is present" {
            $parsed = Parse-AddArgs @("https://github.com/othmanadi/planning-with-files", "--skill", "planning-with-files", "--ref", "master")
            $parsed.ref | Should -Be "master"
        }

        It "Rejects repo URLs passed as --ref values" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--skill", "foo", "--ref", "https://github.com/google-labs-code/stitch-skills.git") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "--ref"
                $_.Exception.Message | Should -Match "仓库地址"
            }
            $thrown | Should -Be $true
        }

        It "Rejects empty --skill value" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--skill=") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Treats explicit dot as root skill path" {
            $parsed = Parse-AddArgs @("owner/repo", "--skill", ".")
            $parsed.skills.Count | Should -Be 1
            $parsed.skills[0] | Should -Be "."
        }

        It "Converts skills.sh repo@skill syntax before repo validation" {
            $parsed = Parse-AddArgs @("geekjourneyx/md2wechat-lite@md2wechat-lite")
            $parsed.repo | Should -Be "geekjourneyx/md2wechat-lite"
            $parsed.skillSpecified | Should -Be $true
            $parsed.skills.Count | Should -Be 1
            $parsed.skills[0] | Should -Be "md2wechat-lite"
        }

        It "Rejects repo@skill when --skill is also provided" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo@foo", "--skill", "bar") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "不能同时传 --skill"
            }
            $thrown | Should -Be $true
        }

        It "Rejects missing option value when next token is another flag" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--ref", "--skill", "foo") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Rejects traversal skill path" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--skill", "..\\secret") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Rejects absolute skill path" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--skill", "C:\\temp\\skill") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }
    }

    Context "Get-AddTokensFromNpx" {
        It "Parses lowercase npx skills add command" {
            $tokens = Get-AddTokensFromNpx @("skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Parses case-insensitive skills add command" {
            $tokens = Get-AddTokensFromNpx @("Skills", "Add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Accepts optional npx prefix in token list" {
            $tokens = Get-AddTokensFromNpx @("npx", "skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Throws clear error when skills add has no args" {
            $thrown = $false
            try {
                Get-AddTokensFromNpx @("skills", "add") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Parses add-skill command case-insensitively" {
            $tokens = Get-AddTokensFromNpx @("ADD-SKILL", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Parses single-string command input" {
            $tokens = Get-AddTokensFromNpx @("skills add owner/repo --skill foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Preserves skills.sh repo@skill token for Parse-AddArgs" {
            $tokens = Get-AddTokensFromNpx @("skills add geekjourneyx/md2wechat-lite@md2wechat-lite")
            $tokens.Count | Should -Be 1
            $tokens[0] | Should -Be "geekjourneyx/md2wechat-lite@md2wechat-lite"
        }
    }

    Context "Get-AddTokensFromCommandLineTokens" {
        It "Parses direct add command" {
            $tokens = Get-AddTokensFromCommandLineTokens @("add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Parses direct skills add command" {
            $tokens = Get-AddTokensFromCommandLineTokens @("skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Parses npx command" {
            $tokens = Get-AddTokensFromCommandLineTokens @("npx", "skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Parses command with skills.ps1 prefix" {
            $tokens = Get-AddTokensFromCommandLineTokens @(".\\skills.ps1", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Parses command with skills.cmd prefix and npx.cmd" {
            $tokens = Get-AddTokensFromCommandLineTokens @("skills.cmd", "npx.cmd", "skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
        }

        It "Throws when only wrapper script is provided" {
            $thrown = $false
            try {
                Get-AddTokensFromCommandLineTokens @(".\\skills.ps1") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Throws when skills command misses subcommand" {
            $thrown = $false
            try {
                Get-AddTokensFromCommandLineTokens @("skills") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Throws when skills subcommand is unsupported" {
            $thrown = $false
            try {
                Get-AddTokensFromCommandLineTokens @("skills", "list") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }
    }

    Context "Resolve-AddTokensFromAnyFormat and Extract-SkillFromGitHubTreeUrl" {

        # ── Extract-SkillFromGitHubTreeUrl ──────────────────────────────────
        It "Extracts skill path from GitHub tree URL" {
            $skill = Extract-SkillFromGitHubTreeUrl "https://github.com/owner/repo/tree/main/skills/create-plan"
            $skill | Should -Be "skills/create-plan"
        }

        It "Trims trailing punctuations like Chinese/English period appropriately" {
            $skill1 = Extract-SkillFromGitHubTreeUrl "https://github.com/openai/skills/tree/main/skills/.experimental/create-plan。"
            $skill1 | Should -Be "skills/.experimental/create-plan"

            $skill2 = Extract-SkillFromGitHubTreeUrl "https://github.com/openai/skills/tree/main/skills/.experimental/create-plan,"
            $skill2 | Should -Be "skills/.experimental/create-plan"
        }

        It "Extracts nested skill path from GitHub tree URL" {
            $skill = Extract-SkillFromGitHubTreeUrl "https://github.com/openai/skills/tree/main/skills/.experimental/create-plan"
            $skill | Should -Be "skills/.experimental/create-plan"
        }

        It "Returns null for non-tree URL" {
            $skill = Extract-SkillFromGitHubTreeUrl "https://github.com/owner/repo"
            $skill | Should -Be $null
        }

        It "Returns null for owner/repo shorthand" {
            $skill = Extract-SkillFromGitHubTreeUrl "owner/repo"
            $skill | Should -Be $null
        }

        # ── /plugin format ──────────────────────────────────────────────────
        It "Resolves /plugin marketplace add owner/repo" {
            $tokens = Resolve-AddTokensFromAnyFormat @("/plugin", "marketplace", "add", "thedotmack/claude-mem")
            $tokens[0] | Should -Be "thedotmack/claude-mem"
        }

        It "Resolves /plugin install owner/repo" {
            $tokens = Resolve-AddTokensFromAnyFormat @("/plugin", "install", "thedotmack/claude-mem")
            $tokens[0] | Should -Be "thedotmack/claude-mem"
        }

        It "Passes through --skill flag from /plugin add" {
            $tokens = Resolve-AddTokensFromAnyFormat @("/plugin", "marketplace", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
            $tokens[1] | Should -Be "--skill"
            $tokens[2] | Should -Be "foo"
        }

        # ── $skill-installer format ─────────────────────────────────────────
        It 'Resolves $skill-installer owner/repo' {
            $tokens = Resolve-AddTokensFromAnyFormat @('$skill-installer', "owner/repo")
            $tokens[0] | Should -Be "owner/repo"
        }

        It 'Resolves $skill-installer install owner/repo' {
            $tokens = Resolve-AddTokensFromAnyFormat @('$skill-installer', "install", "owner/repo")
            $tokens[0] | Should -Be "owner/repo"
        }

        It 'Resolves $skill-installer install GitHub tree URL with skill path' {
            $url = "https://github.com/openai/skills/tree/main/skills/.experimental/create-plan"
            $tokens = Resolve-AddTokensFromAnyFormat @('$skill-installer', "install", $url)
            $tokens[0] | Should -Be "https://github.com/openai/skills.git"
            $tokens[1] | Should -Be "--skill"
            $tokens[2] | Should -Be "skills/.experimental/create-plan"
            $tokens[3] | Should -Be "--sparse"
        }

        # ── Bare GitHub Tree URL ────────────────────────────────────────────
        It "Resolves bare GitHub tree URL to repo + --skill" {
            $url = "https://github.com/openai/skills/tree/main/skills/create-plan"
            $tokens = Resolve-AddTokensFromAnyFormat @($url)
            $tokens[0] | Should -Be "https://github.com/openai/skills.git"
            $tokens[1] | Should -Be "--skill"
            $tokens[2] | Should -Be "skills/create-plan"
            $tokens[3] | Should -Be "--sparse"
        }

        It "Returns null for plain owner/repo (fallthrough to existing logic)" {
            $result = Resolve-AddTokensFromAnyFormat @("owner/repo", "--skill", "foo")
            $result | Should -Be $null
        }

        # ── npm: scoped package auto-conversion ─────────────────────────────
        It "Converts npm install -g scoped package to owner/repo" {
            $tokens = Resolve-AddTokensFromAnyFormat @("npm", "install", "-g", "@steipete/summarize")
            $tokens.Count | Should -Be 1
            $tokens[0] | Should -Be "steipete/summarize"
        }

        It "Converts npm i -g scoped package to owner/repo" {
            $tokens = Resolve-AddTokensFromAnyFormat @("npm", "i", "-g", "@tobilu/qmd")
            $tokens.Count | Should -Be 1
            $tokens[0] | Should -Be "tobilu/qmd"
        }

        It "Still rejects npm install -g for non-scoped package" {
            $thrown = $false
            try {
                Resolve-AddTokensFromAnyFormat @("npm", "install", "-g", "left-pad") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "scoped"
            }
            $thrown | Should -Be $true
        }

        # ── curl / Invoke-RestMethod: friendly error ─────────────────────────
        It "Throws friendly error for curl | bash pattern" {
            $thrown = $false
            try {
                Resolve-AddTokensFromAnyFormat @("curl", "-LsSf", "https://code.kimi.com/install.sh") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "curl"
            }
            $thrown | Should -Be $true
        }

        It "Throws friendly error for Invoke-RestMethod pattern" {
            $thrown = $false
            try {
                Resolve-AddTokensFromAnyFormat @("Invoke-RestMethod", "https://code.kimi.com/install.ps1") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "Invoke-RestMethod"
            }
            $thrown | Should -Be $true
        }

        It "Converts curl install script when install_script_mappings matches" {
            $script:InstallScriptMappingsOverride = @(
                [pscustomobject]@{
                    match = "code.kimi.com/install.sh"
                    repo = "acme/kimi-skill"
                    skill = "skills/kimi"
                }
            )
            try {
                $tokens = Resolve-AddTokensFromAnyFormat @("curl", "-LsSf", "https://code.kimi.com/install.sh", "|", "bash")
                $tokens.Count | Should -Be 3
                $tokens[0] | Should -Be "https://github.com/acme/kimi-skill.git"
                $tokens[1] | Should -Be "--skill"
                $tokens[2] | Should -Be "skills/kimi"
            }
            finally {
                $script:InstallScriptMappingsOverride = $null
            }
        }

        It "Converts Invoke-RestMethod install script when regex mapping matches" {
            $script:InstallScriptMappingsOverride = @(
                [pscustomobject]@{
                    match = "code\.kimi\.com/install\.(sh|ps1)"
                    regex = $true
                    repo = "acme/kimi-skill"
                }
            )
            try {
                $tokens = Resolve-AddTokensFromAnyFormat @("Invoke-RestMethod", "https://code.kimi.com/install.ps1", "|", "Invoke-Expression")
                $tokens.Count | Should -Be 1
                $tokens[0] | Should -Be "https://github.com/acme/kimi-skill.git"
            }
            finally {
                $script:InstallScriptMappingsOverride = $null
            }
        }

        It 'rejects $skill-installer bare names without inventing a deprecated source' {
            { Resolve-AddTokensFromAnyFormat @('$skill-installer', "gh-address-comments") } | Should -Throw
        }
    }

    Context "Looks-LikeRepoInput" {
        It "Returns false for non-repo short name" {
            (Looks-LikeRepoInput "agent-skills") | Should -Be $false
        }

        It "Returns true for owner/repo" {
            (Looks-LikeRepoInput "vercel-labs/agent-skills") | Should -Be $true
        }
    }

    Context "Resolve-UniqueVendorName" {
        It "Throws when vendor name exists with same repo" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "skills"; repo = "https://github.com/openai/skills.git"; ref = "main" }
                )
            }
            $thrown = $false
            try {
                Resolve-UniqueVendorName $cfg "skills" "openai/skills" | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "同一技能库"
                $_.Exception.Message | Should -Match "identityKey"
            }
            $thrown | Should -Be $true
        }

        It "Auto suffixes when vendor name exists with different repo" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "skills"; repo = "https://github.com/openai/skills.git"; ref = "main" }
                )
            }
            $name = Resolve-UniqueVendorName $cfg "skills" "vercel-labs/agent-skills"
            $name | Should -Be "skills-2"
        }

        It "Allows reusing existing vendor name for same repo when explicitly requested" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "superpowers"; repo = "https://github.com/obra/superpowers.git"; ref = "main" }
                )
            }
            $name = Resolve-UniqueVendorName $cfg "superpowers" "https://github.com/obra/superpowers.git" $true
            $name | Should -Be "superpowers"
        }
    }

    Context "Repository identity matching" {
        It "Treats owner/repo and https URL as same repository" {
            (Is-SameRepository "openai/skills" "https://github.com/openai/skills.git") | Should -Be $true
        }

        It "Treats git@ and https URL as same repository" {
            (Is-SameRepository "git@github.com:openai/skills.git" "https://github.com/openai/skills") | Should -Be $true
        }

        It "Treats tree URL and repo URL as same repository" {
            (Is-SameRepository "https://github.com/openai/skills/tree/main/skills/.curated/pdf" "openai/skills") | Should -Be $true
        }

        It "Recognizes different owner as different repository" {
            (Is-SameRepository "openai/skills" "vercel-labs/skills") | Should -Be $false
        }

        It "Builds stable identity key for ssh URL" {
            (Get-RepoIdentityKey "ssh://git@github.com/openai/skills.git") | Should -Be "github.com/openai/skills"
        }
    }

    Context "Installed state detection" {
        It "Treats a vendor directory as installed only when the remote origin matches" {
            $vendorPath = Join-Path $TestDrive "vendor-same"
            New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null
            git -C $vendorPath init | Out-Null
            git -C $vendorPath remote add origin https://github.com/openai/skills.git

            (Test-InstalledVendorPath $vendorPath "openai/skills") | Should -Be $true
        }

        It "Does not treat a vendor directory as installed when the remote origin differs" {
            $vendorPath = Join-Path $TestDrive "vendor-diff"
            New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null
            git -C $vendorPath init | Out-Null
            git -C $vendorPath remote add origin https://github.com/vercel-labs/skills.git

            (Test-InstalledVendorPath $vendorPath "openai/skills") | Should -Be $false
        }

        It "Recognizes equivalent MCP server configs even when names differ" {
            $a = [pscustomobject]@{
                name      = "context7"
                transport = "stdio"
                command   = "npx"
                args      = @("-y", "@upstash/context7-mcp")
                env       = @{ }
            }
            $b = [pscustomobject]@{
                name      = "context7-alt"
                transport = "stdio"
                command   = "npx"
                args      = @("-y", "@upstash/context7-mcp")
                env       = @{ }
            }

            (Test-McpServerEquivalent $a $b) | Should -Be $true
            (Find-EquivalentMcpServer @($a) $b).name | Should -Be "context7"
        }

        It "Does not treat different MCP endpoints as equivalent" {
            $a = [pscustomobject]@{
                name      = "context7"
                transport = "stdio"
                command   = "npx"
                args      = @("-y", "@upstash/context7-mcp")
            }
            $b = [pscustomobject]@{
                name      = "fetch"
                transport = "stdio"
                command   = "npx"
                args      = @("-y", "@modelcontextprotocol/server-fetch")
            }

            (Test-McpServerEquivalent $a $b) | Should -Be $false
            (Find-EquivalentMcpServer @($a) $b) | Should -Be $null
        }
    }

    Context "Merge-FilterAndArgs" {
        It "Prepends Filter when Filter is set" {
            $tokens = Merge-FilterAndArgs "owner/repo" @("--skill", "foo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "owner/repo"
            $tokens[1] | Should -Be "--skill"
            $tokens[2] | Should -Be "foo"
        }

        It "Returns args unchanged when Filter is empty" {
            $tokens = Merge-FilterAndArgs "" @("skills", "add", "owner/repo")
            $tokens.Count | Should -Be 3
            $tokens[0] | Should -Be "skills"
            $tokens[1] | Should -Be "add"
            $tokens[2] | Should -Be "owner/repo"
        }
    }

    Context "Parse-McpInstallArgs" {
        It "Parses stdio MCP server arguments" {
            $parsed = Parse-McpInstallArgs @("context7", "--cmd", "npx", "--", "-y", "@upstash/context7-mcp")
            $parsed.name | Should -Be "context7"
            $parsed.transport | Should -Be "stdio"
            $parsed.command | Should -Be "npx"
            $parsed.args.Count | Should -Be 2
            $parsed.args[0] | Should -Be "-y"
        }

        It "Normalizes accidental --arg wrappers for stdio args" {
            $parsed = Parse-McpInstallArgs @("filesystem", "--cmd", "npx", "--arg", "-y", "--arg", "@modelcontextprotocol/server-filesystem", "--arg", "E:\\CODE\\skills-manager")
            $parsed.command | Should -Be "npx"
            $parsed.args.Count | Should -Be 3
            $parsed.args[0] | Should -Be "-y"
            $parsed.args[1] | Should -Be "@modelcontextprotocol/server-filesystem"
        }

        It "Parses --arg=value wrappers but preserves every token after the separator" {
            $wrapped = Parse-McpInstallArgs @("filesystem", "--cmd", "npx", "--arg=-y")
            $wrapped.args | Should -Be @('-y')

            $passthrough = Parse-McpInstallArgs @("filesystem", "--cmd", "npx", "--", "--arg", "--arg=child-value")
            $passthrough.args.Count | Should -Be 2
            $passthrough.args[0] | Should -Be '--arg'
            $passthrough.args[1] | Should -Be '--arg=child-value'
        }

        It "Supports command tail after -- without --cmd" {
            $parsed = Parse-McpInstallArgs @("fetch", "--", "npx", "-y", "@modelcontextprotocol/server-fetch")
            $parsed.command | Should -Be "npx"
            $parsed.args.Count | Should -Be 2
            $parsed.args[1] | Should -Be "@modelcontextprotocol/server-fetch"
        }

        It "Supports stdio args that start with '-' after --cmd without explicit -- separator" {
            $parsed = Parse-McpInstallArgs @("context7", "--cmd", "npx", "-y", "@upstash/context7-mcp")
            $parsed.command | Should -Be "npx"
            $parsed.args.Count | Should -Be 2
            $parsed.args[0] | Should -Be "-y"
            $parsed.args[1] | Should -Be "@upstash/context7-mcp"
        }

        It "Supports command tail without explicit -- separator" {
            $parsed = Parse-McpInstallArgs @("git", "uvx", "mcp-server-git", "--repository", "E:\\CODE\\skills-manager")
            $parsed.command | Should -Be "uvx"
            $parsed.args.Count | Should -Be 3
            $parsed.args[0] | Should -Be "mcp-server-git"
        }

        It "Rejects missing --cmd value when next token is another flag" {
            $thrown = $false
            try {
                Parse-McpInstallArgs @("fetch", "--cmd", "--arg", "-y") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Rejects missing --url value when next token is another flag" {
            $thrown = $false
            try {
                Parse-McpInstallArgs @("remote", "--transport", "http", "--url", "--header", "k=v") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should -Be $true
        }

        It "Parses bearer token env var for remote MCP servers" {
            $parsed = Parse-McpInstallArgs @("github", "--transport", "http", "--url", "https://api.githubcopilot.com/mcp/readonly", "--bearer-token-env-var", "GITHUB_PERSONAL_ACCESS_TOKEN")
            $parsed.name | Should -Be "github"
            $parsed.transport | Should -Be "http"
            $parsed.bearer_token_env_var | Should -Be "GITHUB_PERSONAL_ACCESS_TOKEN"
        }

        It 'rejects new legacy SSE server definitions' {
            { Parse-McpInstallArgs @('legacy', '--transport', 'sse', '--url', 'https://example.invalid/sse') } |
                Should -Throw '*旧 SSE 已弃用*'
        }

        It "enforces ZIP entry budgets before extraction" {
            $source = Join-Path $TestDrive "zip-budget-source"
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $source "one.txt") -Value one
            Set-Content -LiteralPath (Join-Path $source "two.txt") -Value two
            $zip = Join-Path $TestDrive "zip-budget.zip"
            Compress-Archive -Path (Join-Path $source '*') -DestinationPath $zip

            { Assert-ZipArchiveSafety -ZipPath $zip -MaxEntries 1 } | Should -Throw
        }

        It "rejects traversal, symlink, and non-portable ZIP entry names" {
            foreach($case in @(
                [pscustomobject]@{ name='../escape.txt'; symlink=$false },
                [pscustomobject]@{ name='link'; symlink=$true },
                [pscustomobject]@{ name='CON.txt'; symlink=$false },
                [pscustomobject]@{ name='trailing. '; symlink=$false }
            )) {
                $zip = Join-Path $TestDrive (([guid]::NewGuid().ToString('N')) + '.zip')
                $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
                try {
                    $entry = $archive.CreateEntry([string]$case.name)
                    if([bool]$case.symlink){$entry.ExternalAttributes = (0xA000 -shl 16)}
                    $writer = [IO.StreamWriter]::new($entry.Open())
                    try { $writer.Write('x') } finally { $writer.Dispose() }
                }
                finally { $archive.Dispose() }

                { Assert-ZipArchiveSafety -ZipPath $zip } | Should -Throw
            }
        }

        It "preserves the previous cache when ZIP validation fails" {
            $oldImportDir = $ImportDir
            try {
                $ImportDir = Join-Path $TestDrive "imports-invalid-zip"
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null
                $target = Join-Path $TestDrive "preserved-cache"
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $target "keep.txt") -Value keep
                $invalidZip = Join-Path $TestDrive "invalid.zip"
                Set-Content -LiteralPath $invalidZip -Value 'not a zip archive'

                { Ensure-RepoFromZip $target $invalidZip $true } | Should -Throw
                Get-Content -LiteralPath (Join-Path $target "keep.txt") | Should -Be keep
            }
            finally { $ImportDir = $oldImportDir }
        }

        It "Rejects literal MCP secrets and URL credentials while allowing environment templates" {
            { Parse-McpInstallArgs @("stdio-secret", "--cmd", "tool", "--env", "API_KEY=literal-secret") | Out-Null } | Should -Throw
            { Parse-McpInstallArgs @("header-secret", "--transport", "http", "--url", "https://example.invalid/mcp", "--header", "Authorization=literal") | Out-Null } | Should -Throw
            { Parse-McpInstallArgs @("url-secret", "--transport", "http", "--url", "https://user:pass@example.invalid/mcp") | Out-Null } | Should -Throw
            { Parse-McpInstallArgs @("query-secret", "--transport", "http", "--url", "https://example.invalid/mcp?api_key=literal") | Out-Null } | Should -Throw
            { Parse-McpInstallArgs @("arg-secret", "--cmd", "tool", "--", "--token", "literal-secret") | Out-Null } | Should -Throw
            { Parse-McpInstallArgs @("arg-url-secret", "--cmd", "tool", "--", "postgresql://user:password@example.invalid/db") | Out-Null } | Should -Throw
            { Parse-McpInstallArgs @("curl-header-secret", "--cmd", "tool", "--", "--header", "Authorization: Bearer literal-secret") | Out-Null } | Should -Throw
            { Parse-McpInstallArgs @("curl-short-header-secret", "--cmd", "tool", "--", "-H", "X-API-Key: literal-secret") | Out-Null } | Should -Throw
            { Parse-McpInstallArgs @("curl-cookie-secret", "--cmd", "tool", "--", "--header=Cookie: session=literal-secret") | Out-Null } | Should -Throw

            $parsed = Parse-McpInstallArgs @("safe-secret", "--cmd", "tool", "--env", 'API_KEY=${UNIT_TEST_MCP_TOKEN}')
            [string]$parsed.env.API_KEY | Should -Be '${UNIT_TEST_MCP_TOKEN}'
            $safeArg = Parse-McpInstallArgs @("safe-arg", "--cmd", "tool", "--", "--token", '${UNIT_TEST_MCP_TOKEN}')
            [string]$safeArg.args[1] | Should -Be '${UNIT_TEST_MCP_TOKEN}'
            $headerParsed = Parse-McpInstallArgs @("safe-header", "--transport", "http", "--url", "https://example.invalid/mcp", "--header", 'Authorization=Bearer ${UNIT_TEST_MCP_TOKEN}')
            [string]$headerParsed.headers.Authorization | Should -Be 'Bearer ${UNIT_TEST_MCP_TOKEN}'
            $safeProcessHeader = Parse-McpInstallArgs @("safe-process-header", "--cmd", "tool", "--", "--header", 'Authorization: Bearer ${UNIT_TEST_MCP_TOKEN}', "--header", "Accept: application/json")
            $safeProcessHeader.args.Count | Should -Be 4
        }

        It "Rejects remote MCP URLs that are not absolute http or https URLs" {
            $thrown = $false
            try {
                Parse-McpInstallArgs @("remote", "--transport", "http", "--url", "file://C:/temp/mcp") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "http/https"
            }
            $thrown | Should -Be $true
        }

        It "Rejects bearer token env var names with invalid characters" {
            $thrown = $false
            try {
                Parse-McpInstallArgs @("github", "--transport", "http", "--url", "https://api.githubcopilot.com/mcp/readonly", "--bearer-token-env-var", "BAD-TOKEN-NAME") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "环境变量名"
            }
            $thrown | Should -Be $true
        }
    }

    Context "Convert-McpServersToConfigMap" {
        It "Builds MCP config map from server list" {
            $servers = @(
                [pscustomobject]@{
                    name      = "context7"
                    transport = "stdio"
                    command   = "npx"
                    args      = @("-y", "@upstash/context7-mcp")
                }
            )
            $map = Convert-McpServersToConfigMap $servers
            $map.PSObject.Properties.Name.Count | Should -Be 1
            $map.context7.command | Should -Be "npx"
            $map.context7.args.Count | Should -Be 2
        }

        It "Rejects remote MCP header values that contain newlines" {
            $servers = @(
                [pscustomobject]@{
                    name      = "github"
                    transport = "http"
                    url       = "https://api.githubcopilot.com/mcp"
                    headers   = [pscustomobject]@{
                        Authorization = "Bearer ok`nX-Evil: injected"
                    }
                }
            )

            $thrown = $false
            try {
                Convert-McpServersToConfigMap $servers | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should -Match "换行"
            }
            $thrown | Should -Be $true
        }
    }

    Context "Build-GeminiSettingsPayload" {
        It "Merges mcpServers into existing Gemini settings without dropping other fields" {
            $servers = @(
                [pscustomobject]@{
                    name      = "fetch"
                    transport = "stdio"
                    command   = "python"
                    args      = @("-m", "mcp_server_fetch")
                }
            )
            $existing = @'
{
  "tools": { "allowed": ["run_shell_command(git status)"] },
  "experimental": { "skills": true }
}
'@
            $payload = Build-GeminiSettingsPayload $existing $servers
            $payload.tools.allowed[0] | Should -Be "run_shell_command(git status)"
            $payload.experimental.skills | Should -Be $true
            $payload.mcpServers.fetch.command | Should -Be "python"
            $payload.mcpServers.fetch.args.Count | Should -Be 2
            $payload.mcpServers.fetch.PSObject.Properties.Name -contains "transport" | Should -Be $false
        }

        It "Builds minimal payload when existing settings is empty" {
            $servers = @(
                [pscustomobject]@{
                    name      = "fetch"
                    transport = "stdio"
                    command   = "python"
                    args      = @("-m", "mcp_server_fetch")
                }
            )
            $payload = Build-GeminiSettingsPayload "" $servers
            $payload.mcpServers.fetch.command | Should -Be "python"
        }

        It "Throws on malformed existing settings instead of rebuilding a minimal payload" {
            $servers = @(
                [pscustomobject]@{ name = "fetch"; transport = "stdio"; command = "python" }
            )
            { Build-GeminiSettingsPayload '{ "tools": { broken' $servers } | Should -Throw '*拒绝最小化重建*'
        }
    }

    Context "Build-GenericMcpPayload" {
        It "Throws on malformed existing host config to protect non-MCP host settings" {
            $servers = @(
                [pscustomobject]@{ name = "fetch"; transport = "stdio"; command = "python" }
            )
            { Build-GenericMcpPayload '{ "mcpServers": { broken' $servers } | Should -Throw '*拒绝最小化重建*'
        }
    }

    Context "Build-ZCodeMcpPayload" {
        It "Throws on malformed existing host config to protect non-MCP host settings" {
            $servers = @(
                [pscustomobject]@{ name = "fetch"; transport = "stdio"; command = "python" }
            )
            { Build-ZCodeMcpPayload '{ "mcp": { broken' $servers } | Should -Throw '*拒绝最小化重建*'
        }
    }

    Context "Ensure-GhAuthForGithubMcp" {
        It "Skips GitHub authentication when the server is explicitly disabled" {
            Mock Get-EnvironmentVariableWithScope { throw "disabled GitHub must not read credentials" }

            { Ensure-GhAuthForGithubMcp @([pscustomobject]@{ name = "github"; enabled = $false }) } | Should -Not -Throw

            Should -Invoke Get-EnvironmentVariableWithScope -Times 0 -Exactly
        }

        It "Rejects non-boolean enabled before probing GitHub authentication" {
            Mock Get-EnvironmentVariableWithScope { throw "invalid GitHub config must not read credentials" }

            { Ensure-GhAuthForGithubMcp @([pscustomobject]@{ name = "github"; enabled = "false" }) } | Should -Throw "mcp_server.enabled 必须是布尔值：github"

            Should -Invoke Get-EnvironmentVariableWithScope -Times 0 -Exactly
        }

        It "Hydrates GitHub tokens only in the current sync process" {
            $oldProcessGithub = $env:GITHUB_PERSONAL_ACCESS_TOKEN
            $oldProcessCodex = $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
            try {
                Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                Mock Get-EnvironmentVariableWithScope {
                    if ($name -eq "GITHUB_PERSONAL_ACCESS_TOKEN") {
                        return [pscustomobject]@{ name=$name; scope="User"; value="operator-supplied-token" }
                    }
                    return $null
                }

                Ensure-GhAuthForGithubMcp @([pscustomobject]@{ name = "github" })

                $env:GITHUB_PERSONAL_ACCESS_TOKEN | Should -Be "operator-supplied-token"
                $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN | Should -Be "operator-supplied-token"
                Get-Command Set-McpUserEnvironmentVariable -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
                Should -Invoke Get-EnvironmentVariableWithScope -Times 2 -Exactly
            }
            finally {
                if ($null -ne $oldProcessGithub) {
                    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldProcessGithub
                }
                else {
                    Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
                if ($null -ne $oldProcessCodex) {
                    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldProcessCodex
                }
                else {
                    Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
            }
        }

        It "Rejects conflicting operator-supplied GitHub tokens" {
            Mock Get-EnvironmentVariableWithScope {
                [pscustomobject]@{ name=$name; scope="Process"; value=$(if ($name -eq "GITHUB_PERSONAL_ACCESS_TOKEN") { "one" } else { "two" }) }
            }

            { Ensure-GhAuthForGithubMcp @([pscustomobject]@{ name = "github" }) } | Should -Throw "*不一致*"
        }
    }

    Context "Build-CodexConfigToml" {
        It "Preserves host-owned approval and sandbox settings" {
            $existing = @'
model = "gpt-5.6-luna"
sandbox_mode = "danger-full-access"
approval_policy = "on-request"

[features]
shell_tool = true
'@

            $toml = Build-CodexConfigToml $existing @()

            $toml | Should -Match 'sandbox_mode = "danger-full-access"'
            $toml | Should -Match 'approval_policy = "on-request"'
            $toml | Should -Match '(?m)^\[features\]\r?$'
            $toml | Should -Match '(?m)^shell_tool = true\r?$'
        }

        It "Converts Postgres key-value connection strings to URL form" {
            $url = Convert-PostgresKeyValueConnectionStringToUrl "Host=127.0.0.1;Port=55432;Database=postgres;Username=mcp_user;Password=p@ ss;"
            $url | Should -Be "postgresql://mcp_user:p%40%20ss@127.0.0.1:55432/postgres"
        }

        It "Normalizes Postgres MCP environment before sync writes config" {
            $oldProcess = $env:POSTGRES_CONNECTION_STRING
            try {
                $env:POSTGRES_CONNECTION_STRING = "Host=127.0.0.1;Port=55432;Database=postgres;Username=mcp_user;Password=secret;"
                $servers = @(
                    [pscustomobject]@{
                        name      = "postgres"
                        transport = "stdio"
                        command   = "pwsh"
                        args      = @("-NoLogo", "-NoProfile", "-Command", "npx -y @modelcontextprotocol/server-postgres `$env:POSTGRES_CONNECTION_STRING")
                    }
                )

                Ensure-PostgresMcpEnvironment $servers

                $env:POSTGRES_CONNECTION_STRING | Should -Be "postgresql://mcp_user:secret@127.0.0.1:55432/postgres"
                Get-Command Set-McpUserEnvironmentVariable -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            }
            finally {
                if ($null -ne $oldProcess) {
                    $env:POSTGRES_CONNECTION_STRING = $oldProcess
                }
                else {
                    Remove-Item Env:\POSTGRES_CONNECTION_STRING -ErrorAction SilentlyContinue
                }
            }
        }

        It "Skips Postgres environment checks when the server is explicitly disabled" {
            Mock Get-EnvironmentVariableWithScope { throw "disabled Postgres must not read credentials" } -ParameterFilter { $name -eq "POSTGRES_CONNECTION_STRING" }

            { Ensure-PostgresMcpEnvironment @([pscustomobject]@{ name = "postgres"; enabled = $false }) } | Should -Not -Throw

            Should -Invoke Get-EnvironmentVariableWithScope -Times 0 -Exactly -ParameterFilter { $name -eq "POSTGRES_CONNECTION_STRING" }
        }

        It "Rejects non-boolean Postgres enabled before reading credentials" {
            Mock Get-EnvironmentVariableWithScope { throw "invalid Postgres config must not read credentials" } -ParameterFilter { $name -eq "POSTGRES_CONNECTION_STRING" }

            { Ensure-PostgresMcpEnvironment @([pscustomobject]@{ name = "postgres"; enabled = "false" }) } | Should -Throw "mcp_server.enabled 必须是布尔值：postgres"

            Should -Invoke Get-EnvironmentVariableWithScope -Times 0 -Exactly -ParameterFilter { $name -eq "POSTGRES_CONNECTION_STRING" }
        }

        It "Replaces mcp_servers tables and preserves other codex config fields" {
            $oldToken = $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
            $oldGithubToken = $env:GITHUB_PERSONAL_ACCESS_TOKEN
            Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            try {
                $servers = @(
                    [pscustomobject]@{
                        name                 = "github"
                        transport            = "http"
                        url                  = "https://api.githubcopilot.com/mcp/readonly"
                        bearer_token_env_var = "GITHUB_PERSONAL_ACCESS_TOKEN"
                    }
                )
                $existing = @'
model = "gpt-5.3-codex"
personality = "pragmatic"

[mcp_servers.old]
command = "cmd"
args = ["/c", "echo", "old"]

[windows]
sandbox = "elevated"
'@
                $toml = Build-CodexConfigToml $existing $servers
                $toml | Should -Match "model = ""gpt-5.3-codex"""
                $toml | Should -Match "\[windows\]"
                $toml | Should -Match "\[mcp_servers\.old\]"
                $toml | Should -Not -Match "\[mcp_servers\.github\]"
                $toml | Should -Not -Match "url = ""https://api.githubcopilot.com/mcp/readonly"""
                $toml | Should -Not -Match "bearer_token_env_var = ""CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"""
            }
            finally {
                if ($null -ne $oldToken) {
                    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldToken
                }
                else {
                    Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
                if ($null -ne $oldGithubToken) {
                    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldGithubToken
                }
                else {
                    Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
            }
        }

        It "Clears existing mcp_servers tables when desired server list is empty" {
            $existing = @'
model = "gpt-5.3-codex"

[mcp_servers.old]
command = "cmd"
args = ["/c", "echo", "old"]

[windows]
sandbox = "elevated"
'@
            $toml = Build-CodexConfigToml $existing @()
            $toml | Should -Match "model = ""gpt-5.3-codex"""
            $toml | Should -Match "\[windows\]"
            $toml | Should -Not -Match "\[mcp_servers\.old\]"
        }

        It "Preserves host-owned node_repl and its child tables" {
            $existing = @'
model = "gpt-5.6-sol"

[mcp_servers.node_repl]
command = "C:\\runtime\\node_repl.exe"
args = []

[mcp_servers.node_repl.env]
NODE_REPL_NODE_PATH = "C:\\runtime\\node.exe"

[mcp_servers.old]
command = "cmd"
'@

            $toml = Build-CodexConfigToml $existing @()

            $toml | Should -Match "\[mcp_servers\.node_repl\]"
            $toml | Should -Match "\[mcp_servers\.node_repl\.env\]"
            $toml | Should -Match "NODE_REPL_NODE_PATH"
            $toml | Should -Not -Match "\[mcp_servers\.old\]"
        }

        It "Skips GitHub MCP when GitHub token is unavailable" {
            $oldToken = $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
            $oldGithubToken = $env:GITHUB_PERSONAL_ACCESS_TOKEN
            Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            try {
                $servers = @(
                    [pscustomobject]@{
                        name                 = "github"
                        transport            = "http"
                        url                  = "https://api.githubcopilot.com/mcp/readonly"
                        bearer_token_env_var = "GITHUB_PERSONAL_ACCESS_TOKEN"
                    }
                    [pscustomobject]@{
                        name      = "microsoft-learn"
                        transport = "http"
                        url       = "https://learn.microsoft.com/api/mcp"
                    }
                )

                $toml = Build-CodexConfigToml "" $servers
                $toml | Should -Not -Match "\[mcp_servers\.github\]"
                $toml | Should -Match "\[mcp_servers\.microsoft-learn\]"
                $toml | Should -Match "url = ""https://learn.microsoft.com/api/mcp"""
            }
            finally {
                if ($null -ne $oldToken) {
                    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldToken
                }
                else {
                    Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
                if ($null -ne $oldGithubToken) {
                    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldGithubToken
                }
                else {
                    Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
            }
        }

        It "Includes GitHub MCP when GitHub token is available" {
            $oldToken = $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
            $oldGithubToken = $env:GITHUB_PERSONAL_ACCESS_TOKEN
            $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = "unit-test-token"
            try {
                $servers = @(
                    [pscustomobject]@{
                        name                 = "github"
                        transport            = "http"
                        url                  = "https://api.githubcopilot.com/mcp/readonly"
                        bearer_token_env_var = "GITHUB_PERSONAL_ACCESS_TOKEN"
                    }
                    [pscustomobject]@{
                        name      = "microsoft-learn"
                        transport = "http"
                        url       = "https://learn.microsoft.com/api/mcp"
                    }
                )

                $toml = Build-CodexConfigToml "" $servers
                $toml | Should -Match "\[mcp_servers\.github\]"
                $toml | Should -Match "url = ""https://api.githubcopilot.com/mcp/readonly"""
                $toml | Should -Match "bearer_token_env_var = ""CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"""
                $toml | Should -Match "\[mcp_servers\.microsoft-learn\]"
            }
            finally {
                if ($null -ne $oldToken) {
                    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldToken
                }
                else {
                    Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
                if ($null -ne $oldGithubToken) {
                    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldGithubToken
                }
                else {
                    Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
            }
        }

        It "Writes startup_timeout_sec for codex mcp servers when configured" {
            $oldToken = $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
            $oldGithubToken = $env:GITHUB_PERSONAL_ACCESS_TOKEN
            $oldIncludeLeaky = $env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP
            Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            try {
                $env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP = "1"
                $servers = @(
                    [pscustomobject]@{
                        name                = "context7"
                        transport           = "stdio"
                        command             = "npx"
                        args                = @("-y", "@upstash/context7-mcp")
                        startup_timeout_sec = 120
                    }
                    [pscustomobject]@{
                        name                = "microsoft-learn"
                        transport           = "http"
                        url                 = "https://learn.microsoft.com/api/mcp"
                        startup_timeout_sec = "120"
                    }
                )

                $toml = Build-CodexConfigToml "" $servers
                $toml | Should -Match "\[mcp_servers\.context7\]"
                $toml | Should -Match "\[mcp_servers\.microsoft-learn\]"
                $toml | Should -Match "command = ""node"""
                $toml | Should -Match "mcp-node-cache-wrapper\.mjs"
                $toml | Should -Match "@upstash/context7-mcp"
                $toml | Should -Match "startup_timeout_sec = 120"
            }
            finally {
                if ($null -ne $oldToken) {
                    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldToken
                }
                else {
                    Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
                if ($null -ne $oldGithubToken) {
                    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldGithubToken
                }
                else {
                    Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
                if ($null -ne $oldIncludeLeaky) {
                    $env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP = $oldIncludeLeaky
                }
                else {
                    Remove-Item Env:\SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP -ErrorAction SilentlyContinue
                }
            }
        }

        It "Writes Codex MCP enabled state and enabled_tools when configured" {
            $servers = @(
                [pscustomobject]@{
                    name          = "context7"
                    transport     = "stdio"
                    command       = "npx"
                    args          = @("-y", "@upstash/context7-mcp")
                    enabled       = $false
                    enabled_tools = @("resolve-library-id", "query-docs")
                }
            )

            $toml = Build-CodexConfigToml "" $servers

            $toml | Should -Match "enabled = false"
            $toml | Should -Match 'enabled_tools = \["resolve-library-id", "query-docs"\]'
        }

        It "Projects the active MCP profile over base server definitions" {
            $cfg = [pscustomobject]@{
                mcp_servers = @(
                    [pscustomobject]@{ name = "context7"; transport = "stdio"; command = "npx"; enabled = $false }
                    [pscustomobject]@{ name = "github"; transport = "http"; url = "https://api.githubcopilot.com/mcp/"; enabled = $false }
                    [pscustomobject]@{ name = "postgres"; transport = "stdio"; command = "npx"; enabled = $false }
                )
                mcp_profiles = [pscustomobject]@{
                    active = "coding"
                    profiles = [pscustomobject]@{
                        coding = [pscustomobject]@{
                            enabled = @("context7", "github")
                            enabled_tools = [pscustomobject]@{
                                context7 = @("resolve-library-id", "query-docs")
                                github = @("get_me", "get_file_contents")
                            }
                        }
                    }
                }
            }

            $servers = @(Resolve-McpProfileServers $cfg)

            ($servers | Where-Object name -eq "context7").enabled | Should -Be $true
            @((($servers | Where-Object name -eq "context7").enabled_tools)) | Should -Be @("resolve-library-id", "query-docs")
            ($servers | Where-Object name -eq "github").enabled | Should -Be $true
            ($servers | Where-Object name -eq "postgres").enabled | Should -Be $false
        }

        It "Returns only active profile servers for generic hosts" {
            $servers = @(
                [pscustomobject]@{ name = "docs"; enabled = $true }
                [pscustomobject]@{ name = "database"; enabled = $false }
                [pscustomobject]@{ name = "legacy-without-flag" }
            )

            @((Get-ActiveMcpServers $servers) | ForEach-Object name) | Should -Be @("docs", "legacy-without-flag")
        }

        It "Preserves GitHub MCP activation fields when a token is available" {
            $oldToken = $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
            try {
                $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = "test-token"
                $server = [pscustomobject]@{
                    name          = "github"
                    transport     = "http"
                    url           = "https://api.githubcopilot.com/mcp/"
                    enabled       = $false
                    enabled_tools = @("get_file_contents")
                }

                $toml = Build-CodexConfigToml "" @($server)

                $toml | Should -Match "\[mcp_servers\.github\]"
                $toml | Should -Match "enabled = false"
                $toml | Should -Match 'enabled_tools = \["get_file_contents"\]'
            }
            finally {
                if ($null -ne $oldToken) {
                    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldToken
                }
                else {
                    Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
            }
        }

        It "Keeps an explicitly disabled GitHub MCP when no token is available" {
            $oldToken = $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
            $oldGithubToken = $env:GITHUB_PERSONAL_ACCESS_TOKEN
            try {
                Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                $server = [pscustomobject]@{
                    name      = "github"
                    transport = "http"
                    url       = "https://api.githubcopilot.com/mcp/"
                    enabled   = $false
                }

                $toml = Build-CodexConfigToml "" @($server)

                $toml | Should -Match "\[mcp_servers\.github\]"
                $toml | Should -Match "enabled = false"
            }
            finally {
                if ($null -ne $oldToken) {
                    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldToken
                }
                else {
                    Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
                if ($null -ne $oldGithubToken) {
                    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldGithubToken
                }
                else {
                    Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
            }
        }

        It "Includes Codex MCP activation fields in server equivalence" {
            $disabled = [pscustomobject]@{
                name          = "context7"
                transport     = "stdio"
                command       = "npx"
                args          = @("-y", "@upstash/context7-mcp")
                enabled       = $false
                enabled_tools = @("query-docs")
            }
            $enabled = [pscustomobject]@{
                name          = "context7"
                transport     = "stdio"
                command       = "npx"
                args          = @("-y", "@upstash/context7-mcp")
                enabled       = $true
                enabled_tools = @("query-docs")
            }

            (Test-McpServerEquivalent $disabled $enabled) | Should -Be $false
        }

        It "Treats Codex MCP enabled_tools as an order-independent set" {
            $first = [pscustomobject]@{
                name          = "context7"
                transport     = "stdio"
                command       = "npx"
                args          = @("-y", "@upstash/context7-mcp")
                enabled_tools = @("query-docs", "resolve-library-id")
            }
            $second = [pscustomobject]@{
                name          = "context7"
                transport     = "stdio"
                command       = "npx"
                args          = @("-y", "@upstash/context7-mcp")
                enabled_tools = @("resolve-library-id", "query-docs", "query-docs")
            }

            (Test-McpServerEquivalent $first $second) | Should -Be $true
        }

        It "Writes OpenAI developer docs MCP for codex when configured as http transport" {
            $servers = @(
                [pscustomobject]@{
                    name                = "openaiDeveloperDocs"
                    transport           = "http"
                    url                 = "https://developers.openai.com/mcp"
                    startup_timeout_sec = 120
                }
            )

            $toml = Build-CodexConfigToml "" $servers
            $toml | Should -Match "\[mcp_servers\.openaiDeveloperDocs\]"
            $toml | Should -Match "transport = ""http"""
            $toml | Should -Match "url = ""https://developers.openai.com/mcp"""
            $toml | Should -Match "startup_timeout_sec = 120"
        }

        It "Wraps Codex npx stdio MCP servers through the Node cache wrapper" {
            $oldIncludeLeaky = $env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP
            $env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP = "1"
            $servers = @(
                [pscustomobject]@{
                    name      = "filesystem"
                    transport = "stdio"
                    command   = "npx"
                    args      = @("-y", "@modelcontextprotocol/server-filesystem", "D:\CODE")
                }
                [pscustomobject]@{
                    name      = "playwright"
                    transport = "stdio"
                    command   = "npx"
                    args      = @("@playwright/mcp@latest", "--isolated")
                }
            )

            try {
                $toml = Build-CodexConfigToml "" $servers

                $toml | Should -Match "\[mcp_servers\.filesystem\]"
                $toml | Should -Match "\[mcp_servers\.playwright\]"
                $toml | Should -Match "command = ""node"""
                $toml | Should -Match "mcp-node-cache-wrapper\.mjs"
                $toml | Should -Match "@modelcontextprotocol/server-filesystem"
                $toml | Should -Match "@playwright/mcp"
                $toml | Should -Match "D:\\\\CODE"
                $toml | Should -Match "--isolated"
                $toml | Should -Not -Match "command = ""npx"""
            }
            finally {
                if ($null -ne $oldIncludeLeaky) {
                    $env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP = $oldIncludeLeaky
                }
                else {
                    Remove-Item Env:\SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP -ErrorAction SilentlyContinue
                }
            }
        }

        It "Preserves an exact scoped package selector in the Codex cache wrapper" {
            $server = [pscustomobject]@{
                name      = "context7"
                transport = "stdio"
                command   = "npx"
                args      = @("-y", "@upstash/context7-mcp@3.2.3")
            }

            $wrapped = Convert-CodexNpxServerToCachedNodeWrapper $server

            $wrapped | Should -Not -BeNullOrEmpty
            $wrapped.args[1] | Should -Be "@upstash/context7-mcp@3.2.3"
            $wrapped.args[2] | Should -Be "dist/index.js"
        }

        It "Fails closed until the exact npm package version exists in the cache" {
            $oldNpmCache = $env:npm_config_cache
            $cacheRoot = Join-Path $TestDrive "npm-cache"
            $wrapperPath = Join-Path $TestDrive "mcp-node-cache-wrapper.mjs"
            $wrongPackageRoot = Join-Path $cacheRoot "_npx\wrong\node_modules\@upstash\context7-mcp"
            $rightPackageRoot = Join-Path $cacheRoot "_npx\right\node_modules\@upstash\context7-mcp"
            try {
                $env:npm_config_cache = $cacheRoot
                New-Item -ItemType Directory -Path (Join-Path $wrongPackageRoot "dist") -Force | Out-Null
                Set-ContentUtf8 (Join-Path $wrongPackageRoot "package.json") '{"name":"@upstash/context7-mcp","version":"3.2.2","type":"module"}'
                Set-ContentUtf8 (Join-Path $wrongPackageRoot "dist\index.js") 'process.stdout.write("wrong");'
                Set-ContentUtf8 $wrapperPath (Get-CodexMcpNodeCacheWrapperContent)

                $missingOutput = & node $wrapperPath "@upstash/context7-mcp@3.2.3" "dist/index.js" 2>&1

                $LASTEXITCODE | Should -Be 69
                (@($missingOutput) -join "`n") | Should -Match "Cached @upstash/context7-mcp@3.2.3 package was not found"

                New-Item -ItemType Directory -Path (Join-Path $rightPackageRoot "dist") -Force | Out-Null
                Set-ContentUtf8 (Join-Path $rightPackageRoot "package.json") '{"name":"@upstash/context7-mcp","version":"3.2.3","type":"module"}'
                Set-ContentUtf8 (Join-Path $rightPackageRoot "dist\index.js") 'process.stdout.write("right");'

                $matchedOutput = & node $wrapperPath "@upstash/context7-mcp@3.2.3" "dist/index.js" 2>&1

                $LASTEXITCODE | Should -Be 0
                (@($matchedOutput) -join "`n") | Should -Be "right"
            }
            finally {
                if ($null -ne $oldNpmCache) {
                    $env:npm_config_cache = $oldNpmCache
                }
                else {
                    Remove-Item Env:\npm_config_cache -ErrorAction SilentlyContinue
                }
            }
        }

        It "Includes known npx MCP servers for Codex through the cache wrapper by default" {
            $oldIncludeLeaky = $env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP
            Remove-Item Env:\SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP -ErrorAction SilentlyContinue
            try {
                $servers = @(
                    [pscustomobject]@{
                        name      = "context7"
                        transport = "stdio"
                        command   = "npx"
                        args      = @("-y", "@upstash/context7-mcp")
                    }
                    [pscustomobject]@{
                        name      = "postgres"
                        transport = "stdio"
                        command   = "pwsh"
                        args      = @("-NoLogo", "-NoProfile", "-Command", "npx -y @modelcontextprotocol/server-postgres `$env:POSTGRES_CONNECTION_STRING")
                    }
                )

                $toml = Build-CodexConfigToml "" $servers

                $toml | Should -Match "\[mcp_servers\.context7\]"
                $toml | Should -Match "mcp-node-cache-wrapper\.mjs"
                $toml | Should -Match "@upstash/context7-mcp"
                $toml | Should -Match "\[mcp_servers\.postgres\]"
            }
            finally {
                if ($null -ne $oldIncludeLeaky) {
                    $env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP = $oldIncludeLeaky
                }
                else {
                    Remove-Item Env:\SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP -ErrorAction SilentlyContinue
                }
            }
        }

        It "Wraps Codex postgres MCP through the cached Node env wrapper" {
            $servers = @(
                [pscustomobject]@{
                    name      = "postgres"
                    transport = "stdio"
                    command   = "pwsh"
                    args      = @("-NoLogo", "-NoProfile", "-Command", "npx -y @modelcontextprotocol/server-postgres `$env:POSTGRES_CONNECTION_STRING")
                }
            )

            $toml = Build-CodexConfigToml "" $servers

            $toml | Should -Match "\[mcp_servers\.postgres\]"
            $toml | Should -Match "command = ""node"""
            $toml | Should -Match "mcp-postgres-env-wrapper\.mjs"
            $toml | Should -Not -Match "@modelcontextprotocol/server-postgres"
            $toml | Should -Not -Match "command = ""pwsh"""
        }

        It "Generates a postgres wrapper that can read User scope environment variables" {
            $content = Get-CodexMcpPostgresEnvWrapperContent

            $content | Should -Match "resolveEnvironmentVariable"
            $content | Should -Match "GetEnvironmentVariable"
            $content | Should -Match "POSTGRES_CONNECTION_STRING"
            $content | Should -Match '"User"'
            $content | Should -Match '"Machine"'
            $content | Should -Match "inferUserHomeFromWrapperPath"
            $content | Should -Match "AppData"
            $content | Should -Match "normalizePostgresConnectionString"
            $content | Should -Match "postgresql://"
        }

    }

    Context "Resolve-GeminiAntigravityRootsFromCandidates" {
        It "Extracts antigravity roots from resolved candidate paths" {
            $paths = @(
                "C:\Users\sciman\.gemini\skills",
                "C:\Users\sciman\.gemini\antigravity\skills",
                "C:\Users\sciman\.trae\skills"
            )
            $roots = Resolve-GeminiAntigravityRootsFromCandidates $paths
            $roots.Count | Should -Be 1
            $roots[0] | Should -Be "C:\Users\sciman\.gemini\antigravity"
        }

        It "Ignores lookalike paths that are not antigravity directory" {
            $paths = @(
                "C:\Users\sciman\.gemini\antigravity-backup\skills",
                "C:\Users\sciman\.gemini\antigravity2\skills"
            )
            $roots = Resolve-GeminiAntigravityRootsFromCandidates $paths
            @($roots).Count | Should -Be 0
        }

        It "Finds valid antigravity root even when an earlier lookalike appears in path" {
            $paths = @(
                "C:\tmp\.gemini\antigravity-backup\foo\.gemini\antigravity\skills"
            )
            $roots = Resolve-GeminiAntigravityRootsFromCandidates $paths
            $roots.Count | Should -Be 1
            $roots[0] | Should -Be "C:\tmp\.gemini\antigravity-backup\foo\.gemini\antigravity"
        }

        It "Requires directory boundary before .gemini token" {
            $paths = @(
                "C:\tmp\foo.gemini\antigravity\skills"
            )
            $roots = Resolve-GeminiAntigravityRootsFromCandidates $paths
            @($roots).Count | Should -Be 0
        }
    }

    Context "Get-TraeProjectMcpConfigPath" {
        It "Builds project-level Trae MCP config path under repo root" {
            $repoRoot = Join-Path $TestDrive "skills-manager"
            $path = Get-TraeProjectMcpConfigPath $repoRoot
            $path | Should -Be (Join-Path $repoRoot ".trae\mcp.json")
        }
    }

    Context "Get-NativeMcpCleanupCommands" {
        It "Includes Claude user and local cleanup commands for removed server" {
            $cmds = Get-NativeMcpCleanupCommands "fetch"
            $serialized = $cmds | ForEach-Object { "$($_.command) $($_.args -join ' ')" }
            ($serialized -join "`n") | Should -Match "claude mcp remove fetch --scope user"
            ($serialized -join "`n") | Should -Match "claude mcp remove fetch --scope project"
        }
    }

    Context "Get-NativeMcpAddArgs" {
        It "Places HTTP headers after name/url without expanding env placeholders into argv" {
            $oldUnitToken = $env:UNIT_TEST_MCP_TOKEN
            $env:UNIT_TEST_MCP_TOKEN = "unit-test-token"
            try {
                $server = [pscustomobject]@{
                    name      = "github"
                    transport = "http"
                    url       = "https://api.githubcopilot.com/mcp"
                    headers   = [pscustomobject]@{
                        Authorization = 'Bearer ${UNIT_TEST_MCP_TOKEN}'
                    }
                }

                $args = Get-NativeMcpAddArgs $server "user"
                $joined = $args -join ' '
                $joined | Should -Match '--transport http github https://api\.githubcopilot\.com/mcp'
                $joined | Should -Match '-H Authorization: Bearer \$\{UNIT_TEST_MCP_TOKEN\}'
                $joined | Should -Not -Match 'Bearer unit-test-token'
                $joined | Should -Not -Match 'Authorization=Bearer'
            }
            finally {
                if ($null -ne $oldUnitToken) {
                    $env:UNIT_TEST_MCP_TOKEN = $oldUnitToken
                }
                else {
                    Remove-Item Env:\UNIT_TEST_MCP_TOKEN -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context "MCP managed target transaction" {
        It "creates an absent managed root only below an existing non-reparse parent" {
            $parent = Join-Path $TestDrive "mcp-new-root-parent"
            $root = Join-Path $parent ".codex"
            $path = Join-Path $root "mcp.json"
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            $target = [pscustomobject]@{path=$path;root=$root;kind='generic_json';before_hash=$null;desired_content='desired';changed=$true}

            $result = Invoke-McpManagedTargetTransaction @($target)

            $result.pass | Should -Be $true
            Get-ContentUtf8 $path | Should -Be 'desired'
            Test-Path -LiteralPath (Join-Path $root '.skills-manager-mcp-sync.lock') | Should -Be $false
        }

        It "removes a transaction-created managed root when the first write fails" {
            $parent = Join-Path $TestDrive "mcp-new-root-rollback-parent"
            $root = Join-Path $parent ".codex"
            $path = Join-Path $root "mcp.json"
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            $target = [pscustomobject]@{path=$path;root=$root;kind='generic_json';before_hash=$null;desired_content='desired';changed=$true}
            Mock Write-McpDesiredTarget { throw 'injected first write failure' }

            { Invoke-McpManagedTargetTransaction @($target) | Out-Null } | Should -Throw

            Test-Path -LiteralPath $root | Should -Be $false
        }

        It "fails closed when a target changes after planning" {
            $root = Join-Path $TestDrive "mcp-cas-root"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Join-Path $root "mcp.json"
            Set-ContentUtf8 $path '{"state":"planned"}'
            $target = [pscustomobject]@{ path=$path; root=$root; kind='generic_json'; before_hash=(Get-OperationSha256 (Get-ContentUtf8 $path)); desired_content='{"state":"desired"}'; changed=$true }
            Set-ContentUtf8 $path '{"state":"concurrent"}'

            { Invoke-McpManagedTargetTransaction @($target) | Out-Null } | Should -Throw
            Get-ContentUtf8 $path | Should -Be '{"state":"concurrent"}'
        }

        It "restores earlier targets when a later managed write fails" {
            $root = Join-Path $TestDrive "mcp-transaction-root"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $firstPath = Join-Path $root "first.json"
            $secondPath = Join-Path $root "second.json"
            Set-ContentUtf8 $firstPath 'first-before'
            Set-ContentUtf8 $secondPath 'second-before'
            $targets = @(
                [pscustomobject]@{ path=$firstPath; root=$root; kind='generic_json'; before_hash=(Get-OperationSha256 'first-before'); desired_content='first-after'; changed=$true },
                [pscustomobject]@{ path=$secondPath; root=$root; kind='generic_json'; before_hash=(Get-OperationSha256 'second-before'); desired_content='second-after'; changed=$true }
            )
            Mock Write-McpDesiredTarget {
                param($target)
                if ([string]$target.path -eq $secondPath) { throw 'injected second write failure' }
                Set-ContentUtf8 ([string]$target.path) ([string]$target.desired_content)
            }

            { Invoke-McpManagedTargetTransaction $targets | Out-Null } | Should -Throw
            Get-ContentUtf8 $firstPath | Should -Be 'first-before'
            Get-ContentUtf8 $secondPath | Should -Be 'second-before'
        }

        It "refuses rollback over an independently changed managed target" {
            $root = Join-Path $TestDrive "mcp-rollback-conflict"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Join-Path $root "mcp.json"
            Set-ContentUtf8 $path 'outside-change'
            $snapshot = [pscustomobject]@{
                path = $path
                existed = $true
                bytes = [Text.UTF8Encoding]::new($false).GetBytes('before')
                before_hash = Get-OperationSha256 'before'
                desired_hash = Get-OperationSha256 'desired'
            }

            { Restore-McpManagedTargetSnapshot @($snapshot) } | Should -Throw
            Get-ContentUtf8 $path | Should -Be 'outside-change'
        }

        It "redacts space-delimited secrets and URL userinfo in MCP diagnostics" {
            $masked = Mask-SensitiveMcpCommandText 'token secret-value https://user:pass@example.invalid Authorization: Bearer abc123'
            $masked | Should -Not -Match 'secret-value|user:pass|abc123'
            $masked | Should -Match '<redacted>'
        }

        It "rolls back implicit Codex wrapper sidecars when the target write fails" {
            $root = Join-Path $TestDrive "mcp-sidecar-rollback"
            $scripts = Join-Path $root "scripts"
            New-Item -ItemType Directory -Path $scripts -Force | Out-Null
            $targetPath = Join-Path $root "config.toml"
            $nodeWrapper = Join-Path $scripts "mcp-node-cache-wrapper.mjs"
            $postgresWrapper = Join-Path $scripts "mcp-postgres-env-wrapper.mjs"
            Set-ContentUtf8 $targetPath 'before-target'
            Set-ContentUtf8 $nodeWrapper 'before-node'
            Set-ContentUtf8 $postgresWrapper 'before-postgres'
            $target = [pscustomobject]@{path=$targetPath;root=$root;kind='codex_toml';before_hash=(Get-OperationSha256 'before-target');desired_content='after-target';changed=$true}
            Mock Write-Utf8FileAtomic {
                param($Path,$Content)
                if(-not [string]::IsNullOrWhiteSpace([string]$targetPath) -and [IO.Path]::GetFullPath($Path) -eq [IO.Path]::GetFullPath($targetPath)){throw 'injected target failure'}
                $parent=Split-Path $Path -Parent
                if(-not [string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
                [IO.File]::WriteAllText($Path,[string]$Content,[Text.UTF8Encoding]::new($false))
            }

            { Invoke-McpManagedTargetTransaction @($target) | Out-Null } | Should -Throw
            Get-ContentUtf8 $targetPath | Should -Be 'before-target'
            Get-ContentUtf8 $nodeWrapper | Should -Be 'before-node'
            Get-ContentUtf8 $postgresWrapper | Should -Be 'before-postgres'
        }

        It "does not enter a managed transaction while the target root lock is held" {
            $root = Join-Path $TestDrive "mcp-lock-held"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Join-Path $root "mcp.json"
            Set-ContentUtf8 $path 'before'
            $target = [pscustomobject]@{path=$path;root=$root;kind='generic_json';before_hash=(Get-OperationSha256 'before');desired_content='after';changed=$true}
            $lockPath = Join-Path $root '.skills-manager-mcp-sync.lock'
            $lock = [IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { { Invoke-McpManagedTargetTransaction @($target) | Out-Null } | Should -Throw }
            finally { $lock.Dispose(); Remove-Item -LiteralPath $lockPath -Force }

            Get-ContentUtf8 $path | Should -Be 'before'
        }
    }

    Context "Remove-McpServersFromPayload" {
        It "Removes legacy MCP servers from merged payloads" {
            $payload = [pscustomobject]@{
                mcpServers = [pscustomobject]@{
                    context7 = [pscustomobject]@{ type = "stdio" }
                    fetch = [pscustomobject]@{ type = "stdio" }
                    filesystem = [pscustomobject]@{ type = "stdio" }
                    microsoft_learn = [pscustomobject]@{ type = "http" }
                }
            }

            $updated = Remove-McpServersFromPayload $payload @("fetch", "filesystem")
            $updated.mcpServers.PSObject.Properties.Name -contains "context7" | Should -Be $true
            $updated.mcpServers.PSObject.Properties.Name -contains "fetch" | Should -Be $false
            $updated.mcpServers.PSObject.Properties.Name -contains "filesystem" | Should -Be $false
            $updated.mcpServers.PSObject.Properties.Name -contains "microsoft_learn" | Should -Be $true
        }
    }

    Context "Get-LegacyMcpServersToPrune" {
        It "Returns fetch and filesystem as legacy MCP names" {
            $names = Get-LegacyMcpServersToPrune
            @($names).Count | Should -Be 2
            ($names -contains "fetch") | Should -Be $true
            ($names -contains "filesystem") | Should -Be $true
        }

        It "Does not prune legacy names that are explicitly managed" {
            $servers = @(
                [pscustomobject]@{
                    name = "filesystem"
                    transport = "stdio"
                    command = "npx"
                    args = @("-y", "@modelcontextprotocol/server-filesystem", "D:\CODE")
                }
            )

            $names = Get-McpServersToPrune $servers
            ($names -contains "fetch") | Should -Be $true
            ($names -contains "filesystem") | Should -Be $false
        }
    }

    Context "MCP verify timeout and fallback" {
        It "Includes timed_out and error fields in external command capture" {
            Mock Invoke-ExternalCommandWithTimeout {
                [pscustomobject]@{
                    timed_out = $true
                    exit_code = 124
                    output = @("line")
                    error = "timeout_after_5s"
                }
            } -ParameterFilter {
                $command -eq "gemini" -and $timeoutSeconds -eq 5
            }

            $result = Invoke-ExternalCommandCapture "gemini" @("mcp", "list") 5
            $result.timed_out | Should -Be $true
            $result.exit_code | Should -Be 124
            $result.error | Should -Be "timeout_after_5s"
            @($result.output).Count | Should -Be 1
        }

        It "Passes arguments through timeout wrapper without colliding with automatic args" {
            $result = Invoke-ExternalCommandWithTimeout -command "cmd" -args @("/c", "echo wrapper-args-ok") -workingDir $TestDrive -timeoutSeconds 5

            $result.timed_out | Should -Be $false
            $result.exit_code | Should -Be 0
            (($result.output | ForEach-Object { [string]$_ }) -join "`n") | Should -Match "wrapper-args-ok"
        }

        It "Preserves single arguments that contain spaces" {
            $scriptPath = Join-Path $TestDrive "arg-check.ps1"
            Set-ContentUtf8 $scriptPath @'
param([string]$value)
if ($value -eq "Authorization: Bearer unit-test-token") {
    Write-Output "arg-space-ok"
    exit 0
}
Write-Error ("bad-arg:{0}" -f $value)
exit 3
'@
            $psExe = (Get-Process -Id $PID).Path

            $result = Invoke-ExternalCommandWithTimeout $psExe @(
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                $scriptPath,
                "Authorization: Bearer unit-test-token"
            ) $TestDrive 5

            $result.timed_out | Should -Be $false
            $result.exit_code | Should -Be 0
            (($result.output | ForEach-Object { [string]$_ }) -join "`n") | Should -Match "arg-space-ok"
        }

        It "Applies environment overrides to child process execution" {
            $result = Invoke-ExternalCommandWithTimeout "cmd" @(
                "/c",
                "echo %UNIT_TEST_MCP_ENV%"
            ) $TestDrive 5 @{
                UNIT_TEST_MCP_ENV = "env-override-ok"
            }

            $result.timed_out | Should -Be $false
            $result.exit_code | Should -Be 0
            (($result.output | ForEach-Object { [string]$_ }) -join "`n").Trim() | Should -Be "env-override-ok"
        }

        It "Preserves output captured before an external command timeout" {
            $result = Invoke-ExternalCommandWithTimeout "cmd" @(
                "/c",
                "echo before-timeout && ping -n 4 127.0.0.1 >nul"
            ) $TestDrive 1

            $result.timed_out | Should -Be $true
            $result.exit_code | Should -Be 124
            (($result.output | ForEach-Object { [string]$_ }) -join "`n") | Should -Match "before-timeout"
            $result.error | Should -Match "timeout_after_1s"
        }

        It "Clamps timeout value from env to the configured bounds" {
            $name = "SKILLS_MCP_TIMEOUT_CLAMP_TEST"
            $old = [System.Environment]::GetEnvironmentVariable($name)
            try {
                [System.Environment]::SetEnvironmentVariable($name, "0")
                (Resolve-TimeoutSecondsFromEnv $name 30 1 600) | Should -Be 1

                [System.Environment]::SetEnvironmentVariable($name, "9999")
                (Resolve-TimeoutSecondsFromEnv $name 30 1 600) | Should -Be 600

                [System.Environment]::SetEnvironmentVariable($name, "42")
                (Resolve-TimeoutSecondsFromEnv $name 30 1 600) | Should -Be 42
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($name, $old)
            }
        }

        It "Detects non-interactive MCP error hints" {
            (Test-IsNonInteractiveMcpError "Error: Input must be provided either through stdin") | Should -Be $true
            (Test-IsNonInteractiveMcpError "stdout is not a terminal") | Should -Be $true
            (Test-IsNonInteractiveMcpError "random failure text") | Should -Be $false
        }

        It "Resolves PowerShell wrapper commands to pwsh-first invocation" {
            Mock Get-Command {
                [pscustomobject]@{
                    Path = "C:\tools\demo.ps1"
                }
            } -ParameterFilter { $Name -eq "demo" }

            $invocation = Resolve-ExternalCommandInvocation "demo" @("mcp", "list")
            Split-Path -Leaf $invocation.file | Should -Match "^(pwsh|powershell)(\.exe)?$"
            $invocation.args[4] | Should -Be "-File"
            $invocation.args[5] | Should -Be "C:\tools\demo.ps1"
            $invocation.args[6] | Should -Be "mcp"
            $invocation.args[7] | Should -Be "list"
        }

        It "Keeps native executable path when command is not a PowerShell wrapper" {
            Mock Get-Command {
                [pscustomobject]@{
                    Path = "C:\tools\demo.exe"
                }
            } -ParameterFilter { $Name -eq "demoexe" }

            $invocation = Resolve-ExternalCommandInvocation "demoexe" @("arg1")
            $invocation.file | Should -Be "C:\tools\demo.exe"
            @($invocation.args).Count | Should -Be 1
            $invocation.args[0] | Should -Be "arg1"
        }

        It "Skips gemini CLI verification by default" {
            $result = Test-CliMcpServerReady "gemini" @("context7")
            $result.ok | Should -Be $true
            $result.reason | Should -Be "gemini_cli_verification_skipped"
            @($result.missing).Count | Should -Be 0
        }

        It "Falls back to config-state success when gemini CLI is missing in forced verification mode" {
            $old = [System.Environment]::GetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI")
            try {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", "1")
                Mock Get-Command { $null } -ParameterFilter { $Name -eq "gemini" }

                $result = Test-CliMcpServerReady "gemini" @("context7")
                $result.ok | Should -Be $true
                $result.reason | Should -Be "gemini_cli_not_found_fallback"
                @($result.missing).Count | Should -Be 0
            }
            finally {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", $old)
            }
        }

        It "Falls back to config-state success when gemini mcp list times out in forced verification mode" {
            $old = [System.Environment]::GetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI")
            try {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", "1")
                Mock Get-Command { [pscustomobject]@{ Name = "gemini" } } -ParameterFilter { $Name -eq "gemini" }
                Mock Get-McpListVerifyTimeoutSeconds { 7 } -ParameterFilter { $cli -eq "gemini" }
                Mock Invoke-ExternalCommandCapture {
                    [pscustomobject]@{
                        command = "gemini"
                        args = @("mcp", "list")
                        exit_code = 124
                        timed_out = $true
                        error = "timeout_after_7s"
                        output = @()
                    }
                } -ParameterFilter { $command -eq "gemini" }

                $result = Test-CliMcpServerReady "gemini" @("context7")
                $result.ok | Should -Be $true
                $result.reason | Should -Be "gemini_cli_timeout_fallback_7s"
                @($result.missing).Count | Should -Be 0
            }
            finally {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", $old)
            }
        }

        It "Hydrates gemini GitHub token from user scope during live verification when process env is stale" {
            $oldVerify = [System.Environment]::GetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI")
            $oldProcessGithub = $env:GITHUB_PERSONAL_ACCESS_TOKEN
            $expectedWorkingDir = [Environment]::GetFolderPath("UserProfile")
            try {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", "1")
                Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                Mock Get-McpUserEnvironmentVariable { "gho_user_scope_token" } -ParameterFilter { $name -eq "GITHUB_PERSONAL_ACCESS_TOKEN" }
                Mock Get-Command { [pscustomobject]@{ Name = "gemini" } } -ParameterFilter { $Name -eq "gemini" }
                Mock Get-McpListVerifyTimeoutSeconds { 9 } -ParameterFilter { $cli -eq "gemini" }
                Mock Invoke-ExternalCommandCapture {
                    [pscustomobject]@{
                        command = "gemini"
                        args = @("mcp", "list")
                        exit_code = 0
                        timed_out = $false
                        error = ""
                        output = @("✓ github: https://api.githubcopilot.com/mcp/ (http) - Connected")
                    }
                } -ParameterFilter {
                    $command -eq "gemini" -and
                    $timeoutSeconds -eq 9 -and
                    $EnvironmentOverrides -ne $null -and
                    $EnvironmentOverrides["GITHUB_PERSONAL_ACCESS_TOKEN"] -eq "gho_user_scope_token" -and
                    $workingDir -eq $expectedWorkingDir
                }

                $result = Test-CliMcpServerReady "gemini" @("github")
                $result.ok | Should -Be $true
                $result.reason | Should -Be "ok"
                Should -Invoke Invoke-ExternalCommandCapture -Times 1 -Scope It -ParameterFilter {
                    $command -eq "gemini" -and
                    $EnvironmentOverrides -ne $null -and
                    $EnvironmentOverrides["GITHUB_PERSONAL_ACCESS_TOKEN"] -eq "gho_user_scope_token" -and
                    $workingDir -eq $expectedWorkingDir
                }
            }
            finally {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", $oldVerify)
                if ([string]::IsNullOrWhiteSpace($oldProcessGithub)) {
                    Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                }
                else {
                    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldProcessGithub
                }
            }
        }

        It "Uses config-state verification by default without invoking live CLI list" {
            $root = Join-Path $TestDrive "mcp-fast-verify"
            $claudeRoot = Join-Path $root ".claude"
            New-Item -ItemType Directory -Path $claudeRoot -Force | Out-Null
            Set-ContentUtf8 (Join-Path $claudeRoot ".mcp.json") '{"mcpServers":{"context7":{"transport":"stdio","command":"npx","args":["-y","@upstash/context7-mcp"]}}}'
            Mock Invoke-ExternalCommandCapture { throw "live cli list should not be called by default" }

            Verify-McpAcrossCliWithRetry @($claudeRoot) 1 1

            Should -Invoke Invoke-ExternalCommandCapture -Times 0 -Scope It
        }

        It "Skips native Claude MCP commands by default" {
            Mock Invoke-ExternalCommandWithTimeout { throw "native command should not be called by default" }

            Invoke-NativeMcpCleanup "fetch"
            Invoke-NativeMcpSync @([pscustomobject]@{ name = "context7"; transport = "stdio"; command = "npx"; args = @("-y", "@upstash/context7-mcp") })

            Should -Invoke Invoke-ExternalCommandWithTimeout -Times 0 -Scope It
        }

        It "Replaces existing native Claude MCP servers during explicit native sync" {
            $old = [System.Environment]::GetEnvironmentVariable("SKILLS_MCP_NATIVE_SYNC")
            $script:nativeAddCount = 0
            $script:nativeRemoveCount = 0
            try {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_NATIVE_SYNC", "1")
                Mock Get-Command { [pscustomobject]@{ Name = "claude"; Path = "claude" } } -ParameterFilter { $Name -eq "claude" }
                Mock Invoke-ExternalCommandWithTimeout {
                    if ($CommandArgs[0] -eq "mcp" -and $CommandArgs[1] -eq "add") {
                        $script:nativeAddCount++
                        if ($script:nativeAddCount -eq 1) {
                            return [pscustomobject]@{
                                timed_out = $false
                                exit_code = 1
                                output = @()
                                error = "MCP server postgres already exists in user config"
                            }
                        }
                    }
                    if ($CommandArgs[0] -eq "mcp" -and $CommandArgs[1] -eq "remove" -and $CommandArgs[2] -eq "postgres") {
                        $script:nativeRemoveCount++
                    }
                    return [pscustomobject]@{
                        timed_out = $false
                        exit_code = 0
                        output = @()
                        error = ""
                    }
                } -ParameterFilter { $command -eq "claude" }

                Invoke-NativeMcpSync @([pscustomobject]@{ name = "postgres"; transport = "stdio"; command = "pwsh"; args = @("-NoProfile") })

                $script:nativeAddCount | Should -Be 2
                $script:nativeRemoveCount | Should -Be 1
            }
            finally {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_NATIVE_SYNC", $old)
                Remove-Variable -Name nativeAddCount -Scope Script -ErrorAction SilentlyContinue
                Remove-Variable -Name nativeRemoveCount -Scope Script -ErrorAction SilentlyContinue
            }
        }

        It "Keeps claude timeout as verification failure" {
            Mock Get-Command { [pscustomobject]@{ Name = "claude" } } -ParameterFilter { $Name -eq "claude" }
            Mock Get-McpListVerifyTimeoutSeconds { 11 } -ParameterFilter { $cli -eq "claude" }
            Mock Invoke-ExternalCommandCapture {
                [pscustomobject]@{
                    command = "claude"
                    args = @("mcp", "list")
                    exit_code = 124
                    timed_out = $true
                    error = "timeout_after_11s"
                    output = @()
                }
            } -ParameterFilter { $command -eq "claude" }

            $result = Test-CliMcpServerReady "claude" @("context7")
            $result.ok | Should -Be $false
            $result.reason | Should -Be "timeout_after_11s"
            @($result.missing).Count | Should -Be 1
            $result.missing[0] | Should -Be "context7"
        }

    }

    Context "Get-McpServerNamesFromJsonText" {
        It "Extracts mcpServers property names from JSON payload" {
            $json = '{"mcpServers":{"context7":{"type":"stdio"},"github":{"type":"http"}}}'
            $names = Get-McpServerNamesFromJsonText $json
            @($names).Count | Should -Be 2
            ($names -contains "context7") | Should -Be $true
            ($names -contains "github") | Should -Be $true
        }
    }

    Context "Get-CodexMcpServerNamesFromTomlText" {
        It "Extracts codex mcp server section names from toml" {
            $toml = @'
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp"]

[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"

[mcp_servers.github.env]
TOKEN = "redacted"
'@
            $names = Get-CodexMcpServerNamesFromTomlText $toml
            @($names).Count | Should -Be 2
            ($names -contains "context7") | Should -Be $true
            ($names -contains "github") | Should -Be $true
        }
    }

    Context "Get-McpExpectedServersByCli" {
        It "Reads projected MCP config files without legacy Get-Content -Raw" {
            $root = Join-Path $TestDrive "mcp-expected"
            $claudeRoot = Join-Path $root ".claude"
            $codexRoot = Join-Path $root ".codex"
            New-Item -ItemType Directory -Path $claudeRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $codexRoot -Force | Out-Null
            Set-ContentUtf8 (Join-Path $claudeRoot ".mcp.json") '{"mcpServers":{"context7":{"transport":"stdio"}}}'
            Set-ContentUtf8 (Join-Path $codexRoot "config.toml") @'
[mcp_servers.context7]
command = "npx"
'@

            Mock Get-Content { throw "legacy raw read should not be used for projected mcp config reads" }

            $expected = Get-McpExpectedServersByCli @($claudeRoot, $codexRoot)

            ($expected.claude -contains "context7") | Should -Be $true
            ($expected.codex -contains "context7") | Should -Be $true
        }
    }

    Context "Has-McpServerByName" {
        It "Returns true when target MCP name exists in server list" {
            $servers = @(
                [pscustomobject]@{ name = "context7"; transport = "stdio" },
                [pscustomobject]@{ name = "github"; transport = "http" }
            )
            (Has-McpServerByName $servers "github") | Should -Be $true
        }

        It "Returns false when target MCP name does not exist in server list" {
            $servers = @(
                [pscustomobject]@{ name = "context7"; transport = "stdio" }
            )
            (Has-McpServerByName $servers "github") | Should -Be $false
        }
    }

    Context "Resolve-McpTargetRootsFromCfg" {
        It "Detects unique MCP root dirs from target skill paths" {
            $cfg = [pscustomobject]@{
                targets     = @(
                    [pscustomobject]@{ path = "~/.claude/skills" },
                    [pscustomobject]@{ path = "~/.codex/skills" },
                    [pscustomobject]@{ path = "~/.gemini/skills" },
                    [pscustomobject]@{ path = "~/.gemini/antigravity/skills" }
                )
                mcp_targets = @()
            }
            $roots = Resolve-McpTargetRootsFromCfg $cfg
            $roots.Count | Should -Be 3
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude")) | Should -Be $true
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex")) | Should -Be $true
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".gemini")) | Should -Be $true
        }

        It "Returns stable array shape for single resolved root" {
            $cfg = [pscustomobject]@{
                targets     = @(
                    [pscustomobject]@{ path = "~/.claude/skills" }
                )
                mcp_targets = @()
            }
            $roots = Resolve-McpTargetRootsFromCfg $cfg
            $roots.Count | Should -Be 1
            $roots[0] | Should -Be (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude")
        }

        It "Ignores lookalike dot-directories when resolving roots" {
            $cfg = [pscustomobject]@{
                targets     = @(
                    [pscustomobject]@{ path = "~/.gemini_backup/skills" },
                    [pscustomobject]@{ path = "~/.codex-temp/skills" },
                    [pscustomobject]@{ path = "~/.claude2/skills" }
                )
                mcp_targets = @()
            }
            $roots = Resolve-McpTargetRootsFromCfg $cfg
            @($roots).Count | Should -Be 3
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".gemini")) | Should -Be $false
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex")) | Should -Be $false
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude")) | Should -Be $false
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".gemini_backup")) | Should -Be $true
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex-temp")) | Should -Be $true
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude2")) | Should -Be $true
        }

        It "Finds valid dot-directory root in mcp_targets even after lookalike prefix" {
            $cfg = [pscustomobject]@{
                targets     = @()
                mcp_targets = @(
                    "~/.gemini_backup/foo/.gemini/mcp.json"
                )
            }
            $roots = Resolve-McpTargetRootsFromCfg $cfg
            $roots.Count | Should -Be 1
            $roots[0] | Should -Match "\\.gemini$"
            $roots[0] | Should -Not -Match "mcp\\.json$"
        }

        It "Chooses the earliest valid dot-directory root in a mixed path" {
            $cfg = [pscustomobject]@{
                targets     = @()
                mcp_targets = @(
                    "~/.trae/workspace/.claude/skills"
                )
            }
            $roots = Resolve-McpTargetRootsFromCfg $cfg
            $roots.Count | Should -Be 1
            $roots[0] | Should -Be (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".trae")
        }
    }

    Context "Migrate-ManualToVendor" {
        It "Removes legacy manual dir and migrates import to vendor mode" {
            $oldVendorDir = $VendorDir
            $oldManualDir = $ManualDir
            $oldImportDir = $ImportDir
            try {
                $VendorDir = Join-Path $TestDrive "vendor"
                $ManualDir = Join-Path $TestDrive "manual"
                $ImportDir = Join-Path $TestDrive "imports"
                New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ManualDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null

                $vendorSkillDir = Join-Path $VendorDir "myvendor\\skills\\demo"
                New-Item -ItemType Directory -Path $vendorSkillDir -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $vendorSkillDir "SKILL.md") -Force | Out-Null

                $manualLegacyDir = Join-Path $ManualDir "demo-manual"
                New-Item -ItemType Directory -Path $manualLegacyDir -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $manualLegacyDir "SKILL.md") -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors  = @(
                        [pscustomobject]@{ name = "myvendor"; repo = "https://example.com/repo.git"; ref = "main" }
                    )
                    imports  = @(
                        [pscustomobject]@{
                            name   = "demo-manual"
                            repo   = "https://example.com/repo.git"
                            ref    = "main"
                            skill  = "skills\\demo"
                            mode   = "manual"
                            sparse = $false
                        }
                    )
                    mappings = @(
                        [pscustomobject]@{ vendor = "manual"; from = "demo-manual"; to = "demo-manual" }
                        [pscustomobject]@{ vendor = "manual"; from = "skills\\demo"; to = "demo-legacy-skill-path" }
                        [pscustomobject]@{ vendor = "manual"; from = "keep-me"; to = "keep-me" }
                    )
                }

                $migrated = Migrate-ManualToVendor $cfg "myvendor" "https://example.com/repo.git"
                $migrated | Should -Be 1
                (Test-Path $manualLegacyDir) | Should -Be $false
                @($cfg.imports | Where-Object { $_.name -eq "demo-manual" }).Count | Should -Be 0
                @($cfg.imports | Where-Object { $_.name -eq "myvendor" -and $_.mode -eq "vendor" }).Count | Should -Be 1
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "demo-manual" }).Count | Should -Be 0
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "skills\\demo" }).Count | Should -Be 0
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "keep-me" }).Count | Should -Be 1
            }
            finally {
                $VendorDir = $oldVendorDir
                $ManualDir = $oldManualDir
                $ImportDir = $oldImportDir
            }
        }

        It "Counts migration even when legacy manual dir does not exist" {
            $oldVendorDir = $VendorDir
            $oldManualDir = $ManualDir
            $oldImportDir = $ImportDir
            try {
                $VendorDir = Join-Path $TestDrive "vendor2"
                $ManualDir = Join-Path $TestDrive "manual2"
                $ImportDir = Join-Path $TestDrive "imports2"
                New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ManualDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null

                $vendorSkillDir = Join-Path $VendorDir "myvendor\\skills\\demo"
                New-Item -ItemType Directory -Path $vendorSkillDir -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $vendorSkillDir "SKILL.md") -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors  = @(
                        [pscustomobject]@{ name = "myvendor"; repo = "https://example.com/repo.git"; ref = "main" }
                    )
                    imports  = @(
                        [pscustomobject]@{
                            name   = "demo-manual"
                            repo   = "https://example.com/repo.git"
                            ref    = "main"
                            skill  = "skills\\demo"
                            mode   = "manual"
                            sparse = $false
                        }
                    )
                    mappings = @(
                        [pscustomobject]@{ vendor = "manual"; from = "demo-manual"; to = "demo-manual" }
                    )
                }

                $migrated = Migrate-ManualToVendor $cfg "myvendor" "https://example.com/repo.git"
                $migrated | Should -Be 1
                @($cfg.imports | Where-Object { $_.name -eq "demo-manual" }).Count | Should -Be 0
                @($cfg.imports | Where-Object { $_.name -eq "myvendor" -and $_.mode -eq "vendor" }).Count | Should -Be 1
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "demo-manual" }).Count | Should -Be 0
            }
            finally {
                $VendorDir = $oldVendorDir
                $ManualDir = $oldManualDir
                $ImportDir = $oldImportDir
            }
        }
    }

    Context "Convert-InstalledVendorSkillsToManual" {
        It "Converts installed vendor mappings to manual imports while preserving target names" {
            $oldVendorDir = $VendorDir
            $oldImportDir = $ImportDir
            try {
                $VendorDir = Join-Path $TestDrive "vendor-convert"
                $ImportDir = Join-Path $TestDrive "imports-convert"
                New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null

                $skillSrc = Join-Path $VendorDir "demo-vendor\\skills\\content-strategy"
                New-Item -ItemType Directory -Path $skillSrc -Force | Out-Null
                Set-Content -Path (Join-Path $skillSrc "SKILL.md") -Value "---`nname: content-strategy`ndescription: x`n---"

                $cfg = [pscustomobject]@{
                    vendors = @(
                        [pscustomobject]@{ name = "demo-vendor"; repo = "https://example.com/demo.git"; ref = "main" }
                    )
                    imports = @(
                        [pscustomobject]@{ name = "demo-vendor"; repo = "https://example.com/demo.git"; ref = "main"; skill = "skills\\content-strategy"; mode = "vendor"; sparse = $false }
                    )
                    mappings = @(
                        [pscustomobject]@{ vendor = "demo-vendor"; from = "skills\\content-strategy"; to = "demo-vendor-skills-content-strategy" }
                    )
                }
                $vendorItem = [pscustomobject]@{ name = "demo-vendor"; repo = "https://example.com/demo.git"; ref = "main" }

                $result = Convert-InstalledVendorSkillsToManual $cfg $vendorItem

                $result.converted | Should -Be 1
                @($result.created_paths).Count | Should -Be 1
                @($cfg.mappings | Where-Object { $_.vendor -eq "demo-vendor" }).Count | Should -Be 0
                @($cfg.imports | Where-Object { $_.mode -eq "manual" }).Count | Should -Be 1
                $manualImport = @($cfg.imports | Where-Object { $_.mode -eq "manual" })[0]
                $manualImport.skill | Should -Be "."
                $manualName = [string]$manualImport.name
                (Test-Path (Join-Path $ImportDir ($manualName + "\\SKILL.md"))) | Should -Be $true
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq $manualName -and $_.to -eq "demo-vendor-skills-content-strategy" }).Count | Should -Be 1
            }
            finally {
                $VendorDir = $oldVendorDir
                $ImportDir = $oldImportDir
            }
        }
    }

    Context "Invoke-Doctor" {
        It "Shows non-empty Git version in DryRun" {
            $oldDryRun = $DryRun
            try {
                $DryRun = $true

                Mock Write-Host {}
                Mock Get-CimInstance { [pscustomobject]@{ Caption = "Windows"; OSArchitecture = "64-bit" } }
                Mock Get-ItemProperty { [pscustomobject]@{ LongPathsEnabled = 1 } }
                Mock Test-DoctorTcpConnect { $true }
                # Pin the scheduled-task branch hermetically: machines that
                # really have the weekly task take the classification path,
                # while clean runners (CI) throw and hit the catch branch's
                # Test-Path -LiteralPath runner check. Mock both shapes.
                Mock Get-ScheduledTask { throw 'no such task' }
                Mock Test-Path { $false } -ParameterFilter { $Path -eq $CfgPath }
                Mock Test-Path { $true }

                Invoke-Doctor

                Should -Invoke Write-Host -Exactly -Times 1 -ParameterFilter {
                    $Object -like "✅ Git:*" -and $Object.Trim() -ne "✅ Git:"
                }
            }
            finally {
                $DryRun = $oldDryRun
            }
        }
    }

    Context "Lockfile Strict Mode" {
        It "Throws when lock file is missing in locked mode" {
            $oldRoot = $Root
            $oldCfgPath = $CfgPath
            $oldVendorDir = $VendorDir
            $oldImportDir = $ImportDir
            try {
                $Root = Join-Path $TestDrive "ws-lock-missing"
                $CfgPath = Join-Path $Root "skills.json"
                $VendorDir = Join-Path $Root "vendor"
                $ImportDir = Join-Path $Root "imports"
                New-Item -ItemType Directory -Path $Root -Force | Out-Null
                New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors      = @()
                    targets      = @()
                    mappings     = @()
                    imports      = @()
                    mcp_servers  = @()
                    mcp_targets  = @()
                    update_force = $false
                    sync_mode    = "sync"
                }

                $thrown = $false
                try { Ensure-LockedState $cfg | Out-Null } catch { $thrown = $true }
                $thrown | Should -Be $true
            }
            finally {
                $Root = $oldRoot
                $CfgPath = $oldCfgPath
                $VendorDir = $oldVendorDir
                $ImportDir = $oldImportDir
            }
        }

        It "Throws when lock vendors do not match current cfg" {
            $cfg = [pscustomobject]@{
                vendors = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git"; ref = "main" })
                imports = @()
            }
            $lock = [pscustomobject]@{
                version = 1
                vendors = @([pscustomobject]@{ name = "other"; repo = "https://example.com/other.git"; ref = "main"; commit = "abc" })
                imports = @()
            }
            $thrown = $false
            try { Assert-LockMatchesCfg $cfg $lock } catch { $thrown = $true }
            $thrown | Should -Be $true
        }

        It "Accepts matching lock data independent of hashtable JSON order" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "z"; repo = "https://example.com/z.git"; ref = "main" },
                    [pscustomobject]@{ name = "a"; repo = "https://example.com/a.git"; ref = "dev" }
                )
                imports = @(
                    [pscustomobject]@{ name = "manual-z"; mode = "manual"; repo = "https://example.com/z.git"; ref = "main"; skill = "skills/z"; sparse = $false },
                    [pscustomobject]@{ name = "manual-a"; mode = "manual"; repo = "https://example.com/a.git"; ref = "dev"; skill = "skills/a"; sparse = $true }
                )
            }
            $lock = [pscustomobject]@{
                version = 1
                vendors = @(
                    [pscustomobject]@{ name = "a"; repo = "https://example.com/a.git"; ref = "dev"; commit = "1" },
                    [pscustomobject]@{ name = "z"; repo = "https://example.com/z.git"; ref = "main"; commit = "2" }
                )
                imports = @(
                    [pscustomobject]@{ name = "manual-a"; mode = "manual"; repo = "https://example.com/a.git"; ref = "dev"; skill = "skills\a"; sparse = $true; commit = "1" },
                    [pscustomobject]@{ name = "manual-z"; mode = "manual"; repo = "https://example.com/z.git"; ref = "main"; skill = "skills\z"; sparse = $false; commit = "2" }
                )
            }

            Assert-LockMatchesCfg $cfg $lock
        }

        It "Throws when lock commit differs from workspace commit" {
            $oldVendorDir = $VendorDir
            try {
                $VendorDir = Join-Path $TestDrive "vendor-lock-commit"
                New-Item -ItemType Directory -Path (Join-Path $VendorDir "demo") -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git"; ref = "main" })
                    imports = @()
                }
                $lock = [pscustomobject]@{
                    version = 1
                    vendors = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git"; ref = "main"; commit = "lock-commit" })
                    imports = @()
                }

                Mock Get-RepoHeadCommit { "actual-commit" }
                $thrown = $false
                try { Assert-LockMatchesWorkspace $cfg $lock } catch { $thrown = $true }
                $thrown | Should -Be $true
            }
            finally {
                $VendorDir = $oldVendorDir
            }
        }

        It "Writes lock file with current vendors and imports" {
            $oldRoot = $Root
            $oldCfgPath = $CfgPath
            $oldVendorDir = $VendorDir
            $oldImportDir = $ImportDir
            try {
                $Root = Join-Path $TestDrive "ws-lock-write"
                $CfgPath = Join-Path $Root "skills.json"
                $VendorDir = Join-Path $Root "vendor"
                $ImportDir = Join-Path $Root "imports"
                New-Item -ItemType Directory -Path (Join-Path $VendorDir "demo") -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $ImportDir "manual-demo") -Force | Out-Null

                $cfg = [pscustomobject]@{
                    vendors      = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git"; ref = "main" })
                    targets      = @()
                    mappings     = @()
                    imports      = @([pscustomobject]@{ name = "manual-demo"; mode = "manual"; repo = "https://example.com/demo.git"; ref = "main"; skill = "skills\\demo"; sparse = $false })
                    mcp_servers  = @()
                    mcp_targets  = @()
                    update_force = $false
                    sync_mode    = "sync"
                }

                Mock Get-RepoHeadCommit { "abc123" }
                $lock = Save-LockData $cfg
                (Test-Path (Get-LockPath)) | Should -Be $true
                @($lock.vendors).Count | Should -Be 1
                @($lock.imports).Count | Should -Be 1
                $lock.vendors[0].commit | Should -Be "abc123"
            }
            finally {
                $Root = $oldRoot
                $CfgPath = $oldCfgPath
                $VendorDir = $oldVendorDir
                $ImportDir = $oldImportDir
            }
        }

        It "Reads a shared vendor repository HEAD once per lock snapshot" {
            $oldVendorDir = $VendorDir
            try {
                $VendorDir = Join-Path $TestDrive "vendor-lock-head-cache"
                New-Item -ItemType Directory -Path (Join-Path $VendorDir "demo") -Force | Out-Null
                $cfg = [pscustomobject]@{
                    vendors = @([pscustomobject]@{ name = "demo"; repo = "https://example.com/demo.git"; ref = "main" })
                    imports = @(
                        [pscustomobject]@{ name = "demo"; mode = "vendor"; repo = "https://example.com/demo.git"; ref = "main"; skill = "skills/a"; sparse = $true },
                        [pscustomobject]@{ name = "demo"; mode = "vendor"; repo = "https://example.com/demo.git"; ref = "main"; skill = "skills/b"; sparse = $true }
                    )
                }
                Mock Invoke-GitCapture { "abc123" } -ParameterFilter { $GitArgs[0] -eq "rev-parse" -and $GitArgs[1] -eq "HEAD" }

                $lock = New-LockData $cfg
                Assert-LockMatchesWorkspace $cfg ([pscustomobject]$lock)

                Should -Invoke Invoke-GitCapture -Times 2 -Exactly -ParameterFilter { $GitArgs[0] -eq "rev-parse" -and $GitArgs[1] -eq "HEAD" }
            }
            finally {
                $VendorDir = $oldVendorDir
            }
        }

        It "Writes lock metadata for local zip imports" {
            $oldRoot = $Root
            $oldCfgPath = $CfgPath
            $oldVendorDir = $VendorDir
            $oldImportDir = $ImportDir
            try {
                $Root = Join-Path $TestDrive "ws-lock-zip"
                $CfgPath = Join-Path $Root "skills.json"
                $VendorDir = Join-Path $Root "vendor"
                $ImportDir = Join-Path $Root "imports"
                New-Item -ItemType Directory -Path $Root -Force | Out-Null
                New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null
                $cache = Join-Path $ImportDir "manual-demo"
                New-Item -ItemType Directory -Path $cache -Force | Out-Null
                Set-Content -Path (Join-Path $cache "SKILL.md") -Value "---`nname: manual-demo`ndescription: x`n---"
                $zip = Join-Path $TestDrive "manual-demo.zip"
                Set-Content -Path $zip -Value "zip-lock-data"

                $cfg = [pscustomobject]@{
                    vendors      = @()
                    targets      = @()
                    mappings     = @()
                    imports      = @([pscustomobject]@{ name = "manual-demo"; mode = "manual"; repo = $zip; ref = "main"; skill = "."; sparse = $false })
                    mcp_servers  = @()
                    mcp_targets  = @()
                    update_force = $false
                    sync_mode    = "sync"
                }

                $lock = Save-LockData $cfg
                [string]$lock.imports[0].source_kind | Should -Be "local_zip"
                [string]$lock.imports[0].source_hash | Should -Not -BeNullOrEmpty
                [string]$lock.imports[0].workspace_fingerprint_algorithm | Should -Be "sha256-tree-v2"
                [string]$lock.imports[0].workspace_fingerprint | Should -Not -BeNullOrEmpty
                ($lock.imports[0].PSObject.Properties.Match("commit").Count -gt 0) | Should -Be $false
            }
            finally {
                $Root = $oldRoot
                $CfgPath = $oldCfgPath
                $VendorDir = $oldVendorDir
                $ImportDir = $oldImportDir
            }
        }

        It "Fingerprints local zip workspaces by content including hidden files" {
            $cache = Join-Path $TestDrive "fingerprint-content"
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            $regular = Join-Path $cache "regular.txt"
            Set-Content -LiteralPath $regular -Value "aaaa" -NoNewline
            $originalTimestamp = (Get-Item -LiteralPath $regular).LastWriteTimeUtc
            $before = Get-DirectoryFingerprint $cache

            Set-Content -LiteralPath $regular -Value "bbbb" -NoNewline
            (Get-Item -LiteralPath $regular).LastWriteTimeUtc = $originalTimestamp
            $afterSameMetadata = Get-DirectoryFingerprint $cache
            $afterSameMetadata | Should -Not -Be $before

            $hidden = Join-Path $cache "hidden.txt"
            Set-Content -LiteralPath $hidden -Value "hidden-a" -NoNewline
            [System.IO.File]::SetAttributes($hidden, [System.IO.FileAttributes]::Hidden)
            $withHidden = Get-DirectoryFingerprint $cache
            Set-Content -LiteralPath $hidden -Value "hidden-b" -NoNewline
            (Get-DirectoryFingerprint $cache) | Should -Not -Be $withHidden
        }

        It "Rejects reparse entries instead of fingerprinting content outside the workspace" {
            if ($env:OS -ne "Windows_NT") { return }
            $cache = Join-Path $TestDrive "fingerprint-reparse"
            $outside = Join-Path $TestDrive "fingerprint-outside"
            $link = Join-Path $cache "linked"
            New-Item -ItemType Directory -Path $cache, $outside -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $outside "secret.txt") -Value "outside"
            & cmd /c mklink /J "$link" "$outside" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "test mklink failed" }

            { Get-DirectoryFingerprint $cache } | Should -Throw '*reparse*'
        }

        It "Reads legacy local zip fingerprints and rejects unknown algorithms" {
            $cache = Join-Path $TestDrive "fingerprint-legacy"
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cache "SKILL.md") -Value "legacy"
            $legacyEntry = [pscustomobject]@{
                workspace_fingerprint = Get-LegacyDirectoryMetadataFingerprint $cache
            }
            { Assert-ImportLockWorkspaceFingerprint $legacyEntry $cache "manual/legacy" } | Should -Not -Throw

            $unknownEntry = [pscustomobject]@{
                workspace_fingerprint_algorithm = "unknown-v9"
                workspace_fingerprint = "unused"
            }
            { Assert-ImportLockWorkspaceFingerprint $unknownEntry $cache "manual/unknown" } | Should -Throw '*未知*'
        }

        It "Detects local zip source drift in locked workspace" {
            $oldImportDir = $ImportDir
            try {
                $ImportDir = Join-Path $TestDrive "imports-lock-zip-drift"
                $cache = Join-Path $ImportDir "manual-demo"
                New-Item -ItemType Directory -Path $cache -Force | Out-Null
                Set-Content -Path (Join-Path $cache "SKILL.md") -Value "---`nname: manual-demo`ndescription: x`n---"
                $zip = Join-Path $TestDrive "manual-demo-drift.zip"
                Set-Content -Path $zip -Value "zip-lock-data-v1"

                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @([pscustomobject]@{ name = "manual-demo"; mode = "manual"; repo = $zip; ref = "main"; skill = "."; sparse = $false })
                }
                $lock = [pscustomobject]@{
                    version = 1
                    vendors = @()
                    imports = @([pscustomobject]@{
                            name = "manual-demo"
                            mode = "manual"
                            repo = $zip
                            ref = "main"
                            skill = "."
                            sparse = $false
                            source_kind = "local_zip"
                            source_hash = Get-FileContentHash $zip
                            workspace_fingerprint_algorithm = "sha256-tree-v2"
                            workspace_fingerprint = Get-DirectoryFingerprint $cache
                        })
                }

                Set-Content -Path $zip -Value "zip-lock-data-v2"
                $thrown = $false
                try {
                    Assert-LockMatchesWorkspace $cfg $lock
                }
                catch {
                    $thrown = $true
                    $_.Exception.Message | Should -Match "源文件不匹配"
                }
                $thrown | Should -Be $true
            }
            finally {
                $ImportDir = $oldImportDir
            }
        }

        It "Replays local zip imports end-to-end from rooted archives" {
            $oldRoot = $Root
            $oldCfgPath = $CfgPath
            $oldVendorDir = $VendorDir
            $oldImportDir = $ImportDir
            try {
                $workspaceRoot = Join-Path $TestDrive "ws-lock-zip-e2e"
                $Root = $workspaceRoot
                $CfgPath = Join-Path $workspaceRoot "skills.json"
                $VendorDir = Join-Path $workspaceRoot "vendor"
                $ImportDir = Join-Path $workspaceRoot "imports"
                New-Item -ItemType Directory -Path $workspaceRoot -Force | Out-Null
                New-Item -ItemType Directory -Path $VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $ImportDir -Force | Out-Null

                $srcParent = Join-Path $TestDrive "zip-rooted"
                $src = Join-Path $srcParent "manual-demo-src"
                New-Item -ItemType Directory -Path $src -Force | Out-Null
                Set-Content -Path (Join-Path $src "SKILL.md") -Value "---`nname: manual-demo`ndescription: rooted zip`n---"
                Set-Content -Path (Join-Path $src "note.txt") -Value "rooted archive fixture"
                $zip = Join-Path $TestDrive "manual-demo-rooted.zip"
                Compress-Archive -Path $src -DestinationPath $zip -Force

                $cfg = [pscustomobject]@{
                    vendors      = @()
                    targets      = @()
                    mappings     = @()
                    imports      = @([pscustomobject]@{ name = "manual-demo"; mode = "manual"; repo = $zip; ref = "main"; skill = "."; sparse = $false })
                    mcp_servers  = @()
                    mcp_targets  = @()
                    update_force = $false
                    sync_mode    = "sync"
                }

                $cache = Join-Path $ImportDir "manual-demo"
                Ensure-Repo $cache $zip "main" $null $true $false $false
                $expectedFingerprint = Get-DirectoryFingerprint $cache
                $expectedSkill = Get-Content -Raw (Join-Path $cache "SKILL.md")
                $lock = Save-LockData $cfg
                Remove-Item -LiteralPath $cache -Recurse -Force

                Mock Clear-SkillsCache {}

                Apply-LockToWorkspace $cfg $lock

                (Test-Path (Join-Path $cache "SKILL.md")) | Should -Be $true
                (Get-DirectoryFingerprint $cache) | Should -Be $expectedFingerprint
                (Get-Content -Raw (Join-Path $cache "SKILL.md")) | Should -Be $expectedSkill
                { Assert-LockMatchesWorkspace $cfg $lock } | Should -Not -Throw
                Should -Invoke Clear-SkillsCache -Times 1 -Exactly
            }
            finally {
                $Root = $oldRoot
                $CfgPath = $oldCfgPath
                $VendorDir = $oldVendorDir
                $ImportDir = $oldImportDir
            }
        }

        It "Replays local zip imports without git checkout" {
            $oldImportDir = $ImportDir
            try {
                $ImportDir = Join-Path $TestDrive "imports-lock-zip-apply"
                $cache = Join-Path $ImportDir "manual-demo"
                New-Item -ItemType Directory -Path $cache -Force | Out-Null
                Set-Content -Path (Join-Path $cache "SKILL.md") -Value "---`nname: manual-demo`ndescription: x`n---"
                $zip = Join-Path $TestDrive "manual-demo-apply.zip"
                Set-Content -Path $zip -Value "zip-lock-apply"

                $cfg = [pscustomobject]@{
                    vendors = @()
                    imports = @([pscustomobject]@{ name = "manual-demo"; mode = "manual"; repo = $zip; ref = "main"; skill = "."; sparse = $false })
                    update_force = $false
                }
                $lock = [pscustomobject]@{
                    version = 1
                    vendors = @()
                    imports = @([pscustomobject]@{
                            name = "manual-demo"
                            mode = "manual"
                            repo = $zip
                            ref = "main"
                            skill = "."
                            sparse = $false
                            source_kind = "local_zip"
                            source_hash = Get-FileContentHash $zip
                            workspace_fingerprint_algorithm = "sha256-tree-v2"
                            workspace_fingerprint = Get-DirectoryFingerprint $cache
                        })
                }

                $script:zipLockEnsureArgs = $null
                Mock Ensure-Repo {
                    param($path, $repo, $ref, $sparsePath, $forceClean, $confirmClean, $doFetch)
                    $script:zipLockEnsureArgs = [pscustomobject]@{
                        path = $path
                        repo = $repo
                        ref = $ref
                        sparsePath = $sparsePath
                        forceClean = $forceClean
                        confirmClean = $confirmClean
                        doFetch = $doFetch
                    }
                }
                Mock Invoke-Git { throw "Invoke-Git should not be called for local zip lock replay." }
                Mock Clear-SkillsCache {}

                Apply-LockToWorkspace $cfg $lock

                $script:zipLockEnsureArgs | Should -Not -BeNullOrEmpty
                $script:zipLockEnsureArgs.forceClean | Should -Be $true
                Should -Invoke Ensure-Repo -Times 1 -Exactly
                Should -Invoke Invoke-Git -Times 0 -Exactly
                Should -Invoke Clear-SkillsCache
            }
            finally {
                $ImportDir = $oldImportDir
            }
        }
    }
}

Describe "Reference shelf governance" {
    BeforeAll {
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$manifestPath = Join-Path $repoRoot "references\reference-shelf.manifest.json"
$refreshScript = Join-Path $repoRoot "scripts\refresh-reference-repos.ps1"
$governanceScript = Join-Path $repoRoot "scripts\verify-reference-governance.ps1"
}

    It "Limits reference portfolio mutations to the project-owned external root" {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.references_root | Should -Be "D:\CODE\external\skills-manager-references"
    }

    It "Enforces reference portfolio tier and status lifecycle pairs" {
        . $governanceScript

        Test-ReferenceLifecycleState "core-mainline" "active" | Should -Be $true
        Test-ReferenceLifecycleState "secondary" "active" | Should -Be $true
        Test-ReferenceLifecycleState "conditional" "active" | Should -Be $true
        Test-ReferenceLifecycleState "core-mainline" "deprecated" | Should -Be $false
        Test-ReferenceLifecycleState "secondary" "not-cloned" | Should -Be $false
    }

    It 'requires a named consumer and retirement trigger for conditional references' {
        . $governanceScript

        Test-ConditionalReferenceContract ([pscustomobject]@{ tier='conditional'; consumer='watch-runtime'; retirement_trigger='remove when unused' }) | Should -BeTrue
        Test-ConditionalReferenceContract ([pscustomobject]@{ tier='conditional'; consumer=''; retirement_trigger='remove when unused' }) | Should -BeFalse
        Test-ConditionalReferenceContract ([pscustomobject]@{ tier='conditional'; consumer='watch-runtime'; retirement_trigger='' }) | Should -BeFalse
        Test-ConditionalReferenceContract ([pscustomobject]@{ tier='secondary' }) | Should -BeTrue
    }

    It "Rejects rooted and traversal reference paths before normalization" {
        . $governanceScript

        Test-ContainedReferenceRelativePath "/absolute/path" | Should -Be $false
        Test-ContainedReferenceRelativePath "C:\absolute\path" | Should -Be $false
        Test-ContainedReferenceRelativePath "nested/../../escape" | Should -Be $false
        Test-ContainedReferenceRelativePath "safe/./repo" | Should -Be $false
        Test-ContainedReferenceRelativePath "safe/repo" | Should -Be $true
    }

    It "Fails closed on manifest path traversal before reference refresh operations" {
        $fixtureManifest = Join-Path $TestDrive "traversal-reference-manifest.json"
        $fixture = [ordered]@{
            schema_version = 1
            references_root = (Join-Path $TestDrive "reference-root")
            default_refresh_set = @("escape")
            repos = @([ordered]@{
                    name = "escape"
                    tier = "core-mainline"
                    status = "active"
                    upstream_url = "https://example.invalid/escape.git"
                    relative_path = "nested/../../escape"
                })
        }
        [System.IO.File]::WriteAllText($fixtureManifest, ($fixture | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

        { & $refreshScript -ManifestPath $fixtureManifest -ReferencesRoot $fixture.references_root -RepoNames escape -FetchOnly } | Should -Throw
        Test-Path -LiteralPath (Join-Path $TestDrive "escape") | Should -Be $false
    }

    It "Tracks the current official OpenAI plugin source and retires the deprecated skills repository" {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $plugins = @($manifest.repos | Where-Object name -eq "openai-plugins")
        $skills = @($manifest.repos | Where-Object name -eq "openai-skills")

        $plugins.Count | Should -Be 1
        $plugins[0].tier | Should -Be "core-mainline"
        $plugins[0].status | Should -Be "active"
        $plugins[0].source_disposition | Should -Be "current-official"
        $plugins[0].upstream_url | Should -Be "https://github.com/openai/plugins.git"
        $plugins[0].relative_path | Should -Be "core/openai-plugins"

        $skills.Count | Should -Be 0
        @($manifest.default_refresh_set) -contains "openai-plugins" | Should -Be $true
        @($manifest.default_refresh_set) -contains "openai-skills" | Should -Be $false
    }

    It 'retains conditional references only for a named current consumer' {
        . $governanceScript
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $conditional = @($manifest.repos | Where-Object tier -eq 'conditional')
        foreach ($entry in $conditional) {
            (Test-ConditionalReferenceContract $entry) | Should -BeTrue
        }

        $hermes = @($conditional | Where-Object name -eq 'hermes-agent')
        $hermes.Count | Should -Be 1
        $hermes[0].consumer | Should -Match 'HSM POC'
        $hermes[0].license | Should -Be 'MIT'
        $hermes[0].reviewed_revision | Should -Match '^[0-9a-f]{40}$'
        @($manifest.default_refresh_set) | Should -Not -Contain 'hermes-agent'
    }

    It "Selects a governed conditional reference only when explicitly requested" {
        $referencesRoot = Join-Path $TestDrive "conditional-reference-shelf"
        $outputDirectory = Join-Path $TestDrive "conditional-updates"
        $conditionalManifest = Join-Path $TestDrive 'conditional-manifest.json'
        [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @()
            repos = @([ordered]@{
                    name = 'fixture-conditional'
                    tier = 'conditional'
                    status = 'active'
                    upstream_url = 'https://example.invalid/fixture.git'
                    relative_path = 'conditional/fixture/fixture-conditional'
                    branch = 'main'
                    policy = 'floating'
                    consumer = 'fixture-current-consumer'
                    retirement_trigger = 'remove when fixture consumer is retired'
                })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $conditionalManifest -Encoding UTF8

        $result = & $refreshScript -ManifestPath $conditionalManifest -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -Tier conditional -FetchOnly

        $result.repo_set | Should -Be "tier-conditional"
        @($result.repo_names) | Should -Be @('fixture-conditional')
        @($result.results | Where-Object status -ne "missing").Count | Should -Be 0
    }

    It "Routes the default set to plugins and writes a runtime receipt" {
        $referencesRoot = Join-Path $TestDrive "reference-shelf"
        $outputDirectory = Join-Path $TestDrive "updates"

        $defaultResult = & $refreshScript -ManifestPath $manifestPath -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -FetchOnly
        $defaultResult.repo_set | Should -Be "core-default"
        @($defaultResult.repo_names) -contains "openai-plugins" | Should -Be $true
        @($defaultResult.repo_names) -contains "openai-skills" | Should -Be $false

        $defaultResult.output_path | Should -Be (Join-Path $outputDirectory "receipt.md")
        Test-Path -LiteralPath $defaultResult.output_path | Should -Be $true
    }

    It "Distinguishes fetched remote refs from the consumable local checkout revision" {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "git not found, skipping reference refresh provenance test."
            return
        }
        $remote = Join-Path $TestDrive "reference-remote.git"
        $publisher = Join-Path $TestDrive "reference-publisher"
        $referencesRoot = Join-Path $TestDrive "reference-consumer"
        $consumer = Join-Path $referencesRoot "core\demo"
        $outputDirectory = Join-Path $TestDrive "reference-reports"
        $fixtureManifest = Join-Path $TestDrive "reference-manifest.json"
        & git init --bare -q $remote
        & git clone -q $remote $publisher
        & git -C $publisher config user.name fixture
        & git -C $publisher config user.email fixture@example.invalid
        Set-Content -LiteralPath (Join-Path $publisher "README.md") -Value "one" -Encoding UTF8
        & git -C $publisher add README.md
        & git -C $publisher commit -q -m one
        & git -C $publisher push -q origin HEAD
        New-Item -ItemType Directory -Path (Split-Path $consumer -Parent) -Force | Out-Null
        & git clone -q $remote $consumer
        $manifest = [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @("demo")
            repos = @([ordered]@{
                    name = "demo"
                    tier = "core-mainline"
                    status = "active"
                    upstream_url = $remote
                    relative_path = "core/demo"
                })
        }
        [System.IO.File]::WriteAllText($fixtureManifest, ($manifest | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

        $current = & $refreshScript -ManifestPath $fixtureManifest -OutputDirectory $outputDirectory -FetchOnly
        $current.results[0].remote_refs_current | Should -Be $true
        $current.results[0].working_tree_matches_upstream | Should -Be $true
        [string]$current.results[0].consumable_revision | Should -Match '^[0-9a-f]{40}$'
        $current.results[0].consumable_revision | Should -Be $current.results[0].upstream_revision

        Set-Content -LiteralPath (Join-Path $publisher "README.md") -Value "two" -Encoding UTF8
        & git -C $publisher add README.md
        & git -C $publisher commit -q -m two
        & git -C $publisher push -q origin HEAD
        $behind = & $refreshScript -ManifestPath $fixtureManifest -OutputDirectory $outputDirectory -FetchOnly
        $behind.results[0].remote_refs_current | Should -Be $true
        $behind.results[0].working_tree_matches_upstream | Should -Be $false
        $behind.results[0].consumable_revision | Should -Not -Be $behind.results[0].upstream_revision
        $report = Get-Content -LiteralPath $behind.output_path -Raw -Encoding UTF8
        $report | Should -Match 'remote refs current：`true`'
        $report | Should -Match 'working tree matches upstream：`false`'
        $report | Should -Match 'consumable revision：`[0-9a-f]{40}`'
    }
}

Describe "Audit regression gates" {
    Context "Normalize-RepoUrl shorthand forms" {
        It "Does not double-suffix a .git-terminated owner/repo shorthand" {
            Normalize-RepoUrl "owner/repo.git" | Should -Be "https://github.com/owner/repo.git"
            Normalize-RepoUrl "owner/repo" | Should -Be "https://github.com/owner/repo.git"
            Normalize-RepoUrl "owner/repo_name.git" | Should -Be "https://github.com/owner/repo_name.git"
            Normalize-RepoUrl "https://github.com/owner/repo.git" | Should -Be "https://github.com/owner/repo.git"
        }
    }

    Context "Has-GitChanges fail-closed" {
        It "Treats a failed git status as dirty instead of clean" {
            $oldDryRun = $DryRun
            try {
                $DryRun = $false
                Mock Invoke-GitCapture { $null }
                Has-GitChanges | Should -Be $true
                Mock Invoke-GitCapture { "" }
                Has-GitChanges | Should -Be $false
            }
            finally {
                $DryRun = $oldDryRun
            }
        }
    }

    Context "Normalize-Cfg null-element arrays" {
        It "Keeps arrays containing null elements instead of wiping them" {
            $cfg = [pscustomobject]@{
                mappings  = @([pscustomobject]@{ vendor = "demo"; from = "a"; to = "a" }, $null)
                imports   = @()
                sync_mode = "link"
            }
            $normalized = Normalize-Cfg $cfg
            @($normalized.mappings).Count | Should -Be 2
        }

        It "Fills genuinely null collections with empty arrays" {
            $cfg = [pscustomobject]@{ mappings = $null; imports = $null; sync_mode = $null }
            $normalized = Normalize-Cfg $cfg
            @($normalized.mappings).Count | Should -Be 0
            @($normalized.imports).Count | Should -Be 0
        }
    }
}

Describe "构建生效 rollback compensation" {
    It "Re-projects hosts to the rolled-back agent state after partial sync failure" {
        $oldDryRun = $DryRun
        $oldCfgPath = $CfgPath
        $oldRoot = $Root
        try {
            $DryRun = $false
            # 密封：构建生效会经 Optimize-Imports/SaveCfg 读写 $CfgPath，
            # 必须重定向到 TestDrive 并 mock 掉 SaveCfg，禁止触碰仓库真值。
            $Root = Join-Path $TestDrive "ws-build-compensation"
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
            $CfgPath = Join-Path $Root "skills.json"
            $cfg = [pscustomobject]@{
                vendors = @(); targets = @(); mappings = @(); imports = @()
                mcp_servers = @(); mcp_targets = @(); sync_mode = "link"; update_force = $true
            }
            Mock Preflight {}
            Mock LoadCfg { $cfg }
            Mock SaveCfg {}
            Mock Optimize-Imports {}
            Mock Write-BuildSummary {}
            Mock Start-BuildTransaction { [pscustomobject]@{ id = "txn" } }
            Mock 构建Agent { @() }
            Mock Get-HostProjectionPromotionContext { [pscustomobject]@{ required = $false; promotion_mode = "local_only" } } -ParameterFilter { -not $AllowUnverified }
            Mock Get-HostProjectionPromotionContext { [pscustomobject]@{ required = $true; promotion_mode = "unverified_override" } } -ParameterFilter { [bool]$AllowUnverified }
            Mock 应用到ClaudeCodex { @("target:x => simulated failure") } -ParameterFilter { -not $PromotionContext -or $PromotionContext.promotion_mode -ne "unverified_override" }
            Mock 应用到ClaudeCodex { @() } -ParameterFilter { $PromotionContext -and $PromotionContext.promotion_mode -eq "unverified_override" }
            Mock Rollback-BuildTransaction {}
            Mock Complete-BuildTransaction {}
            Mock Sync-SkillDiscoveryCatalog {}
            Mock Sync-NativeAgentBridge {}

            { 构建生效 } | Should -Throw '*构建生效失败*'

            Should -Invoke Rollback-BuildTransaction -Times 1 -Exactly
            Should -Invoke Complete-BuildTransaction -Times 0 -Exactly
            Should -Invoke Get-HostProjectionPromotionContext -Times 1 -Exactly -ParameterFilter { [bool]$AllowUnverified }
            Should -Invoke 应用到ClaudeCodex -Times 1 -Exactly -ParameterFilter { $PromotionContext -and $PromotionContext.promotion_mode -eq "unverified_override" }
        }
        finally {
            $DryRun = $oldDryRun
            $CfgPath = $oldCfgPath
            $Root = $oldRoot
        }
    }
}

Describe "Sparse checkout disable guard" {
    It "Fails closed when disable is required but fails" {
        Mock Invoke-GitCapture { "true" }
        Mock Invoke-Git { throw "git 失败：sparse-checkout disable" }
        { Set-GitSparseCheckout @() } | Should -Throw '*git 失败*'
        Should -Invoke Invoke-Git -Times 1 -Exactly -ParameterFilter { @($GitArgs) -contains "disable" }
    }

    It "Skips disable when sparse checkout was never enabled" {
        Mock Invoke-GitCapture { "" }
        Mock Invoke-Git {}
        Set-GitSparseCheckout @()
        Should -Invoke Invoke-Git -Times 0 -Exactly
    }

    It "Runs disable when sparse checkout is enabled" {
        Mock Invoke-GitCapture { "true" }
        Mock Invoke-Git {}
        Set-GitSparseCheckout @()
        Should -Invoke Invoke-Git -Times 1 -Exactly -ParameterFilter { @($GitArgs) -contains "disable" }
    }
}

Describe "Build transaction rollback backup preservation" {
    It "Restores agent and removes the transaction directory on success" {
        $oldAgentDir = $AgentDir
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $root = Join-Path $TestDrive "txn-ok"
            $txnPath = Join-Path $root "build-t1"
            $backupAgent = Join-Path $txnPath "agent.backup"
            New-Item -ItemType Directory -Path (Join-Path $backupAgent "skill") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $backupAgent "skill\SKILL.md") "backup"
            $AgentDir = Join-Path $root "agent"
            New-Item -ItemType Directory -Path (Join-Path $AgentDir "new") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir "new\SKILL.md") "new"
            $txn = [pscustomobject]@{ path = $txnPath; backup_agent = $backupAgent; has_backup_agent = $true; backup_error = $null }

            Rollback-BuildTransaction $txn | Should -Be $true
            Test-Path -LiteralPath (Join-Path $AgentDir "skill\SKILL.md") -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $txnPath | Should -BeFalse
        }
        finally {
            $AgentDir = $oldAgentDir
            $DryRun = $oldDryRun
        }
    }

    It "Keeps the transaction directory and backup when the restore fails" {
        $oldAgentDir = $AgentDir
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $root = Join-Path $TestDrive "txn-fail"
            $txnPath = Join-Path $root "build-t2"
            $backupAgent = Join-Path $txnPath "agent.backup"
            New-Item -ItemType Directory -Path (Join-Path $backupAgent "skill") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $backupAgent "skill\SKILL.md") "backup"
            $AgentDir = Join-Path $root "agent"
            New-Item -ItemType Directory -Path (Join-Path $AgentDir "new") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir "new\SKILL.md") "new"
            $txn = [pscustomobject]@{ path = $txnPath; backup_agent = $backupAgent; has_backup_agent = $true; backup_error = $null }
            Mock Invoke-MoveItem { throw "file in use" }

            Rollback-BuildTransaction $txn | Should -Be $false
            Test-Path -LiteralPath $txnPath -PathType Container | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $backupAgent "skill\SKILL.md") -PathType Leaf | Should -BeTrue
        }
        finally {
            $AgentDir = $oldAgentDir
            $DryRun = $oldDryRun
        }
    }
}
