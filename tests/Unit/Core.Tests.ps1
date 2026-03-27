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
            $msg = @"
技能路径预检失败：--skill remotion-best-practices
未找到技能入口文件：E:\CODE\skills-manager\imports\_probe_xxx\remotion-best-practices
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
            $servers = @(
                [pscustomobject]@{
                    name      = "fetch"
                    transport = "stdio"
                    command   = "python"
                    args      = @("-m", "mcp_server_fetch")
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
            $toml | Should Not Match "\[mcp_servers\.old\]"
            $toml | Should Match "\[mcp_servers\.fetch\]"
            $toml | Should Match "command = ""python"""
            $toml | Should Match "args = \[""-m"", ""mcp_server_fetch""\]"
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
            $path = Get-TraeProjectMcpConfigPath "E:\CODE\skills-manager"
            $path | Should Be "E:\CODE\skills-manager\.trae\mcp.json"
        }
    }

    Context "Get-NativeMcpCleanupCommands" {
        It "Includes Claude user and local cleanup commands for removed server" {
            $cmds = Get-NativeMcpCleanupCommands "fetch"
            $serialized = $cmds | ForEach-Object { "$($_.command) $($_.args -join ' ')" }
            ($serialized -join "`n") | Should Match "claude mcp remove fetch --scope user"
            ($serialized -join "`n") | Should Match "claude mcp remove fetch"
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
                    mappings = @()
                }

                $migrated = Migrate-ManualToVendor $cfg "myvendor" "https://example.com/repo.git"
                $migrated | Should Be 1
                (Test-Path $manualLegacyDir) | Should Be $false
                @($cfg.imports | Where-Object { $_.name -eq "demo-manual" }).Count | Should Be 0
                @($cfg.imports | Where-Object { $_.name -eq "myvendor" -and $_.mode -eq "vendor" }).Count | Should Be 1
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
                    mappings = @()
                }

                $migrated = Migrate-ManualToVendor $cfg "myvendor" "https://example.com/repo.git"
                $migrated | Should Be 1
                @($cfg.imports | Where-Object { $_.name -eq "demo-manual" }).Count | Should Be 0
                @($cfg.imports | Where-Object { $_.name -eq "myvendor" -and $_.mode -eq "vendor" }).Count | Should Be 1
            }
            finally {
                $script:VendorDir = $oldVendorDir
                $script:ManualDir = $oldManualDir
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
    }
}
