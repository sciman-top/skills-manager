# Dot-source the main script to load functions
. $PSScriptRoot\..\..\skills.ps1

Describe "Core Functions" {
    Context "Normalize-Name" {
        It "Normalizes typical names" {
            Normalize-Name " My Skill " | Should Be "my-skill"
            Normalize-Name "foo_bar" | Should Be "foo-bar"
            Normalize-Name "foo/bar" | Should Be "foo-bar"
        }

        It "Removes invalid characters" {
            Normalize-Name "foo@bar!" | Should Be "foo-bar"
        }

        It "Collapses multiple dashes" {
            Normalize-Name "foo--bar" | Should Be "foo-bar"
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

            (Test-PathEntry $link) | Should Be $true
            (Is-ReparsePoint $link) | Should Be $true

            New-Junction $link $newTarget

            $item = Get-Item -LiteralPath $link -Force
            $item.LinkType | Should Be "Junction"
            $item.Target | Should Be $newTarget
        }
    }

    Context "Literal path filesystem helpers" {
        It "Moves paths containing wildcard characters literally" {
            $src = Join-Path $TestDrive "skill[one]"
            $dst = Join-Path $TestDrive "skill[one]-moved"
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $src "SKILL.md") -Value "x"

            Invoke-MoveItem $src $dst

            (Test-Path -LiteralPath $src) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $dst "SKILL.md")) | Should Be $true
        }

        It "Removes paths containing wildcard characters literally" {
            $dir = Join-Path $TestDrive "remove[me]"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir "SKILL.md") -Value "x"

            Invoke-RemoveItemWithRetry $dir -Recurse | Should Be $true

            (Test-Path -LiteralPath $dir) | Should Be $false
        }
    }

    Context "Split-Args" {
        It "Splits simple arguments" {
            $tokens = Split-Args "foo bar baz"
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "foo"
        }

        It "External quotes are consumed" {
            $tokens = Split-Args 'foo "bar baz"'
            $tokens.Count | Should Be 2
            $tokens[1] | Should Be "bar baz"
        }
        
        It "Nested quotes are preserved" {
            # In PowerShell: Split-Args 'foo "bar \"baz\""' -> foo, bar "baz"
            $tokens = Split-Args 'foo "bar \"baz\""'
            $tokens.Count | Should Be 2
            $tokens[1] | Should Be 'bar "baz"'
        }

        It "Throws on unclosed double quote" {
            $thrown = $false
            try {
                Split-Args 'foo "bar baz' | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Throws on unclosed single quote" {
            $thrown = $false
            try {
                Split-Args "foo 'bar baz" | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
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
            Get-InstallErrorSuggestedSkillPath $msg @("remotion-best-practices") | Should Be "skills/remotion"
        }

        It "Falls back to input when candidate is unavailable" {
            $msg = "未找到技能入口文件：X"
            Get-InstallErrorSuggestedSkillPath $msg @("remotion-best-practices") | Should Be "skills/remotion-best-practices"
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

            ($items.Count -gt 0) | Should Be $true
            @($items).Count | Should Be 1
            @($items)[0].rel | Should Be "skills\remotion"
            @($items)[0].leaf | Should Be "remotion"
        }
    }

    Context "Resolve-SkillPath" {
        It "Auto-resolves compact name variants like uni-app -> skills\uniapp" {
            $base = Join-Path $TestDrive "repo-compact"
            $skillDir = Join-Path $base "skills\\uniapp"
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $skillDir "AGENTS.md") -Force | Out-Null

            Clear-SkillsCache
            Resolve-SkillPath $base "uni-app" | Should Be "skills\uniapp"
        }
    }

    Context "Parse-DefaultBranchFromSymref" {
        It "Parses main branch from ls-remote symref output" {
            Parse-DefaultBranchFromSymref "ref: refs/heads/main`tHEAD" | Should Be "main"
        }

        It "Parses master branch from ls-remote symref output" {
            Parse-DefaultBranchFromSymref "ref: refs/heads/master`tHEAD" | Should Be "master"
        }

        It "Returns null for non-symref output" {
            Parse-DefaultBranchFromSymref "4292f000a15ecf07a6d0900ab495b80864de2a15`tHEAD" | Should Be $null
        }
    }

    Context "Zip Repo Input" {
        It "Recognizes existing local zip as repo input" {
            $zip = Join-Path $TestDrive "sample.zip"
            Set-Content -Path $zip -Value "x"
            Test-LocalZipRepoInput $zip | Should Be $true
        }

        It "Extracts local zip via Ensure-Repo and keeps skill directory discoverable" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports-zip"
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null

                $srcRoot = Join-Path $TestDrive "myskills"
                $skillDir = Join-Path $srcRoot "downloaded-skills\\d3-viz"
                New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
                Set-Content -Path (Join-Path $skillDir "SKILL.md") -Value "# test"

                $zip = Join-Path $TestDrive "myskills.zip"
                Compress-Archive -Path (Join-Path $srcRoot "*") -DestinationPath $zip -Force

                $dest = Join-Path $TestDrive "cache"
                Ensure-Repo $dest $zip "main" $null $true $false

                (Test-IsSkillDir (Join-Path $dest "d3-viz")) | Should Be $true
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }

        It "Rejects sparse checkout when repo input is local zip" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports-zip-2"
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null

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
                $thrown | Should Be $true
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
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
                $_.Exception.Message | Should Match "并非有效的 GitHub 仓库格式"
            }
            $thrown | Should Be $true
        }

        It "Leaves ref empty when --ref is not provided" {
            $parsed = Parse-AddArgs @("https://github.com/othmanadi/planning-with-files", "--skill", "planning-with-files")
            [string]::IsNullOrWhiteSpace($parsed.ref) | Should Be $true
        }

        It "Uses provided ref when --ref is present" {
            $parsed = Parse-AddArgs @("https://github.com/othmanadi/planning-with-files", "--skill", "planning-with-files", "--ref", "master")
            $parsed.ref | Should Be "master"
        }

        It "Rejects repo URLs passed as --ref values" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--skill", "foo", "--ref", "https://github.com/google-labs-code/stitch-skills.git") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "--ref"
                $_.Exception.Message | Should Match "仓库地址"
            }
            $thrown | Should Be $true
        }

        It "Rejects empty --skill value" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--skill=") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Treats explicit dot as root skill path" {
            $parsed = Parse-AddArgs @("owner/repo", "--skill", ".")
            $parsed.skills.Count | Should Be 1
            $parsed.skills[0] | Should Be "."
        }

        It "Rejects missing option value when next token is another flag" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--ref", "--skill", "foo") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Rejects traversal skill path" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--skill", "..\\secret") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Rejects absolute skill path" {
            $thrown = $false
            try {
                Parse-AddArgs @("owner/repo", "--skill", "C:\\temp\\skill") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }
    }

    Context "Get-AddTokensFromNpx" {
        It "Parses lowercase npx skills add command" {
            $tokens = Get-AddTokensFromNpx @("skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Parses case-insensitive skills add command" {
            $tokens = Get-AddTokensFromNpx @("Skills", "Add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Accepts optional npx prefix in token list" {
            $tokens = Get-AddTokensFromNpx @("npx", "skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Throws clear error when skills add has no args" {
            $thrown = $false
            try {
                Get-AddTokensFromNpx @("skills", "add") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Parses add-skill command case-insensitively" {
            $tokens = Get-AddTokensFromNpx @("ADD-SKILL", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Parses single-string command input" {
            $tokens = Get-AddTokensFromNpx @("skills add owner/repo --skill foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }
    }

    Context "Get-AddTokensFromCommandLineTokens" {
        It "Parses direct add command" {
            $tokens = Get-AddTokensFromCommandLineTokens @("add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Parses direct skills add command" {
            $tokens = Get-AddTokensFromCommandLineTokens @("skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Parses npx command" {
            $tokens = Get-AddTokensFromCommandLineTokens @("npx", "skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Parses command with skills.ps1 prefix" {
            $tokens = Get-AddTokensFromCommandLineTokens @(".\\skills.ps1", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Parses command with skills.cmd prefix and npx.cmd" {
            $tokens = Get-AddTokensFromCommandLineTokens @("skills.cmd", "npx.cmd", "skills", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
        }

        It "Throws when only wrapper script is provided" {
            $thrown = $false
            try {
                Get-AddTokensFromCommandLineTokens @(".\\skills.ps1") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Throws when skills command misses subcommand" {
            $thrown = $false
            try {
                Get-AddTokensFromCommandLineTokens @("skills") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Throws when skills subcommand is unsupported" {
            $thrown = $false
            try {
                Get-AddTokensFromCommandLineTokens @("skills", "list") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }
    }

    Context "Resolve-AddTokensFromAnyFormat and Extract-SkillFromGitHubTreeUrl" {

        # ── Extract-SkillFromGitHubTreeUrl ──────────────────────────────────
        It "Extracts skill path from GitHub tree URL" {
            $skill = Extract-SkillFromGitHubTreeUrl "https://github.com/owner/repo/tree/main/skills/create-plan"
            $skill | Should Be "skills/create-plan"
        }

        It "Trims trailing punctuations like Chinese/English period appropriately" {
            $skill1 = Extract-SkillFromGitHubTreeUrl "https://github.com/openai/skills/tree/main/skills/.experimental/create-plan。"
            $skill1 | Should Be "skills/.experimental/create-plan"
            
            $skill2 = Extract-SkillFromGitHubTreeUrl "https://github.com/openai/skills/tree/main/skills/.experimental/create-plan,"
            $skill2 | Should Be "skills/.experimental/create-plan"
        }

        It "Extracts nested skill path from GitHub tree URL" {
            $skill = Extract-SkillFromGitHubTreeUrl "https://github.com/openai/skills/tree/main/skills/.experimental/create-plan"
            $skill | Should Be "skills/.experimental/create-plan"
        }

        It "Returns null for non-tree URL" {
            $skill = Extract-SkillFromGitHubTreeUrl "https://github.com/owner/repo"
            $skill | Should Be $null
        }

        It "Returns null for owner/repo shorthand" {
            $skill = Extract-SkillFromGitHubTreeUrl "owner/repo"
            $skill | Should Be $null
        }

        # ── /plugin format ──────────────────────────────────────────────────
        It "Resolves /plugin marketplace add owner/repo" {
            $tokens = Resolve-AddTokensFromAnyFormat @("/plugin", "marketplace", "add", "thedotmack/claude-mem")
            $tokens[0] | Should Be "thedotmack/claude-mem"
        }

        It "Resolves /plugin install owner/repo" {
            $tokens = Resolve-AddTokensFromAnyFormat @("/plugin", "install", "thedotmack/claude-mem")
            $tokens[0] | Should Be "thedotmack/claude-mem"
        }

        It "Passes through --skill flag from /plugin add" {
            $tokens = Resolve-AddTokensFromAnyFormat @("/plugin", "marketplace", "add", "owner/repo", "--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
            $tokens[1] | Should Be "--skill"
            $tokens[2] | Should Be "foo"
        }

        # ── $skill-installer format ─────────────────────────────────────────
        It 'Resolves $skill-installer owner/repo' {
            $tokens = Resolve-AddTokensFromAnyFormat @('$skill-installer', "owner/repo")
            $tokens[0] | Should Be "owner/repo"
        }

        It 'Resolves $skill-installer install owner/repo' {
            $tokens = Resolve-AddTokensFromAnyFormat @('$skill-installer', "install", "owner/repo")
            $tokens[0] | Should Be "owner/repo"
        }

        It 'Resolves $skill-installer install GitHub tree URL with skill path' {
            $url = "https://github.com/openai/skills/tree/main/skills/.experimental/create-plan"
            $tokens = Resolve-AddTokensFromAnyFormat @('$skill-installer', "install", $url)
            $tokens[0] | Should Be "https://github.com/openai/skills.git"
            $tokens[1] | Should Be "--skill"
            $tokens[2] | Should Be "skills/.experimental/create-plan"
        }

        # ── Bare GitHub Tree URL ────────────────────────────────────────────
        It "Resolves bare GitHub tree URL to repo + --skill" {
            $url = "https://github.com/openai/skills/tree/main/skills/create-plan"
            $tokens = Resolve-AddTokensFromAnyFormat @($url)
            $tokens[0] | Should Be "https://github.com/openai/skills.git"
            $tokens[1] | Should Be "--skill"
            $tokens[2] | Should Be "skills/create-plan"
        }

        It "Returns null for plain owner/repo (fallthrough to existing logic)" {
            $result = Resolve-AddTokensFromAnyFormat @("owner/repo", "--skill", "foo")
            $result | Should Be $null
        }

        # ── npm: scoped package auto-conversion ─────────────────────────────
        It "Converts npm install -g scoped package to owner/repo" {
            $tokens = Resolve-AddTokensFromAnyFormat @("npm", "install", "-g", "@steipete/summarize")
            $tokens.Count | Should Be 1
            $tokens[0] | Should Be "steipete/summarize"
        }

        It "Converts npm i -g scoped package to owner/repo" {
            $tokens = Resolve-AddTokensFromAnyFormat @("npm", "i", "-g", "@tobilu/qmd")
            $tokens.Count | Should Be 1
            $tokens[0] | Should Be "tobilu/qmd"
        }

        It "Still rejects npm install -g for non-scoped package" {
            $thrown = $false
            try {
                Resolve-AddTokensFromAnyFormat @("npm", "install", "-g", "left-pad") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "scoped"
            }
            $thrown | Should Be $true
        }

        # ── curl / Invoke-RestMethod: friendly error ─────────────────────────
        It "Throws friendly error for curl | bash pattern" {
            $thrown = $false
            try {
                Resolve-AddTokensFromAnyFormat @("curl", "-LsSf", "https://code.kimi.com/install.sh") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "curl"
            }
            $thrown | Should Be $true
        }

        It "Throws friendly error for Invoke-RestMethod pattern" {
            $thrown = $false
            try {
                Resolve-AddTokensFromAnyFormat @("Invoke-RestMethod", "https://code.kimi.com/install.ps1") | Out-Null
            }
            catch {
                $thrown = $true
                $_.Exception.Message | Should Match "Invoke-RestMethod"
            }
            $thrown | Should Be $true
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
                $tokens.Count | Should Be 3
                $tokens[0] | Should Be "https://github.com/acme/kimi-skill.git"
                $tokens[1] | Should Be "--skill"
                $tokens[2] | Should Be "skills/kimi"
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
                $tokens.Count | Should Be 1
                $tokens[0] | Should Be "https://github.com/acme/kimi-skill.git"
            }
            finally {
                $script:InstallScriptMappingsOverride = $null
            }
        }

        It 'Resolves $skill-installer bare curated skill name' {
            $tokens = Resolve-AddTokensFromAnyFormat @('$skill-installer', "gh-address-comments")
            $tokens[0] | Should Be "https://github.com/openai/skills.git"
            $tokens[1] | Should Be "--skill"
            $tokens[2] | Should Be "skills/.curated/gh-address-comments"
        }
    }

    Context "Try-ParseAddLikeInput / Looks-LikeRepoInput" {
        It "Parses npx command line and extracts repo/ref" {
            $parsed = Try-ParseAddLikeInput 'npx skills add vercel-labs/agent-skills --ref main'
            $parsed | Should Not Be $null
            $parsed.repo | Should Be "vercel-labs/agent-skills"
            $parsed.ref | Should Be "main"
        }

        It "Parses plugin install shorthand alias command" {
            $parsed = Try-ParseAddLikeInput '/plugin install claude-mem'
            $parsed | Should Not Be $null
            $parsed.repo | Should Be "thedotmack/claude-mem"
        }

        It "Returns false for non-repo short name" {
            (Looks-LikeRepoInput "agent-skills") | Should Be $false
        }

        It "Returns true for owner/repo" {
            (Looks-LikeRepoInput "vercel-labs/agent-skills") | Should Be $true
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
                $_.Exception.Message | Should Match "同一技能库"
                $_.Exception.Message | Should Match "identityKey"
            }
            $thrown | Should Be $true
        }

        It "Auto suffixes when vendor name exists with different repo" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "skills"; repo = "https://github.com/openai/skills.git"; ref = "main" }
                )
            }
            $name = Resolve-UniqueVendorName $cfg "skills" "vercel-labs/agent-skills"
            $name | Should Be "skills-2"
        }

        It "Allows reusing existing vendor name for same repo when explicitly requested" {
            $cfg = [pscustomobject]@{
                vendors = @(
                    [pscustomobject]@{ name = "superpowers"; repo = "https://github.com/obra/superpowers.git"; ref = "main" }
                )
            }
            $name = Resolve-UniqueVendorName $cfg "superpowers" "https://github.com/obra/superpowers.git" $true
            $name | Should Be "superpowers"
        }
    }

    Context "Repository identity matching" {
        It "Treats owner/repo and https URL as same repository" {
            (Is-SameRepository "openai/skills" "https://github.com/openai/skills.git") | Should Be $true
        }

        It "Treats git@ and https URL as same repository" {
            (Is-SameRepository "git@github.com:openai/skills.git" "https://github.com/openai/skills") | Should Be $true
        }

        It "Treats tree URL and repo URL as same repository" {
            (Is-SameRepository "https://github.com/openai/skills/tree/main/skills/.curated/pdf" "openai/skills") | Should Be $true
        }

        It "Recognizes different owner as different repository" {
            (Is-SameRepository "openai/skills" "vercel-labs/skills") | Should Be $false
        }

        It "Builds stable identity key for ssh URL" {
            (Get-RepoIdentityKey "ssh://git@github.com/openai/skills.git") | Should Be "github.com/openai/skills"
        }
    }

    Context "Installed state detection" {
        It "Treats a vendor directory as installed only when the remote origin matches" {
            $vendorPath = Join-Path $TestDrive "vendor-same"
            New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null
            git -C $vendorPath init | Out-Null
            git -C $vendorPath remote add origin https://github.com/openai/skills.git

            (Test-InstalledVendorPath $vendorPath "openai/skills") | Should Be $true
        }

        It "Does not treat a vendor directory as installed when the remote origin differs" {
            $vendorPath = Join-Path $TestDrive "vendor-diff"
            New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null
            git -C $vendorPath init | Out-Null
            git -C $vendorPath remote add origin https://github.com/vercel-labs/skills.git

            (Test-InstalledVendorPath $vendorPath "openai/skills") | Should Be $false
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

            (Test-McpServerEquivalent $a $b) | Should Be $true
            (Find-EquivalentMcpServer @($a) $b).name | Should Be "context7"
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

            (Test-McpServerEquivalent $a $b) | Should Be $false
            (Find-EquivalentMcpServer @($a) $b) | Should Be $null
        }
    }

    Context "Merge-FilterAndArgs" {
        It "Prepends Filter when Filter is set" {
            $tokens = Merge-FilterAndArgs "owner/repo" @("--skill", "foo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "owner/repo"
            $tokens[1] | Should Be "--skill"
            $tokens[2] | Should Be "foo"
        }

        It "Returns args unchanged when Filter is empty" {
            $tokens = Merge-FilterAndArgs "" @("skills", "add", "owner/repo")
            $tokens.Count | Should Be 3
            $tokens[0] | Should Be "skills"
            $tokens[1] | Should Be "add"
            $tokens[2] | Should Be "owner/repo"
        }
    }

    Context "Parse-McpInstallArgs" {
        It "Parses stdio MCP server arguments" {
            $parsed = Parse-McpInstallArgs @("context7", "--cmd", "npx", "--", "-y", "@upstash/context7-mcp")
            $parsed.name | Should Be "context7"
            $parsed.transport | Should Be "stdio"
            $parsed.command | Should Be "npx"
            $parsed.args.Count | Should Be 2
            $parsed.args[0] | Should Be "-y"
        }

        It "Normalizes accidental --arg wrappers for stdio args" {
            $parsed = Parse-McpInstallArgs @("filesystem", "--cmd", "npx", "--arg", "-y", "--arg", "@modelcontextprotocol/server-filesystem", "--arg", "E:\\CODE\\skills-manager")
            $parsed.command | Should Be "npx"
            $parsed.args.Count | Should Be 3
            $parsed.args[0] | Should Be "-y"
            $parsed.args[1] | Should Be "@modelcontextprotocol/server-filesystem"
        }

        It "Supports command tail after -- without --cmd" {
            $parsed = Parse-McpInstallArgs @("fetch", "--", "npx", "-y", "@modelcontextprotocol/server-fetch")
            $parsed.command | Should Be "npx"
            $parsed.args.Count | Should Be 2
            $parsed.args[1] | Should Be "@modelcontextprotocol/server-fetch"
        }

        It "Supports stdio args that start with '-' after --cmd without explicit -- separator" {
            $parsed = Parse-McpInstallArgs @("context7", "--cmd", "npx", "-y", "@upstash/context7-mcp")
            $parsed.command | Should Be "npx"
            $parsed.args.Count | Should Be 2
            $parsed.args[0] | Should Be "-y"
            $parsed.args[1] | Should Be "@upstash/context7-mcp"
        }

        It "Supports command tail without explicit -- separator" {
            $parsed = Parse-McpInstallArgs @("git", "uvx", "mcp-server-git", "--repository", "E:\\CODE\\skills-manager")
            $parsed.command | Should Be "uvx"
            $parsed.args.Count | Should Be 3
            $parsed.args[0] | Should Be "mcp-server-git"
        }

        It "Rejects missing --cmd value when next token is another flag" {
            $thrown = $false
            try {
                Parse-McpInstallArgs @("fetch", "--cmd", "--arg", "-y") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Rejects missing --url value when next token is another flag" {
            $thrown = $false
            try {
                Parse-McpInstallArgs @("remote", "--transport", "http", "--url", "--header", "k=v") | Out-Null
            }
            catch {
                $thrown = $true
            }
            $thrown | Should Be $true
        }

        It "Parses bearer token env var for remote MCP servers" {
            $parsed = Parse-McpInstallArgs @("github", "--transport", "http", "--url", "https://api.githubcopilot.com/mcp/readonly", "--bearer-token-env-var", "GITHUB_PERSONAL_ACCESS_TOKEN")
            $parsed.name | Should Be "github"
            $parsed.transport | Should Be "http"
            $parsed.bearer_token_env_var | Should Be "GITHUB_PERSONAL_ACCESS_TOKEN"
        }
    }

    Context "Parse-McpStdioCommandLine" {
        It "Normalizes accidental --arg wrappers in interactive stdio command line" {
            $parsed = Parse-McpStdioCommandLine "fetch" "npx --arg -y --arg @upstash/context7-mcp"
            $parsed.command | Should Be "npx"
            $parsed.args.Count | Should Be 2
            $parsed.args[0] | Should Be "-y"
            $parsed.args[1] | Should Be "@upstash/context7-mcp"
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
            $map.PSObject.Properties.Name.Count | Should Be 1
            $map.context7.command | Should Be "npx"
            $map.context7.args.Count | Should Be 2
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
            $payload.tools.allowed[0] | Should Be "run_shell_command(git status)"
            $payload.experimental.skills | Should Be $true
            $payload.mcpServers.fetch.command | Should Be "python"
            $payload.mcpServers.fetch.args.Count | Should Be 2
            $payload.mcpServers.fetch.PSObject.Properties.Name -contains "transport" | Should Be $false
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
            $payload.mcpServers.fetch.command | Should Be "python"
        }
    }

    Context "Build-CodexConfigToml" {
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
                $toml | Should Match "model = ""gpt-5.3-codex"""
                $toml | Should Match "\[windows\]"
                $toml | Should Match "\[mcp_servers\.old\]"
                $toml | Should Not Match "\[mcp_servers\.github\]"
                $toml | Should Not Match "url = ""https://api.githubcopilot.com/mcp/readonly"""
                $toml | Should Not Match "bearer_token_env_var = ""CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"""
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
            $toml | Should Match "model = ""gpt-5.3-codex"""
            $toml | Should Match "\[windows\]"
            $toml | Should Not Match "\[mcp_servers\.old\]"
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
                $toml | Should Not Match "\[mcp_servers\.github\]"
                $toml | Should Match "\[mcp_servers\.microsoft-learn\]"
                $toml | Should Match "url = ""https://learn.microsoft.com/api/mcp"""
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
                $toml | Should Match "\[mcp_servers\.github\]"
                $toml | Should Match "url = ""https://api.githubcopilot.com/mcp/readonly"""
                $toml | Should Match "bearer_token_env_var = ""CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"""
                $toml | Should Match "\[mcp_servers\.microsoft-learn\]"
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
            Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
            try {
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
                $toml | Should Match "\[mcp_servers\.context7\]"
                $toml | Should Match "\[mcp_servers\.microsoft-learn\]"
                $toml | Should Match "startup_timeout_sec = 120"
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
                $toml | Should Not Match "\[mcp_servers\.github\]"
                $toml | Should Match "\[mcp_servers\.microsoft-learn\]"
                $toml | Should Match "url = ""https://learn.microsoft.com/api/mcp"""
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
    }

    Context "Resolve-GeminiAntigravityRootsFromCandidates" {
        It "Extracts antigravity roots from resolved candidate paths" {
            $paths = @(
                "C:\Users\sciman\.gemini\skills",
                "C:\Users\sciman\.gemini\antigravity\skills",
                "C:\Users\sciman\.trae\skills"
            )
            $roots = Resolve-GeminiAntigravityRootsFromCandidates $paths
            $roots.Count | Should Be 1
            $roots[0] | Should Be "C:\Users\sciman\.gemini\antigravity"
        }

        It "Ignores lookalike paths that are not antigravity directory" {
            $paths = @(
                "C:\Users\sciman\.gemini\antigravity-backup\skills",
                "C:\Users\sciman\.gemini\antigravity2\skills"
            )
            $roots = Resolve-GeminiAntigravityRootsFromCandidates $paths
            @($roots).Count | Should Be 0
        }

        It "Finds valid antigravity root even when an earlier lookalike appears in path" {
            $paths = @(
                "C:\tmp\.gemini\antigravity-backup\foo\.gemini\antigravity\skills"
            )
            $roots = Resolve-GeminiAntigravityRootsFromCandidates $paths
            $roots.Count | Should Be 1
            $roots[0] | Should Be "C:\tmp\.gemini\antigravity-backup\foo\.gemini\antigravity"
        }

        It "Requires directory boundary before .gemini token" {
            $paths = @(
                "C:\tmp\foo.gemini\antigravity\skills"
            )
            $roots = Resolve-GeminiAntigravityRootsFromCandidates $paths
            @($roots).Count | Should Be 0
        }
    }

    Context "Get-TraeProjectMcpConfigPath" {
        It "Builds project-level Trae MCP config path under repo root" {
            $repoRoot = Join-Path $TestDrive "skills-manager"
            $path = Get-TraeProjectMcpConfigPath $repoRoot
            $path | Should Be (Join-Path $repoRoot ".trae\mcp.json")
        }
    }

    Context "Get-NativeMcpCleanupCommands" {
        It "Includes Claude user and local cleanup commands for removed server" {
            $cmds = Get-NativeMcpCleanupCommands "fetch"
            $serialized = $cmds | ForEach-Object { "$($_.command) $($_.args -join ' ')" }
            ($serialized -join "`n") | Should Match "claude mcp remove fetch --scope user"
            ($serialized -join "`n") | Should Match "claude mcp remove fetch --scope project"
        }
    }

    Context "Get-NativeMcpAddArgs" {
        It "Places HTTP headers after name/url and expands env placeholders for Claude native MCP sync" {
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
                $joined | Should Match '--transport http github https://api\.githubcopilot\.com/mcp'
                $joined | Should Match '-H Authorization: Bearer unit-test-token'
                $joined | Should Not Match 'Authorization=Bearer'
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
            $updated.mcpServers.PSObject.Properties.Name -contains "context7" | Should Be $true
            $updated.mcpServers.PSObject.Properties.Name -contains "fetch" | Should Be $false
            $updated.mcpServers.PSObject.Properties.Name -contains "filesystem" | Should Be $false
            $updated.mcpServers.PSObject.Properties.Name -contains "microsoft_learn" | Should Be $true
        }
    }

    Context "Get-LegacyMcpServersToPrune" {
        It "Returns fetch and filesystem as legacy MCP names" {
            $names = Get-LegacyMcpServersToPrune
            @($names).Count | Should Be 2
            ($names -contains "fetch") | Should Be $true
            ($names -contains "filesystem") | Should Be $true
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
            } -Scope It

            $result = Invoke-ExternalCommandCapture "gemini" @("mcp", "list") 5
            $result.timed_out | Should Be $true
            $result.exit_code | Should Be 124
            $result.error | Should Be "timeout_after_5s"
            @($result.output).Count | Should Be 1
        }

        It "Passes arguments through timeout wrapper without colliding with automatic args" {
            $result = Invoke-ExternalCommandWithTimeout -command "cmd" -args @("/c", "echo wrapper-args-ok") -workingDir $TestDrive -timeoutSeconds 5

            $result.timed_out | Should Be $false
            $result.exit_code | Should Be 0
            (($result.output | ForEach-Object { [string]$_ }) -join "`n") | Should Match "wrapper-args-ok"
        }

        It "Preserves output captured before an external command timeout" {
            $result = Invoke-ExternalCommandWithTimeout "cmd" @(
                "/c",
                "echo before-timeout && ping -n 4 127.0.0.1 >nul"
            ) $TestDrive 1

            $result.timed_out | Should Be $true
            $result.exit_code | Should Be 124
            (($result.output | ForEach-Object { [string]$_ }) -join "`n") | Should Match "before-timeout"
            $result.error | Should Match "timeout_after_1s"
        }

        It "Clamps timeout value from env to the configured bounds" {
            $name = "SKILLS_MCP_TIMEOUT_CLAMP_TEST"
            $old = [System.Environment]::GetEnvironmentVariable($name)
            try {
                [System.Environment]::SetEnvironmentVariable($name, "0")
                (Resolve-TimeoutSecondsFromEnv $name 30 1 600) | Should Be 1

                [System.Environment]::SetEnvironmentVariable($name, "9999")
                (Resolve-TimeoutSecondsFromEnv $name 30 1 600) | Should Be 600

                [System.Environment]::SetEnvironmentVariable($name, "42")
                (Resolve-TimeoutSecondsFromEnv $name 30 1 600) | Should Be 42
            }
            finally {
                [System.Environment]::SetEnvironmentVariable($name, $old)
            }
        }

        It "Detects non-interactive MCP error hints" {
            (Test-IsNonInteractiveMcpError "Error: Input must be provided either through stdin") | Should Be $true
            (Test-IsNonInteractiveMcpError "stdout is not a terminal") | Should Be $true
            (Test-IsNonInteractiveMcpError "random failure text") | Should Be $false
        }

        It "Resolves PowerShell wrapper commands to pwsh-first invocation" {
            Mock Get-Command {
                [pscustomobject]@{
                    Path = "C:\tools\demo.ps1"
                }
            } -ParameterFilter { $Name -eq "demo" } -Scope It

            $invocation = Resolve-ExternalCommandInvocation "demo" @("mcp", "list")
            Split-Path -Leaf $invocation.file | Should Match "^(pwsh|powershell)(\.exe)?$"
            $invocation.args[4] | Should Be "-File"
            $invocation.args[5] | Should Be "C:\tools\demo.ps1"
            $invocation.args[6] | Should Be "mcp"
            $invocation.args[7] | Should Be "list"
        }

        It "Keeps native executable path when command is not a PowerShell wrapper" {
            Mock Get-Command {
                [pscustomobject]@{
                    Path = "C:\tools\demo.exe"
                }
            } -ParameterFilter { $Name -eq "demoexe" } -Scope It

            $invocation = Resolve-ExternalCommandInvocation "demoexe" @("arg1")
            $invocation.file | Should Be "C:\tools\demo.exe"
            @($invocation.args).Count | Should Be 1
            $invocation.args[0] | Should Be "arg1"
        }

        It "Skips gemini CLI verification by default" {
            $result = Test-CliMcpServerReady "gemini" @("context7")
            $result.ok | Should Be $true
            $result.reason | Should Be "gemini_cli_verification_skipped"
            @($result.missing).Count | Should Be 0
        }

        It "Falls back to config-state success when gemini CLI is missing in forced verification mode" {
            $old = [System.Environment]::GetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI")
            try {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", "1")
                Mock Get-Command { $null } -ParameterFilter { $Name -eq "gemini" } -Scope It

                $result = Test-CliMcpServerReady "gemini" @("context7")
                $result.ok | Should Be $true
                $result.reason | Should Be "gemini_cli_not_found_fallback"
                @($result.missing).Count | Should Be 0
            }
            finally {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", $old)
            }
        }

        It "Falls back to config-state success when gemini mcp list times out in forced verification mode" {
            $old = [System.Environment]::GetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI")
            try {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", "1")
                Mock Get-Command { [pscustomobject]@{ Name = "gemini" } } -ParameterFilter { $Name -eq "gemini" } -Scope It
                Mock Get-McpListVerifyTimeoutSeconds { 7 } -ParameterFilter { $cli -eq "gemini" } -Scope It
                Mock Invoke-ExternalCommandCapture {
                    [pscustomobject]@{
                        command = "gemini"
                        args = @("mcp", "list")
                        exit_code = 124
                        timed_out = $true
                        error = "timeout_after_7s"
                        output = @()
                    }
                } -ParameterFilter { $command -eq "gemini" } -Scope It

                $result = Test-CliMcpServerReady "gemini" @("context7")
                $result.ok | Should Be $true
                $result.reason | Should Be "gemini_cli_timeout_fallback_7s"
                @($result.missing).Count | Should Be 0
            }
            finally {
                [System.Environment]::SetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI", $old)
            }
        }

        It "Keeps claude timeout as verification failure" {
            Mock Get-Command { [pscustomobject]@{ Name = "claude" } } -ParameterFilter { $Name -eq "claude" } -Scope It
            Mock Get-McpListVerifyTimeoutSeconds { 11 } -ParameterFilter { $cli -eq "claude" } -Scope It
            Mock Invoke-ExternalCommandCapture {
                [pscustomobject]@{
                    command = "claude"
                    args = @("mcp", "list")
                    exit_code = 124
                    timed_out = $true
                    error = "timeout_after_11s"
                    output = @()
                }
            } -ParameterFilter { $command -eq "claude" } -Scope It

            $result = Test-CliMcpServerReady "claude" @("context7")
            $result.ok | Should Be $false
            $result.reason | Should Be "timeout_after_11s"
            @($result.missing).Count | Should Be 1
            $result.missing[0] | Should Be "context7"
        }

    }

    Context "Get-McpServerNamesFromJsonText" {
        It "Extracts mcpServers property names from JSON payload" {
            $json = '{"mcpServers":{"context7":{"type":"stdio"},"github":{"type":"http"}}}'
            $names = Get-McpServerNamesFromJsonText $json
            @($names).Count | Should Be 2
            ($names -contains "context7") | Should Be $true
            ($names -contains "github") | Should Be $true
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
'@
            $names = Get-CodexMcpServerNamesFromTomlText $toml
            @($names).Count | Should Be 2
            ($names -contains "context7") | Should Be $true
            ($names -contains "github") | Should Be $true
        }
    }

    Context "Has-McpServerByName" {
        It "Returns true when target MCP name exists in server list" {
            $servers = @(
                [pscustomobject]@{ name = "context7"; transport = "stdio" },
                [pscustomobject]@{ name = "github"; transport = "http" }
            )
            (Has-McpServerByName $servers "github") | Should Be $true
        }

        It "Returns false when target MCP name does not exist in server list" {
            $servers = @(
                [pscustomobject]@{ name = "context7"; transport = "stdio" }
            )
            (Has-McpServerByName $servers "github") | Should Be $false
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
            $roots.Count | Should Be 3
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude")) | Should Be $true
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex")) | Should Be $true
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".gemini")) | Should Be $true
        }

        It "Returns stable array shape for single resolved root" {
            $cfg = [pscustomobject]@{
                targets     = @(
                    [pscustomobject]@{ path = "~/.claude/skills" }
                )
                mcp_targets = @()
            }
            $roots = Resolve-McpTargetRootsFromCfg $cfg
            $roots.Count | Should Be 1
            $roots[0] | Should Be (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude")
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
            @($roots).Count | Should Be 3
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".gemini")) | Should Be $false
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex")) | Should Be $false
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude")) | Should Be $false
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".gemini_backup")) | Should Be $true
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex-temp")) | Should Be $true
            ($roots -contains (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude2")) | Should Be $true
        }

        It "Finds valid dot-directory root in mcp_targets even after lookalike prefix" {
            $cfg = [pscustomobject]@{
                targets     = @()
                mcp_targets = @(
                    "~/.gemini_backup/foo/.gemini/mcp.json"
                )
            }
            $roots = Resolve-McpTargetRootsFromCfg $cfg
            $roots.Count | Should Be 1
            $roots[0] | Should Match "\\.gemini$"
            $roots[0] | Should Not Match "mcp\\.json$"
        }

        It "Chooses the earliest valid dot-directory root in a mixed path" {
            $cfg = [pscustomobject]@{
                targets     = @()
                mcp_targets = @(
                    "~/.trae/workspace/.claude/skills"
                )
            }
            $roots = Resolve-McpTargetRootsFromCfg $cfg
            $roots.Count | Should Be 1
            $roots[0] | Should Be (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".trae")
        }
    }

    Context "Migrate-ManualToVendor" {
        It "Removes legacy manual dir and migrates import to vendor mode" {
            $oldVendorDir = $script:VendorDir
            $oldManualDir = $script:ManualDir
            $oldImportDir = $script:ImportDir
            try {
                $script:VendorDir = Join-Path $TestDrive "vendor"
                $script:ManualDir = Join-Path $TestDrive "manual"
                $script:ImportDir = Join-Path $TestDrive "imports"
                New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $script:ManualDir -Force | Out-Null
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null

                $vendorSkillDir = Join-Path $script:VendorDir "myvendor\\skills\\demo"
                New-Item -ItemType Directory -Path $vendorSkillDir -Force | Out-Null
                New-Item -ItemType File -Path (Join-Path $vendorSkillDir "SKILL.md") -Force | Out-Null

                $manualLegacyDir = Join-Path $script:ManualDir "demo-manual"
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
                $migrated | Should Be 1
                (Test-Path $manualLegacyDir) | Should Be $false
                @($cfg.imports | Where-Object { $_.name -eq "demo-manual" }).Count | Should Be 0
                @($cfg.imports | Where-Object { $_.name -eq "myvendor" -and $_.mode -eq "vendor" }).Count | Should Be 1
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "demo-manual" }).Count | Should Be 0
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "skills\\demo" }).Count | Should Be 0
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "keep-me" }).Count | Should Be 1
            }
            finally {
                $script:VendorDir = $oldVendorDir
                $script:ManualDir = $oldManualDir
                $script:ImportDir = $oldImportDir
            }
        }

        It "Counts migration even when legacy manual dir does not exist" {
            $oldVendorDir = $script:VendorDir
            $oldManualDir = $script:ManualDir
            $oldImportDir = $script:ImportDir
            try {
                $script:VendorDir = Join-Path $TestDrive "vendor2"
                $script:ManualDir = Join-Path $TestDrive "manual2"
                $script:ImportDir = Join-Path $TestDrive "imports2"
                New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $script:ManualDir -Force | Out-Null
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null

                $vendorSkillDir = Join-Path $script:VendorDir "myvendor\\skills\\demo"
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
                $migrated | Should Be 1
                @($cfg.imports | Where-Object { $_.name -eq "demo-manual" }).Count | Should Be 0
                @($cfg.imports | Where-Object { $_.name -eq "myvendor" -and $_.mode -eq "vendor" }).Count | Should Be 1
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq "demo-manual" }).Count | Should Be 0
            }
            finally {
                $script:VendorDir = $oldVendorDir
                $script:ManualDir = $oldManualDir
                $script:ImportDir = $oldImportDir
            }
        }
    }

    Context "Convert-InstalledVendorSkillsToManual" {
        It "Converts installed vendor mappings to manual imports while preserving target names" {
            $oldVendorDir = $script:VendorDir
            $oldImportDir = $script:ImportDir
            try {
                $script:VendorDir = Join-Path $TestDrive "vendor-convert"
                $script:ImportDir = Join-Path $TestDrive "imports-convert"
                New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null

                $skillSrc = Join-Path $script:VendorDir "demo-vendor\\skills\\content-strategy"
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

                $result.converted | Should Be 1
                @($cfg.mappings | Where-Object { $_.vendor -eq "demo-vendor" }).Count | Should Be 0
                @($cfg.imports | Where-Object { $_.mode -eq "manual" }).Count | Should Be 1
                $manualImport = @($cfg.imports | Where-Object { $_.mode -eq "manual" })[0]
                $manualImport.skill | Should Be "."
                $manualName = [string]$manualImport.name
                (Test-Path (Join-Path $script:ImportDir ($manualName + "\\SKILL.md"))) | Should Be $true
                @($cfg.mappings | Where-Object { $_.vendor -eq "manual" -and $_.from -eq $manualName -and $_.to -eq "demo-vendor-skills-content-strategy" }).Count | Should Be 1
            }
            finally {
                $script:VendorDir = $oldVendorDir
                $script:ImportDir = $oldImportDir
            }
        }
    }

    Context "Invoke-Doctor" {
        It "Shows non-empty Git version in DryRun" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $true

                Mock Write-Host {}
                Mock Get-CimInstance { [pscustomobject]@{ Caption = "Windows"; OSArchitecture = "64-bit" } }
                Mock Get-ItemProperty { [pscustomobject]@{ LongPathsEnabled = 1 } }
                Mock Test-NetConnection { $true }
                Mock Test-Path { $false } -ParameterFilter { $Path -eq $script:CfgPath }

                Invoke-Doctor

                Assert-MockCalled Write-Host -Exactly -Times 1 -ParameterFilter {
                    $Object -like "✅ Git:*" -and $Object.Trim() -ne "✅ Git:"
                }
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }
    }

    Context "Lockfile Strict Mode" {
        It "Throws when lock file is missing in locked mode" {
            $oldRoot = $script:Root
            $oldCfgPath = $script:CfgPath
            $oldVendorDir = $script:VendorDir
            $oldImportDir = $script:ImportDir
            try {
                $script:Root = Join-Path $TestDrive "ws-lock-missing"
                $script:CfgPath = Join-Path $script:Root "skills.json"
                $script:VendorDir = Join-Path $script:Root "vendor"
                $script:ImportDir = Join-Path $script:Root "imports"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null

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
                $thrown | Should Be $true
            }
            finally {
                $script:Root = $oldRoot
                $script:CfgPath = $oldCfgPath
                $script:VendorDir = $oldVendorDir
                $script:ImportDir = $oldImportDir
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
            $thrown | Should Be $true
        }

        It "Throws when lock commit differs from workspace commit" {
            $oldVendorDir = $script:VendorDir
            try {
                $script:VendorDir = Join-Path $TestDrive "vendor-lock-commit"
                New-Item -ItemType Directory -Path (Join-Path $script:VendorDir "demo") -Force | Out-Null

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
                $thrown | Should Be $true
            }
            finally {
                $script:VendorDir = $oldVendorDir
            }
        }

        It "Writes lock file with current vendors and imports" {
            $oldRoot = $script:Root
            $oldCfgPath = $script:CfgPath
            $oldVendorDir = $script:VendorDir
            $oldImportDir = $script:ImportDir
            try {
                $script:Root = Join-Path $TestDrive "ws-lock-write"
                $script:CfgPath = Join-Path $script:Root "skills.json"
                $script:VendorDir = Join-Path $script:Root "vendor"
                $script:ImportDir = Join-Path $script:Root "imports"
                New-Item -ItemType Directory -Path (Join-Path $script:VendorDir "demo") -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $script:ImportDir "manual-demo") -Force | Out-Null

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
                (Test-Path (Get-LockPath)) | Should Be $true
                @($lock.vendors).Count | Should Be 1
                @($lock.imports).Count | Should Be 1
                $lock.vendors[0].commit | Should Be "abc123"
            }
            finally {
                $script:Root = $oldRoot
                $script:CfgPath = $oldCfgPath
                $script:VendorDir = $oldVendorDir
                $script:ImportDir = $oldImportDir
            }
        }

        It "Writes lock metadata for local zip imports" {
            $oldRoot = $script:Root
            $oldCfgPath = $script:CfgPath
            $oldVendorDir = $script:VendorDir
            $oldImportDir = $script:ImportDir
            try {
                $script:Root = Join-Path $TestDrive "ws-lock-zip"
                $script:CfgPath = Join-Path $script:Root "skills.json"
                $script:VendorDir = Join-Path $script:Root "vendor"
                $script:ImportDir = Join-Path $script:Root "imports"
                New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
                New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null
                $cache = Join-Path $script:ImportDir "manual-demo"
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
                [string]$lock.imports[0].source_kind | Should Be "local_zip"
                [string]$lock.imports[0].source_hash | Should Not BeNullOrEmpty
                [string]$lock.imports[0].workspace_fingerprint | Should Not BeNullOrEmpty
                ($lock.imports[0].PSObject.Properties.Match("commit").Count -gt 0) | Should Be $false
            }
            finally {
                $script:Root = $oldRoot
                $script:CfgPath = $oldCfgPath
                $script:VendorDir = $oldVendorDir
                $script:ImportDir = $oldImportDir
            }
        }

        It "Detects local zip source drift in locked workspace" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports-lock-zip-drift"
                $cache = Join-Path $script:ImportDir "manual-demo"
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
                    $_.Exception.Message | Should Match "源文件不匹配"
                }
                $thrown | Should Be $true
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }

        It "Replays local zip imports end-to-end from rooted archives" {
            $oldRoot = $script:Root
            $oldCfgPath = $script:CfgPath
            $oldVendorDir = $script:VendorDir
            $oldImportDir = $script:ImportDir
            try {
                $workspaceRoot = Join-Path $TestDrive "ws-lock-zip-e2e"
                $script:Root = $workspaceRoot
                $script:CfgPath = Join-Path $workspaceRoot "skills.json"
                $script:VendorDir = Join-Path $workspaceRoot "vendor"
                $script:ImportDir = Join-Path $workspaceRoot "imports"
                New-Item -ItemType Directory -Path $workspaceRoot -Force | Out-Null
                New-Item -ItemType Directory -Path $script:VendorDir -Force | Out-Null
                New-Item -ItemType Directory -Path $script:ImportDir -Force | Out-Null

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

                $cache = Join-Path $script:ImportDir "manual-demo"
                Ensure-Repo $cache $zip "main" $null $true $false $false
                $expectedFingerprint = Get-DirectoryFingerprint $cache
                $expectedSkill = Get-Content -Raw (Join-Path $cache "SKILL.md")
                $lock = Save-LockData $cfg
                Remove-Item -LiteralPath $cache -Recurse -Force

                Mock Clear-SkillsCache {}

                Apply-LockToWorkspace $cfg $lock

                (Test-Path (Join-Path $cache "SKILL.md")) | Should Be $true
                (Get-DirectoryFingerprint $cache) | Should Be $expectedFingerprint
                (Get-Content -Raw (Join-Path $cache "SKILL.md")) | Should Be $expectedSkill
                { Assert-LockMatchesWorkspace $cfg $lock } | Should Not Throw
                Assert-MockCalled Clear-SkillsCache -Times 1 -Exactly
            }
            finally {
                $script:Root = $oldRoot
                $script:CfgPath = $oldCfgPath
                $script:VendorDir = $oldVendorDir
                $script:ImportDir = $oldImportDir
            }
        }

        It "Replays local zip imports without git checkout" {
            $oldImportDir = $script:ImportDir
            try {
                $script:ImportDir = Join-Path $TestDrive "imports-lock-zip-apply"
                $cache = Join-Path $script:ImportDir "manual-demo"
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

                $script:zipLockEnsureArgs | Should Not BeNullOrEmpty
                $script:zipLockEnsureArgs.forceClean | Should Be $true
                Assert-MockCalled Ensure-Repo -Times 1 -Exactly
                Assert-MockCalled Invoke-Git -Times 0 -Exactly
                Assert-MockCalled Clear-SkillsCache
            }
            finally {
                $script:ImportDir = $oldImportDir
            }
        }
    }
}
