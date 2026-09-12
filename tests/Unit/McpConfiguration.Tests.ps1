BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')
}

Describe 'MCP configuration and host transactions' {
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

    Context "Get-McpServerSignature" {
        It "Includes normalized startup_timeout_sec so manual edits move the fingerprint" {
            $server = [pscustomobject]@{ name = "api"; command = "npx"; args = @("-y", "mcp"); startup_timeout_sec = 45 }
            (Get-McpServerSignature $server) | Should -Match '"startup_timeout_sec":45'
            (Get-McpServerSignature ([pscustomobject]@{ name = "api"; command = "npx"; startup_timeout_sec = "not-a-number" })) | Should -Not -Match 'startup_timeout_sec'
            (Get-McpServerSignature ([pscustomobject]@{ name = "api"; command = "npx" })) | Should -Not -Match 'startup_timeout_sec'
        }
    }

    Context "Host env-template projection guard" {
        It "Refuses env template values for the Codex TOML host" {
            $server = [pscustomobject]@{ name = "api-gw"; command = "npx"; args = @("-y", "mcp"); env = [pscustomobject]@{ API_KEY = '${API_KEY}' } }
            { Build-CodexConfigToml "" @($server) } | Should -Throw '*环境展开*'
        }

        It "Refuses header template values for the Gemini host" {
            $server = [pscustomobject]@{ name = "gw"; transport = "http"; url = "https://example.com/mcp"; headers = [pscustomobject]@{ Authorization = 'Bearer ${TOK}' } }
            { Convert-McpServersToGeminiConfigMap @($server) } | Should -Throw '*环境展开*'
        }

        It "Does not copy the GITHUB token into process env under DryRun" {
            $oldCodex = [string]$env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN
            $oldGithub = [string]$env:GITHUB_PERSONAL_ACCESS_TOKEN
            try {
                Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
                $env:GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_test_dryrun_only"
                # 调用方作用域注入 DryRun：函数内的 $DryRun 读取沿动态作用域命中此处。
                & { $DryRun = $true; Build-CodexConfigToml "" @() | Out-Null }
                [string]$env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN | Should -Be ""
            }
            finally {
                if ($oldCodex) { $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $oldCodex } else { Remove-Item Env:\CODEX_GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue }
                if ($oldGithub) { $env:GITHUB_PERSONAL_ACCESS_TOKEN = $oldGithub } else { Remove-Item Env:\GITHUB_PERSONAL_ACCESS_TOKEN -ErrorAction SilentlyContinue }
            }
        }
    }

    Context "Build-CodexConfigToml" {
        It "Quotes TOML inline keys that are not bare keys" {
            $server = [pscustomobject]@{ name = "api-gw"; transport = "http"; url = "https://example.com/mcp"; headers = [pscustomobject]@{ "X.Custom" = "abc" } }
            $toml = Build-CodexConfigToml "" @($server)
            ($toml -join "`n") | Should -Match '"X\.Custom" = "abc"'
        }

        It "Refuses a managed server whose name is not a TOML bare key" {
            $server = [pscustomobject]@{ name = "a.b"; transport = "http"; url = "https://example.com/mcp" }
            { Build-CodexConfigToml "" @($server) } | Should -Throw '*bare key*'
        }

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
            $roots = @(Resolve-GeminiAntigravityRootsFromCandidates $paths)
            $roots.Count | Should -Be 1
            $roots[0] | Should -Be "C:\Users\sciman\.gemini\antigravity"
        }

        It "Ignores lookalike paths that are not antigravity directory" {
            $paths = @(
                "C:\Users\sciman\.gemini\antigravity-backup\skills",
                "C:\Users\sciman\.gemini\antigravity2\skills"
            )
            $roots = @(Resolve-GeminiAntigravityRootsFromCandidates $paths)
            @($roots).Count | Should -Be 0
        }

        It "Finds valid antigravity root even when an earlier lookalike appears in path" {
            $paths = @(
                "C:\tmp\.gemini\antigravity-backup\foo\.gemini\antigravity\skills"
            )
            $roots = @(Resolve-GeminiAntigravityRootsFromCandidates $paths)
            $roots.Count | Should -Be 1
            $roots[0] | Should -Be "C:\tmp\.gemini\antigravity-backup\foo\.gemini\antigravity"
        }

        It "Requires directory boundary before .gemini token" {
            $paths = @(
                "C:\tmp\foo.gemini\antigravity\skills"
            )
            $roots = @(Resolve-GeminiAntigravityRootsFromCandidates $paths)
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
            $roots = @(Resolve-McpTargetRootsFromCfg $cfg)
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
            $roots = @(Resolve-McpTargetRootsFromCfg $cfg)
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
            $roots = @(Resolve-McpTargetRootsFromCfg $cfg)
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
            $roots = @(Resolve-McpTargetRootsFromCfg $cfg)
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
            $roots = @(Resolve-McpTargetRootsFromCfg $cfg)
            $roots.Count | Should -Be 1
            $roots[0] | Should -Be (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".trae")
        }
    }

    It 'keeps the default MCP profile off and specialized profiles narrow' {
        $config = Get-ContentUtf8 (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json
        $profiles = $config.mcp_profiles.profiles

        @($profiles.default.enabled) | Should -Be @()
        @($profiles.coding.enabled) | Should -Be @('openaiDeveloperDocs')
        @($profiles.dotnet.enabled) | Should -Be @('microsoft-learn')
        @($profiles.coding.enabled_tools.openaiDeveloperDocs) | Should -Be @('search_openai_docs', 'fetch_openai_doc')
        @($profiles.dotnet.enabled_tools.'microsoft-learn') | Should -Be @('microsoft_docs_search', 'microsoft_docs_fetch', 'microsoft_code_sample_search')

        $codingConfig = $config | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $codingConfig.mcp_profiles.active = 'coding'
        $codingServers = @(Resolve-McpProfileServers $codingConfig)
        ($codingServers | Where-Object name -eq 'context7').enabled | Should -BeFalse
        ($codingServers | Where-Object name -eq 'openaiDeveloperDocs').enabled | Should -BeTrue
        @((($codingServers | Where-Object name -eq 'openaiDeveloperDocs').enabled_tools)) | Should -Be @('search_openai_docs', 'fetch_openai_doc')
    }
}
