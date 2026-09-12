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

        It "Does not treat case-only command changes as equivalent" {
            $a = [pscustomobject]@{
                name      = "casey"
                transport = "stdio"
                command   = "npx"
                args      = @("-y", "@upstash/context7-mcp")
            }
            $b = [pscustomobject]@{
                name      = "casey"
                transport = "stdio"
                command   = "NPX"
                args      = @("-y", "@upstash/context7-mcp")
            }

            # 仅大小写差异必须移动指纹，否则同步会误判 unchanged 跳过重写。
            (Test-McpServerEquivalent $a $b) | Should -Be $false
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

        It "Returns an empty array instead of null when no filter and no args" {
            $tokens = Merge-FilterAndArgs "" @()
            ($null -eq $tokens) | Should -Be $false
            @($tokens).Count | Should -Be 0
        }
    }

    Context "Test-SafeRelativePath" {
        It "Rejects .. traversal" {
            Test-SafeRelativePath "a\..\b" | Should -Be $false
        }

        It "Rejects Win32 trailing dot/space traversal variants of .." {
            Test-SafeRelativePath "a\.. \b" | Should -Be $false
            Test-SafeRelativePath "a\...\b" | Should -Be $false
            Test-SafeRelativePath ".. " | Should -Be $false
        }

        It "Still accepts plain relative paths and current-dot segments" {
            Test-SafeRelativePath "skills/foo" | Should -Be $true
            Test-SafeRelativePath "a\.\b" | Should -Be $true
        }
    }

    Context "Test-CfgArrayProperty" {
        It "Requires the property value itself to be an array" {
            Test-CfgArrayProperty ([pscustomobject]@{ enabled = "solo" }) "enabled" | Should -Be $false
            Test-CfgArrayProperty ([pscustomobject]@{ enabled = [pscustomobject]@{ a = 1 } }) "enabled" | Should -Be $false
            Test-CfgArrayProperty ([pscustomobject]@{ enabled = @() }) "enabled" | Should -Be $true
            Test-CfgArrayProperty ([pscustomobject]@{ enabled = @(1, 2) }) "enabled" | Should -Be $true
        }
    }

    Context "LoadCfg -NoAutoFix" {
        It "Diagnoses without persisting the auto-fix write-back" {
            $oldCfgPath = $CfgPath
            try {
                $CfgPath = Join-Path $TestDrive "skills-noautofix.json"
                $dupMapping = @{ vendor = "vendor-a"; from = "a"; to = "skill-x" }
                $cfg = @{
                    vendors = @(@{ name = "vendor-a"; repo = "https://example.com/a.git"; ref = "main" })
                    targets = @(@{ path = "~/.codex/skills" })
                    mappings = @($dupMapping, $dupMapping)
                    imports = @()
                    mcp_servers = @()
                    mcp_targets = @()
                    sync_mode = "link"
                    update_force = $true
                } | ConvertTo-Json -Depth 10
                Set-Content -Path $CfgPath -Value $cfg -Encoding UTF8
                $before = Get-ContentUtf8 $CfgPath

                LoadCfg -NoAutoFix | Out-Null
                Get-ContentUtf8 $CfgPath | Should -Be $before

                $cfgObj = LoadCfg
                Get-ContentUtf8 $CfgPath | Should -Not -Be $before
                @($cfgObj.mappings).Count | Should -Be 1
            }
            finally { $CfgPath = $oldCfgPath }
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

    Context "Update fast-noop Git probes fail-closed" {
        It "Does not treat a failed ignored-status probe as a clean cache" {
            $repo = Join-Path $TestDrive "update-status-failure"
            New-Item -ItemType Directory -Path $repo -Force | Out-Null
            $item = [pscustomobject]@{ type = "vendor"; name = "demo"; current = "abc"; target = "abc"; changed = $false }
            Mock VendorPath { $repo }
            Mock Test-IsGitRepoRoot { $true }
            Mock Invoke-GitCaptureCore {
                param($GitArgs, $Ok)
                $Ok.Value = $false
                return @()
            }

            Test-UpdateCacheCleanForPlanItem $item ([pscustomobject]@{ imports = @() }) | Should -BeFalse
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
            Mock Rollback-BuildTransaction { $true }
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

    It "Skips compensation projection and reports rollback_failed when rollback does not restore" {
        $oldDryRun = $DryRun
        $oldCfgPath = $CfgPath
        $oldRoot = $Root
        try {
            $DryRun = $false
            $Root = Join-Path $TestDrive "ws-build-compensation-failed"
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
            Mock 应用到ClaudeCodex { @("target:x => simulated failure") } -ParameterFilter { -not $PromotionContext -or $PromotionContext.promotion_mode -ne "unverified_override" }
            Mock Get-HostProjectionPromotionContext { [pscustomobject]@{ required = $false; promotion_mode = "local_only" } }
            Mock Get-HostProjectionPromotionContext { [pscustomobject]@{ required = $true; promotion_mode = "unverified_override" } } -ParameterFilter { [bool]$AllowUnverified }
            Mock Rollback-BuildTransaction { $false }
            Mock Complete-BuildTransaction {}
            Mock Sync-SkillDiscoveryCatalog {}
            Mock Sync-NativeAgentBridge {}

            # 回滚未恢复时：不得补偿投影，最终失败集必须如实含 rollback_failed。
            { 构建生效 } | Should -Throw '*rollback_failed*'

            Should -Invoke Rollback-BuildTransaction -Times 1 -Exactly
            Should -Invoke Get-HostProjectionPromotionContext -Times 0 -Exactly -ParameterFilter { [bool]$AllowUnverified }
            Should -Invoke 应用到ClaudeCodex -Times 0 -Exactly -ParameterFilter { $PromotionContext -and $PromotionContext.promotion_mode -eq "unverified_override" }
        }
        finally {
            $DryRun = $oldDryRun
            $CfgPath = $oldCfgPath
            $Root = $oldRoot
        }
    }

    It "passes a catalog transaction when host projection is skipped" {
        $oldDryRun = $DryRun
        $oldCfgPath = $CfgPath
        $oldLogPath = $LogPath
        $oldRoot = $Root
        $oldLocked = $Locked
        $oldSuppressAllLogging = $script:SuppressAllLogging
        try {
            $DryRun = $false
            $Locked = $false
            $script:SuppressAllLogging = $true
            $Root = Join-Path $TestDrive "ws-build-skip-host"
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
            $CfgPath = Join-Path $Root "skills.json"
            $LogPath = Join-Path $Root "build.log"
            $managed = Join-Path $Root "agent"
            $cfg = [pscustomobject]@{
                vendors = @(); targets = @(); mappings = @(); imports = @()
                mcp_servers = @(); mcp_targets = @(); sync_mode = "link"; update_force = $true
                skill_projection = [pscustomobject]@{ managed_source_path = $managed }
            }
            Mock Preflight {}
            Mock LoadCfg { $cfg }
            Mock SaveCfg {}
            Mock Optimize-Imports {}
            Mock Write-BuildSummary {}
            Mock New-SkillDiscoveryCatalogTransaction {
                [pscustomobject]@{
                    file_snapshots = @()
                    preserve_file_paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                }
            }
            Mock Start-BuildTransaction { [pscustomobject]@{ path = (Join-Path $Root '.txn\build-test') } }
            Mock 构建Agent { @() }
            Mock Sync-SkillDiscoveryCatalog {
                param($ProjectionCfg, $Transaction, [switch]$SkipLock)
                if ($null -eq $Transaction) { throw 'catalog transaction missing' }
                [pscustomobject]@{ enabled = $false; changed = $false; persisted = $false; skill_count = 0; domain_count = 0 }
            }
            Mock Complete-BuildTransaction {}

            { 构建生效 -SkipHostProjection } | Should -Not -Throw

            Should -Invoke New-SkillDiscoveryCatalogTransaction -Times 1 -Exactly
            Should -Invoke Sync-SkillDiscoveryCatalog -Times 1 -Exactly -ParameterFilter { $null -ne $Transaction -and [bool]$SkipLock }
            Should -Invoke Complete-BuildTransaction -Times 1 -Exactly
        }
        finally {
            $DryRun = $oldDryRun
            $CfgPath = $oldCfgPath
            $LogPath = $oldLogPath
            $Root = $oldRoot
            $Locked = $oldLocked
            $script:SuppressAllLogging = $oldSuppressAllLogging
        }
    }
}

Describe "Sparse checkout disable guard" {
    It "Fails closed when disable is required but fails" {
        Mock Invoke-GitCaptureCore {
            param($GitArgs, $Ok, $ExitCode)
            $Ok.Value = $true
            if ($null -ne $ExitCode) { $ExitCode.Value = 0 }
            return ,@("true")
        }
        Mock Invoke-Git { throw "git 失败：sparse-checkout disable" }
        { Set-GitSparseCheckout @() } | Should -Throw '*git 失败*'
        Should -Invoke Invoke-Git -Times 1 -Exactly -ParameterFilter { @($GitArgs) -contains "disable" }
    }

    It "Skips disable when sparse checkout was never enabled" {
        Mock Test-GitSparseCheckoutEnabled { $false }
        Mock Invoke-Git {}
        Set-GitSparseCheckout @()
        Should -Invoke Invoke-Git -Times 0 -Exactly
    }

    It "Fails closed when the sparse checkout config probe fails" {
        Mock Invoke-GitCaptureCore {
            param($GitArgs, $Ok, $ExitCode)
            $Ok.Value = $false
            if ($null -ne $ExitCode) { $ExitCode.Value = 128 }
            return @()
        }

        { Set-GitSparseCheckout @() } | Should -Throw '*无法读取 Git sparse checkout 配置*'
    }

    It "Runs disable when sparse checkout is enabled" {
        Mock Test-GitSparseCheckoutEnabled { $true }
        Mock Invoke-Git {}
        Set-GitSparseCheckout @()
        Should -Invoke Invoke-Git -Times 1 -Exactly -ParameterFilter { @($GitArgs) -contains "disable" }
    }

    It "Treats unconfigured sparse key as not enabled with real git" {
        $oldDryRun = $DryRun
        $DryRun = $false
        $repo = Join-Path $TestDrive ("sparse-probe-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "test git init failed" }
        Push-Location $repo
        try {
            # 键未配置（git config 查询 exit 1）是从未启用过 sparse 的正常态。
            Test-GitSparseCheckoutEnabled | Should -Be $false
            git -C $repo config --bool core.sparseCheckout false 2>$null
            Test-GitSparseCheckoutEnabled | Should -Be $false
            git -C $repo config --bool core.sparseCheckout true 2>$null
            Test-GitSparseCheckoutEnabled | Should -Be $true
        }
        finally {
            Pop-Location
            $DryRun = $oldDryRun
        }
    }

    It "Skips disable without calling git when sparse key is unconfigured (real git)" {
        $oldDryRun = $DryRun
        $DryRun = $false
        $repo = Join-Path $TestDrive ("sparse-fresh-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "test git init failed" }
        Push-Location $repo
        try {
            # 存量缓存 ensure 的真实生产路径：无 sparse 键的仓库不允许误触发 disable。
            Mock Invoke-Git { throw "git 不应被调用：键未配置时无需 disable" }
            { Set-GitSparseCheckout @() } | Should -Not -Throw
            Should -Invoke Invoke-Git -Times 0 -Exactly
        }
        finally {
            Pop-Location
            $DryRun = $oldDryRun
        }
    }

    It "Maps real git failure to Ok=false in Invoke-GitCaptureCore" {
        $oldDryRun = $DryRun
        $DryRun = $false
        $repo = Join-Path $TestDrive ("git-core-fail-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        git -C $repo init 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "test git init failed" }
        Push-Location $repo
        try {
            # 空 repo 无 HEAD：真实 git exit 128，必须映射为 Ok=false 而非空成功。
            $ok = $true
            $lines = Invoke-GitCaptureCore @("rev-parse", "HEAD") ([ref]$ok)
            $ok | Should -Be $false
            @($lines).Count | Should -Be 0
        }
        finally {
            Pop-Location
            $DryRun = $oldDryRun
        }
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
            $txn = [pscustomobject]@{
                path = $txnPath
                backup_agent = $backupAgent
                has_backup_agent = $true
                backup_error = $null
                agent_before_state = 'backed_up'
                agent_before_fingerprint = Get-DirectoryFingerprint $backupAgent
                backup_agent_fingerprint = Get-DirectoryFingerprint $backupAgent
                agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
                agent_after_fingerprint_error = ''
            }

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
            $txn = [pscustomobject]@{
                path = $txnPath
                backup_agent = $backupAgent
                has_backup_agent = $true
                backup_error = $null
                agent_before_state = 'backed_up'
                agent_before_fingerprint = Get-DirectoryFingerprint $backupAgent
                backup_agent_fingerprint = Get-DirectoryFingerprint $backupAgent
                agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
                agent_after_fingerprint_error = ''
            }
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

    It "Fails closed without deleting pre-build agent when backup is missing but agent existed before" {
        $oldAgentDir = $AgentDir
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $root = Join-Path $TestDrive "txn-no-backup"
            $txnPath = Join-Path $root "build-t3"
            New-Item -ItemType Directory -Path $txnPath -Force | Out-Null
            $AgentDir = Join-Path $root "agent"
            New-Item -ItemType Directory -Path (Join-Path $AgentDir "pre") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir "pre\SKILL.md") "pre-build content"
            # 备份挪动失败的三态：构建前 agent/ 仍在、无备份可恢复。
            $txn = [pscustomobject]@{ path = $txnPath; backup_agent = (Join-Path $txnPath "agent.backup"); has_backup_agent = $false; backup_error = "move failed"; agent_before_state = "present_no_backup" }

            Rollback-BuildTransaction $txn | Should -Be $false
            # 构建前 agent/ 是唯一副本，必须原样保留。
            Test-Path -LiteralPath (Join-Path $AgentDir "pre\SKILL.md") -PathType Leaf | Should -BeTrue
            Get-ContentUtf8 (Join-Path $AgentDir "pre\SKILL.md") | Should -Be "pre-build content"
            Test-Path -LiteralPath $txnPath -PathType Container | Should -BeTrue
        }
        finally {
            $AgentDir = $oldAgentDir
            $DryRun = $oldDryRun
        }
    }

    It "Clears built agent when no agent existed before build" {
        $oldAgentDir = $AgentDir
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $root = Join-Path $TestDrive "txn-absent"
            $txnPath = Join-Path $root "build-t4"
            New-Item -ItemType Directory -Path $txnPath -Force | Out-Null
            $AgentDir = Join-Path $root "agent"
            New-Item -ItemType Directory -Path (Join-Path $AgentDir "built") -Force | Out-Null
            $txn = [pscustomobject]@{
                path = $txnPath
                backup_agent = (Join-Path $txnPath "agent.backup")
                has_backup_agent = $false
                backup_error = $null
                agent_before_state = "absent"
                agent_before_fingerprint = 'missing'
                agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
                agent_after_fingerprint_error = ''
            }

            Rollback-BuildTransaction $txn | Should -Be $true
            Test-Path -LiteralPath $AgentDir | Should -BeFalse
            Test-Path -LiteralPath $txnPath | Should -BeFalse
        }
        finally {
            $AgentDir = $oldAgentDir
            $DryRun = $oldDryRun
        }
    }

    It "Restores catalog-stage writes into agent before the fingerprint CAS on rollback" {
        $oldAgentDir = $AgentDir
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $root = Join-Path $TestDrive "txn-catalog"
            $txnPath = Join-Path $root "build-t5"
            $backupAgent = Join-Path $txnPath "agent.backup"
            New-Item -ItemType Directory -Path (Join-Path $backupAgent "skill") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $backupAgent "skill\SKILL.md") "backup"
            $AgentDir = Join-Path $root "agent"
            New-Item -ItemType Directory -Path (Join-Path $AgentDir "new") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir "new\SKILL.md") "new"
            # agent_after_fingerprint 采集于构建完成时刻；cold-discovery catalog
            # 阶段随后向 agent/ 内写入。回滚必须先还原 catalog 快照，否则 CAS
            # 会把合法的 catalog 写入误判为并发漂移。
            $agentAfterFingerprint = Get-DirectoryFingerprint $AgentDir
            $catalogFile = Join-Path $AgentDir "new\catalog.json"
            $catalogBytes = [System.Text.Encoding]::UTF8.GetBytes("catalog-generated")
            Set-ContentUtf8 $catalogFile "catalog-generated"
            $catalogSnapshot = [pscustomobject][ordered]@{
                path = [IO.Path]::GetFullPath($catalogFile)
                existed = $false
                bytes = [byte[]]@()
                before_hash = ''
                before_kind = 'missing'
                after_known = $true
                after_existed = $true
                after_bytes = $catalogBytes
                after_hash = (Get-SkillProjectionBytesSha256 $catalogBytes)
                after_kind = 'file'
            }
            $txn = [pscustomobject]@{
                path = $txnPath
                backup_agent = $backupAgent
                has_backup_agent = $true
                backup_error = $null
                agent_before_state = 'backed_up'
                agent_before_fingerprint = Get-DirectoryFingerprint $backupAgent
                backup_agent_fingerprint = Get-DirectoryFingerprint $backupAgent
                agent_after_fingerprint = $agentAfterFingerprint
                agent_after_fingerprint_error = ''
                catalog_transaction = [pscustomobject]@{ file_snapshots = @($catalogSnapshot) }
            }

            Rollback-BuildTransaction $txn | Should -Be $true
            Test-Path -LiteralPath $catalogFile | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $AgentDir "new\SKILL.md") | Should -BeFalse
            Get-ContentUtf8 (Join-Path $AgentDir "skill\SKILL.md") | Should -Be "backup"
            Test-Path -LiteralPath $txnPath | Should -BeFalse
        }
        finally {
            $AgentDir = $oldAgentDir
            $DryRun = $oldDryRun
        }
    }

    It "Still fails closed on true concurrent drift without a catalog transaction" {
        $oldAgentDir = $AgentDir
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $root = Join-Path $TestDrive "txn-drift"
            $txnPath = Join-Path $root "build-t6"
            $backupAgent = Join-Path $txnPath "agent.backup"
            New-Item -ItemType Directory -Path (Join-Path $backupAgent "skill") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $backupAgent "skill\SKILL.md") "backup"
            $AgentDir = Join-Path $root "agent"
            New-Item -ItemType Directory -Path (Join-Path $AgentDir "new") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $AgentDir "new\SKILL.md") "new"
            $txn = [pscustomobject]@{
                path = $txnPath
                backup_agent = $backupAgent
                has_backup_agent = $true
                backup_error = $null
                agent_before_state = 'backed_up'
                agent_before_fingerprint = Get-DirectoryFingerprint $backupAgent
                backup_agent_fingerprint = Get-DirectoryFingerprint $backupAgent
                agent_after_fingerprint = Get-DirectoryFingerprint $AgentDir
                agent_after_fingerprint_error = ''
            }
            # 无事务快照覆盖的构建后变更仍是并发漂移，必须 fail closed。
            Set-ContentUtf8 (Join-Path $AgentDir "new\stray.txt") "drift"

            Rollback-BuildTransaction $txn | Should -Be $false
            Test-Path -LiteralPath $txnPath -PathType Container | Should -BeTrue
            Get-ContentUtf8 (Join-Path $backupAgent "skill\SKILL.md") | Should -Be "backup"
        }
        finally {
            $AgentDir = $oldAgentDir
            $DryRun = $oldDryRun
        }
    }
}

Describe "Managed-link-only whole-root rollback" {
    It "restores the whole-root junction when managed-link-only projection fails" {
        $oldAgentDir = $AgentDir
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $root = Join-Path $TestDrive "mlo-rollback"
            $agentDir = Join-Path $root "agent"
            New-Item -ItemType Directory -Path (Join-Path $agentDir "demo") -Force | Out-Null
            Set-ContentUtf8 (Join-Path $agentDir "demo\SKILL.md") "---`nname: demo`ndescription: Demo skill.`n---`nbody"
            $AgentDir = $agentDir
            $targetRoot = Join-Path $root "user-skills"
            New-Item -ItemType Junction -Path $targetRoot -Target $agentDir | Out-Null

            $cfg = [pscustomobject]@{ sync_mode = "link"; skill_projection = [pscustomobject]@{} }
            $targetCfg = [pscustomobject]@{ host = "codex"; receipt_path = "reports/skill-projection/mlo-rollback.json" }
            Mock Get-SkillProjectionEffectiveSelection { [pscustomobject]@{ included_names = @("demo"); excluded_names = @(); include_all = $false } }
            Mock Apply-NativeSkillProjection { throw "fixture projection failure" }

            { Sync-ManagedLinkOnlyTarget $cfg $targetCfg $targetRoot } | Should -Throw '*fixture projection failure*'

            # 行为反证：源码正则测试拦不住"恢复到错误目标/回滚失败不上报"——
            # 这里钉真实回滚：整目录 junction 必须重建并指回 agent/。
            (Is-ReparsePoint $targetRoot) | Should -BeTrue
            $restoredTarget = Get-NativeSkillProjectionLinkTarget $targetRoot
            [string]::Equals([string]$restoredTarget, [IO.Path]::GetFullPath($agentDir), [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        }
        finally {
            $AgentDir = $oldAgentDir
            $DryRun = $oldDryRun
        }
    }
}
