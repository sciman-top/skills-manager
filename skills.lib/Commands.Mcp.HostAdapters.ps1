# MCP 宿主适配层：各宿主的 MCP 配置形状（config map / payload 构造）、
# codex node 缓存包装与宿主 MCP 配置文件名解析。从 Mcp.ps1 纯迁移
# （函数名与实现逐字不变）；解析/规划/事务/同步留在 Mcp.ps1。

function Convert-McpServersToConfigMap($servers) {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { [string]$s.transport }
        $entry.transport = $transport
        if ($transport -eq "stdio") {
            Assert-McpKeyValueMapSafe $s.env "env"
            Assert-McpProcessArgsSafe @($s.args) 'args'
            if (-not [string]::IsNullOrWhiteSpace([string]$s.command)) { $entry.command = [string]$s.command }
            if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $s.args -ne $null) { $entry.args = @($s.args) }
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) { $entry.env = $s.env }
        }
        else {
            Assert-McpRemoteUrl ([string]$s.url) ([string]$s.name) $transport
            Assert-McpKeyValueMapSafe $s.headers "header"
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) { $entry.url = [string]$s.url }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) { $entry.headers = $s.headers }
            if ($s.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.bearer_token_env_var)) {
                Need (Test-ValidEnvVarName ([string]$s.bearer_token_env_var)) ("bearer token 环境变量名非法：{0}" -f [string]$s.bearer_token_env_var)
                $entry.bearer_token_env_var = [string]$s.bearer_token_env_var
            }
        }
        $map[[string]$s.name] = [pscustomobject]$entry
    }
    return [pscustomobject]$map
}

function Convert-McpServersToGeminiConfigMap($servers) {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { ([string]$s.transport).Trim().ToLowerInvariant() }
        if ($transport -eq "stdio") {
            if (-not [string]::IsNullOrWhiteSpace([string]$s.command)) { $entry.command = [string]$s.command }
            if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $s.args -ne $null) { $entry.args = @($s.args) }
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) {
                foreach ($p in @($s.env.PSObject.Properties)) { Assert-McpHostValueNotEnvTemplate ([string]$s.name) 'env' ([string]$p.Name) ([string]$p.Value) }
                $entry.env = $s.env
            }
        }
        else {
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) {
                if ($transport -eq "http") { $entry.httpUrl = [string]$s.url }
                else { $entry.url = [string]$s.url }
            }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) {
                foreach ($p in @($s.headers.PSObject.Properties)) { Assert-McpHostValueNotEnvTemplate ([string]$s.name) 'headers' ([string]$p.Name) ([string]$p.Value) }
                $entry.headers = $s.headers
            }
        }
        $map[[string]$s.name] = [pscustomobject]$entry
    }
    return [pscustomobject]$map
}

function Get-CodexMcpStartupTimeoutSec($server) {
    if ($null -eq $server) { return $null }
    if ($server.PSObject.Properties.Match("startup_timeout_sec").Count -eq 0) { return $null }

    $raw = $server.startup_timeout_sec
    if ($null -eq $raw -or [string]::IsNullOrWhiteSpace([string]$raw)) { return $null }

    $parsed = 0
    if (-not [int]::TryParse([string]$raw, [ref]$parsed) -or $parsed -lt 1) {
        Log ("mcp_server.startup_timeout_sec 无效，已忽略：{0}" -f [string]$server.name) "WARN"
        return $null
    }
    return [int]$parsed
}

function Get-CodexNpxPackageName([string]$spec) {
    if ([string]::IsNullOrWhiteSpace($spec)) { return "" }
    $text = $spec.Trim()
    if ($text.StartsWith("@")) {
        $versionAt = $text.IndexOf("@", 1)
        if ($versionAt -gt 0) { return $text.Substring(0, $versionAt) }
        return $text
    }

    $plainVersionAt = $text.IndexOf("@")
    if ($plainVersionAt -gt 0) { return $text.Substring(0, $plainVersionAt) }
    return $text
}

function Get-CodexNpxWrapperBinRel([string]$packageName) {
    switch -Exact ($packageName) {
        "@upstash/context7-mcp" { return "dist/index.js" }
        "@modelcontextprotocol/server-filesystem" { return "dist/index.js" }
        "@playwright/mcp" { return "cli.js" }
        default { return "" }
    }
}

function Get-CodexMcpScriptsRoot([string]$CodexRoot = '') {
    $root = if ([string]::IsNullOrWhiteSpace($CodexRoot)) {
        Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex"
    }
    else {
        [IO.Path]::GetFullPath($CodexRoot)
    }
    return (Join-Path $root 'scripts')
}

function Convert-CodexNpxServerToCachedNodeWrapper($server, [string]$CodexRoot = '') {
    if ($null -eq $server) { return $null }
    if (-not [string]::Equals([string]$server.command, "npx", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $args = @()
    if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $server.args -ne $null) {
        $args = @($server.args | ForEach-Object { [string]$_ })
    }
    $packageIndex = -1
    for ($i = 0; $i -lt $args.Count; $i++) {
        if (-not ([string]$args[$i]).StartsWith("-")) {
            $packageIndex = $i
            break
        }
    }
    if ($packageIndex -lt 0) { return $null }

    $packageSpec = ([string]$args[$packageIndex]).Trim()
    $packageName = Get-CodexNpxPackageName $packageSpec
    $binRel = Get-CodexNpxWrapperBinRel $packageName
    if ([string]::IsNullOrWhiteSpace($packageName) -or [string]::IsNullOrWhiteSpace($binRel)) {
        return $null
    }

    $extraArgs = @()
    if ($packageIndex + 1 -lt $args.Count) {
        $extraArgs = @($args[($packageIndex + 1)..($args.Count - 1)])
    }
    $wrapperPath = Join-Path (Get-CodexMcpScriptsRoot $CodexRoot) "mcp-node-cache-wrapper.mjs"
    $entry = [ordered]@{
        command = "node"
        args = @($wrapperPath, $packageSpec, $binRel) + @($extraArgs)
    }
    if ($server.PSObject.Properties.Match("env").Count -gt 0 -and $server.env -ne $null) { $entry.env = $server.env }
    return [pscustomobject]$entry
}

function Convert-CodexPostgresServerToCachedNodeWrapper($server, [string]$CodexRoot = '') {
    if ($null -eq $server) { return $null }
    if (-not (Test-McpServerUsesPostgresConnectionString $server)) { return $null }

    $wrapperPath = Join-Path (Get-CodexMcpScriptsRoot $CodexRoot) "mcp-postgres-env-wrapper.mjs"
    $entry = [ordered]@{
        command = "node"
        args = @($wrapperPath)
    }
    if ($server.PSObject.Properties.Match("env").Count -gt 0 -and $server.env -ne $null) { $entry.env = $server.env }
    return [pscustomobject]$entry
}

function Test-CodexMcpKnownTaskkillStdoutLeak($server) {
    if ($null -eq $server) { return $false }
    if (-not [string]::Equals([string]$server.command, "npx", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    $args = @()
    if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $server.args -ne $null) {
        $args = @($server.args | ForEach-Object { [string]$_ })
    }
    foreach ($arg in $args) {
        if (([string]$arg).StartsWith("-")) { continue }
        $packageName = Get-CodexNpxPackageName ([string]$arg)
        return @(
            "@upstash/context7-mcp",
            "@modelcontextprotocol/server-filesystem",
            "@playwright/mcp"
        ) -contains $packageName
    }
    return $false
}

function Should-IncludeCodexMcpKnownTaskkillStdoutLeak {
    $raw = [string]$env:SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP
    return @("1", "true", "yes", "on") -contains $raw.Trim().ToLowerInvariant()
}

function Should-SkipCodexMcpKnownTaskkillStdoutLeak($server) {
    if (-not (Test-CodexMcpKnownTaskkillStdoutLeak $server)) { return $false }
    if (Should-IncludeCodexMcpKnownTaskkillStdoutLeak) { return $false }

    # These servers are written through mcp-node-cache-wrapper.mjs below. The
    # wrapper launches the cached package entrypoint directly, so the historical
    # Windows npx/taskkill stdout leak no longer applies to the Codex projection.
    if ($null -ne (Convert-CodexNpxServerToCachedNodeWrapper $server)) { return $false }
    return $true
}

function Convert-McpServersToCodexConfigMap($servers, [string]$CodexRoot = '') {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        if (Should-SkipCodexMcpKnownTaskkillStdoutLeak $s) {
            continue
        }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { [string]$s.transport }
        # Codex infers the transport from `command` (stdio) vs `url` (http) and does
        # not recognise an explicit `transport` key: `codex --strict-config` fails
        # closed with "unknown configuration field mcp_servers.<name>.transport",
        # and non-strict sessions log "unrecognized configuration setting ... is
        # ignored" once per server. `$transport` is kept for branching only.
        if ($transport -eq "stdio") {
            $wrapped = Convert-CodexPostgresServerToCachedNodeWrapper $s $CodexRoot
            if ($null -eq $wrapped) {
                $wrapped = Convert-CodexNpxServerToCachedNodeWrapper $s $CodexRoot
            }
            if ($null -ne $wrapped) {
                foreach ($prop in $wrapped.PSObject.Properties) { $entry[[string]$prop.Name] = $prop.Value }
            }
            else {
                if (-not [string]::IsNullOrWhiteSpace([string]$s.command)) { $entry.command = [string]$s.command }
                if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $s.args -ne $null) { $entry.args = @($s.args) }
                if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) { $entry.env = $s.env }
            }
        }
        else {
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) { $entry.url = [string]$s.url }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) { $entry.headers = $s.headers }
            if ($s.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.bearer_token_env_var)) {
                $entry.bearer_token_env_var = [string]$s.bearer_token_env_var
            }
        }

        if ($s.PSObject.Properties.Match("enabled").Count -gt 0) {
            Need ($s.enabled -is [bool]) ("mcp_server.enabled 必须是布尔值：{0}" -f [string]$s.name)
            $entry.enabled = [bool]$s.enabled
        }
        if ($s.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $s.enabled_tools) {
            $tools = @()
            foreach ($rawTool in @($s.enabled_tools)) {
                $tool = ([string]$rawTool).Trim()
                Need (-not [string]::IsNullOrWhiteSpace($tool)) ("mcp_server.enabled_tools 不得包含空值：{0}" -f [string]$s.name)
                Need (-not ($tool.Contains("`r") -or $tool.Contains("`n"))) ("mcp_server.enabled_tools 不得包含换行：{0}" -f [string]$s.name)
                if ($tools -notcontains $tool) { $tools += $tool }
            }
            $entry.enabled_tools = @($tools)
        }

        $startupTimeoutSec = Get-CodexMcpStartupTimeoutSec $s
        if ($null -ne $startupTimeoutSec) {
            $entry.startup_timeout_sec = [int]$startupTimeoutSec
        }

        $map[[string]$s.name] = [pscustomobject]$entry
    }
    return [pscustomobject]$map
}

function Get-CodexMcpNodeCacheWrapperContent {
    return @'
#!/usr/bin/env node
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [packageSpec, binRel, ...extraArgs] = process.argv.slice(2);
if (!packageSpec || !binRel) {
  console.error("usage: mcp-node-cache-wrapper.mjs <packageSpec> <binRel> [args...]");
  process.exit(64);
}

function parsePackageSpec(spec) {
  const versionAt = spec.startsWith("@") ? spec.indexOf("@", 1) : spec.indexOf("@");
  if (versionAt <= 0) return { packageName: spec, packageVersion: "" };
  return {
    packageName: spec.slice(0, versionAt),
    packageVersion: spec.slice(versionAt + 1),
  };
}

const { packageName, packageVersion } = parsePackageSpec(packageSpec.trim());
if (!packageName || (packageSpec.includes("@", 1) && !packageVersion)) {
  console.error(`Invalid npm package selector: ${packageSpec}`);
  process.exit(64);
}

const npmCache = process.env.npm_config_cache || join(process.env.LOCALAPPDATA || "", "npm-cache");
const npxRoot = join(npmCache, "_npx");
let entry = "";
if (existsSync(npxRoot)) {
  for (const item of readdirSync(npxRoot, { withFileTypes: true })) {
    if (!item.isDirectory()) continue;
    const packageRoot = join(npxRoot, item.name, "node_modules", ...packageName.split("/"));
    const candidate = join(packageRoot, ...binRel.split("/"));
    if (!existsSync(candidate)) continue;
    if (packageVersion) {
      try {
        const manifest = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"));
        if (manifest.version !== packageVersion) continue;
      } catch {
        continue;
      }
    }
    entry = candidate;
    break;
  }
}

if (!entry) {
  console.error(`Cached ${packageSpec} package was not found. Run npx for this MCP once to populate the npm cache.`);
  process.exit(69);
}

process.argv = [process.argv[0], entry, ...extraArgs];
await import(pathToFileURL(entry).href);
'@
}

function Get-CodexMcpPostgresEnvWrapperContent {
    return @'
#!/usr/bin/env node
import { existsSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

function readWindowsEnvironmentVariable(name, scope) {
  if (process.platform !== "win32") return "";
  try {
    return execFileSync(
      "pwsh.exe",
      [
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        `[Environment]::GetEnvironmentVariable('${name}', '${scope}')`,
      ],
      { encoding: "utf8", windowsHide: true, stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
  } catch {
    return "";
  }
}

function resolveEnvironmentVariable(name) {
  const processValue = process.env[name];
  if (processValue && processValue.trim()) return processValue.trim();
  for (const scope of ["User", "Machine"]) {
    const scopedValue = readWindowsEnvironmentVariable(name, scope);
    if (scopedValue && scopedValue.trim()) return scopedValue.trim();
  }
  return "";
}

function normalizePostgresConnectionString(raw) {
  const value = (raw || "").trim();
  if (/^postgres(?:ql)?:\/\//i.test(value)) return value;
  const fields = new Map();
  for (const part of value.split(";")) {
    const separator = part.indexOf("=");
    if (separator < 1) continue;
    fields.set(part.slice(0, separator).trim().toLowerCase(), part.slice(separator + 1).trim());
  }
  const host = fields.get("host") || "";
  const port = fields.get("port") || "";
  const database = fields.get("database") || "";
  const username = fields.get("username") || fields.get("user id") || fields.get("userid") || "";
  const password = fields.get("password") || "";
  if (![host, port, database, username, password].every(Boolean)) return "";
  return `postgresql://${encodeURIComponent(username)}:${encodeURIComponent(password)}@${host}:${port}/${encodeURIComponent(database)}`;
}

const conn = normalizePostgresConnectionString(resolveEnvironmentVariable("POSTGRES_CONNECTION_STRING"));
if (!conn) {
  console.error("POSTGRES_CONNECTION_STRING is required for postgres MCP.");
  process.exit(64);
}

function inferUserHomeFromWrapperPath() {
  try {
    return dirname(dirname(dirname(fileURLToPath(import.meta.url))));
  } catch {
    return "";
  }
}

const inferredUserHome = inferUserHomeFromWrapperPath();
const localAppData = resolveEnvironmentVariable("LOCALAPPDATA") || (inferredUserHome ? join(inferredUserHome, "AppData", "Local") : "");
const npmCache = process.env.npm_config_cache || join(localAppData || "", "npm-cache");
const npxRoot = join(npmCache, "_npx");
let entry = "";
if (existsSync(npxRoot)) {
  for (const item of readdirSync(npxRoot, { withFileTypes: true })) {
    if (!item.isDirectory()) continue;
    const candidate = join(
      npxRoot,
      item.name,
      "node_modules",
      "@modelcontextprotocol",
      "server-postgres",
      "dist",
      "index.js",
    );
    if (existsSync(candidate)) {
      entry = candidate;
      break;
    }
  }
}

if (!entry) {
  console.error("Cached @modelcontextprotocol/server-postgres package was not found. Run npx for this MCP once to populate the npm cache.");
  process.exit(69);
}

process.argv = [process.argv[0], entry, conn];
await import(pathToFileURL(entry).href);
'@
}

function Ensure-CodexMcpNodeCacheWrapper([string]$codexRoot) {
    if ([string]::IsNullOrWhiteSpace($codexRoot)) { return }
    $scriptsDir = Join-Path $codexRoot "scripts"
    EnsureDir $scriptsDir
    $wrapperPath = Join-Path $scriptsDir "mcp-node-cache-wrapper.mjs"
    Write-Utf8FileAtomic -Path $wrapperPath -Content (Get-CodexMcpNodeCacheWrapperContent)
    $postgresWrapperPath = Join-Path $scriptsDir "mcp-postgres-env-wrapper.mjs"
    Write-Utf8FileAtomic -Path $postgresWrapperPath -Content (Get-CodexMcpPostgresEnvWrapperContent)
}

function Build-GenericMcpPayload([string]$existingContent, $servers) {
    $base = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($existingContent)) {
        try {
            $parsed = $existingContent | ConvertFrom-Json
            if ($parsed -ne $null) {
                foreach ($p in $parsed.PSObject.Properties) {
                    $base[[string]$p.Name] = $p.Value
                }
            }
        }
        catch {
            # Fail closed: the existing file holds host settings beyond MCP
            # (model/theme/auth references). Rebuilding a minimal payload here
            # would overwrite them; throwing lets the transaction snapshot
            # restore the original file instead.
            throw ("宿主 MCP 配置 JSON 解析失败，拒绝最小化重建以保护既有内容：{0}" -f $_.Exception.Message)
        }
    }

    $managedMap = Convert-McpServersToConfigMap $servers
    # MCP 同步以 skills.json 为唯一真源，避免卸载后残留旧项。
    $base["mcpServers"] = $managedMap
    if ($base.Contains("mcp_servers")) { $base.Remove("mcp_servers") }
    return [pscustomobject]$base
}

function Build-ZCodeMcpPayload([string]$existingContent, $servers) {
    $base = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($existingContent)) {
        try {
            $parsed = $existingContent | ConvertFrom-Json
            if ($null -ne $parsed) {
                foreach ($property in $parsed.PSObject.Properties) { $base[[string]$property.Name] = $property.Value }
            }
        }
        catch {
            throw ("ZCode 宿主配置 JSON 解析失败，拒绝最小化重建以保护既有内容：{0}" -f $_.Exception.Message)
        }
    }

    $mcp = [ordered]@{}
    $existingMcp = if ($base.Contains('mcp')) { $base['mcp'] } else { $null }
    if ($null -ne $existingMcp) {
        foreach ($property in $existingMcp.PSObject.Properties) { $mcp[[string]$property.Name] = $property.Value }
    }
    $mcp['servers'] = Convert-McpServersToConfigMap $servers
    $base['mcp'] = [pscustomobject]$mcp
    return [pscustomobject]$base
}

function Get-NativeMcpKeyValueFlags($data, [string]$flagName, [string]$separator = "=") {
    $flags = @()
    if ($null -eq $data) { return $flags }

    if ($data -is [hashtable] -or $data -is [System.Collections.IDictionary]) {
        foreach ($k in $data.Keys) {
            $key = [string]$k
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $value = [string]$data[$k]
            $flags += @($flagName, ("{0}{1}{2}" -f $key, $separator, $value))
        }
        return $flags
    }

    if ($data -is [pscustomobject]) {
        foreach ($p in $data.PSObject.Properties) {
            $key = [string]$p.Name
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $value = [string]$p.Value
            $flags += @($flagName, ("{0}{1}{2}" -f $key, $separator, $value))
        }
        return $flags
    }

    return $flags
}

function Get-NativeMcpAddArgs($server, [string]$scope = "user") {
    Need ($null -ne $server) "MCP 服务不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$server.name)) "MCP 服务缺少 name"
    Need (($scope -eq "local") -or ($scope -eq "user")) ("不支持的 scope：{0}" -f $scope)

    $name = [string]$server.name
    $transport = if ([string]::IsNullOrWhiteSpace([string]$server.transport)) { "stdio" } else { [string]$server.transport }
    $transport = $transport.Trim().ToLowerInvariant()
    $args = @("mcp", "add", "--scope", $scope)

    if ($transport -eq "stdio") {
        $envFlags = @()
        if ($server.PSObject.Properties.Match("env").Count -gt 0) {
            $envFlags = Get-NativeMcpKeyValueFlags $server.env "-e"
        }
        if ($envFlags.Count -gt 0) { $args += $envFlags }
        $args += @($name, "--")
        $cmd = [string]$server.command
        Need (-not [string]::IsNullOrWhiteSpace($cmd)) ("stdio MCP 缺少 command：{0}" -f $name)
        $args += $cmd
        if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $server.args -ne $null) {
            $args += @($server.args | ForEach-Object { [string]$_ })
        }
        return $args
    }

    $headerFlags = @()
    if ($server.PSObject.Properties.Match("headers").Count -gt 0) {
        $headerFlags = Get-NativeMcpKeyValueFlags $server.headers "-H" ": "
    }
    $url = if ($server.PSObject.Properties.Match("url").Count -gt 0) { [string]$server.url } else { "" }
    Need (-not [string]::IsNullOrWhiteSpace($url)) ("{0} MCP 缺少 url：{1}" -f $transport, $name)
    $args += @("--transport", $transport, $name, $url)
    # `claude mcp add --header` is variadic and consumes trailing tokens, so headers must
    # be appended after <name> <url>.
    if ($headerFlags.Count -gt 0) { $args += $headerFlags }
    return $args
}

function Get-McpGenericConfigFileName([string]$Root) {
    # WorkBuddy resolves its MCP file as "<configDir>/mcp.json" (no dot prefix):
    # its own resolveWorkbuddyConfigDir() is WORKBUDDY_CONFIG_DIR || CODEBUDDY_CONFIG_DIR
    # || ~/<dataFolderName> (default ".workbuddy"), and getMcpConfigPath() joins the bare
    # name "mcp.json". A dot-prefixed ".mcp.json" is never read there, so the generic
    # default would create a file the host ignores and the sync would silently no-op.
    if ([string]::IsNullOrWhiteSpace($Root)) { return '.mcp.json' }
    $leaf = Split-Path $Root -Leaf
    if ($leaf -in @('.workbuddy', '.workbuddy-ai')) { return 'mcp.json' }
    foreach ($envName in @('WORKBUDDY_CONFIG_DIR', 'CODEBUDDY_CONFIG_DIR')) {
        $envDir = [Environment]::GetEnvironmentVariable($envName)
        if ([string]::IsNullOrWhiteSpace($envDir)) { continue }
        if ((Normalize-OperationPathKey $envDir) -eq (Normalize-OperationPathKey $Root)) { return 'mcp.json' }
    }
    return '.mcp.json'
}

# --- 宿主 MCP 配置文件形状与目标根解析（从 Mcp.ps1 纯迁移） ---

function Build-GeminiSettingsPayload([string]$existingContent, $servers) {
    $base = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($existingContent)) {
        try {
            $parsed = $existingContent | ConvertFrom-Json
            if ($parsed -ne $null) {
                foreach ($p in $parsed.PSObject.Properties) {
                    $base[[string]$p.Name] = $p.Value
                }
            }
        }
        catch {
            throw ("Gemini settings.json 解析失败，拒绝最小化重建以保护既有内容：{0}" -f $_.Exception.Message)
        }
    }

    $managedMap = Convert-McpServersToGeminiConfigMap $servers
    # Gemini 同步以 skills.json 为唯一真源，避免卸载后残留旧项。
    $base["mcpServers"] = $managedMap
    if ($base.Contains("mcp_servers")) { $base.Remove("mcp_servers") }
    return [pscustomobject]$base
}

function ConvertTo-TomlBasicValue($value) {
    if ($null -eq $value) { return '""' }
    if ($value -is [bool]) { return ($(if ($value) { "true" } else { "false" })) }
    if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) { return [string]$value }
    $text = [string]$value
    $text = $text.Replace("\", "\\").Replace('"', '\"')
    return ('"{0}"' -f $text)
}

function Test-TomlBareKey([string]$key) {
    return $key -cmatch '^[A-Za-z0-9_-]+$'
}

function ConvertTo-TomlKey([string]$key) {
    if (Test-TomlBareKey $key) { return $key }
    return ('"{0}"' -f $key.Replace('\', '\\').Replace('"', '\"'))
}

function Assert-McpHostValueNotEnvTemplate([string]$ServerName, [string]$FieldName, [string]$Key, [string]$Value) {
    # Codex config.toml 与 Gemini settings.json 不做 ${VAR} 展开：模板值会按字面量传给服务进程。
    if ($Value -match '^\s*(?:(?:Bearer|Basic)\s+)?\$\{[A-Za-z_][A-Za-z0-9_]*\}\s*$') {
        Need $false ('宿主不支持 ${{VAR}} 环境展开（会按字面量传递导致认证失败），拒绝投影：{0} {1}.{2}' -f $ServerName, $FieldName, $Key)
    }
}

function Build-CodexConfigToml([string]$existingToml, $servers, [string]$CodexRoot = '') {
    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($existingToml)) {
        $lines = $existingToml -split "`r?`n"
    }
    $codexServers = @()
    $skippedGithubForMissingToken = $false
    $hasGithubToken = -not [string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)
    # plan/DRYRUN 是只读命令：不向当前进程复制 token 环境变量。
    if (-not $DryRun -and [string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)) {
        $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = [string]$env:GITHUB_PERSONAL_ACCESS_TOKEN
    }
    foreach ($server in @($servers)) {
        if ($null -eq $server) { continue }
        if ([string]::Equals([string]$server.name, "github", [System.StringComparison]::OrdinalIgnoreCase)) {
            $hasEnabled = $server.PSObject.Properties.Match("enabled").Count -gt 0
            if ($hasEnabled) {
                Need ($server.enabled -is [bool]) "mcp_server.enabled 必须是布尔值：github"
            }
            $isExplicitlyDisabled = $hasEnabled -and -not [bool]$server.enabled
            if (-not $hasGithubToken -and -not $isExplicitlyDisabled) {
                Log "Codex 检测到 GitHub MCP 但缺少 CODEX_GITHUB_PERSONAL_ACCESS_TOKEN（或 GITHUB_PERSONAL_ACCESS_TOKEN），已跳过同步以避免影响启动。" "WARN"
                $skippedGithubForMissingToken = $true
                continue
            }
            if ($hasGithubToken) {
                Log "Codex 检测到 GitHub MCP 且存在 Token，将写入 bearer_token_env_var=CODEX_GITHUB_PERSONAL_ACCESS_TOKEN。" "INFO"
            }
            else {
                Log "Codex 检测到 GitHub MCP 已显式停用；缺少 Token 时仍保留停用配置。" "INFO"
            }
            $normalizedGithub = [ordered]@{
                name = [string]$server.name
                transport = if ([string]::IsNullOrWhiteSpace([string]$server.transport)) { "http" } else { [string]$server.transport }
                url = [string]$server.url
                bearer_token_env_var = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"
            }
            if ($hasEnabled) {
                $normalizedGithub.enabled = [bool]$server.enabled
            }
            if ($server.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $server.enabled_tools) {
                $normalizedGithub.enabled_tools = @($server.enabled_tools)
            }
            $codexServers += [pscustomobject]$normalizedGithub
            continue
        }
        $codexServers += $server
    }

    $managedMap = Convert-McpServersToCodexConfigMap $codexServers $CodexRoot
    $managedNames = @($managedMap.PSObject.Properties.Name | Sort-Object)
    # Ownership basis: only names declared here own a section. A section the host
    # owns (node_repl) or one that is not declared at all is preserved verbatim --
    # dropping undeclared sections by omission silently deleted host configuration.
    $managedNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($managedName in $managedNames) { $managedNameSet.Add([string]$managedName) | Out-Null }
    $preserveExistingMcpSections = ($managedNames.Count -eq 0 -and $skippedGithubForMissingToken)

    $kept = New-Object System.Collections.Generic.List[string]
    if ($preserveExistingMcpSections) {
        foreach ($line in $lines) {
            $kept.Add($line) | Out-Null
        }
    }
    else {
        $skipMcpSection = $false
        $hostOwnedMcpNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $hostOwnedMcpNames.Add("node_repl") | Out-Null
        foreach ($line in $lines) {
            if ($line -match '^\s*\[mcp_servers\.([^\.\]]+)(?:\.[^\]]+)?\]\s*(?:#.*)?$') {
                $serverName = [string]$Matches[1]
                $skipMcpSection = $managedNameSet.Contains($serverName) -and -not $hostOwnedMcpNames.Contains($serverName)
                if (-not $skipMcpSection) {
                    $kept.Add($line) | Out-Null
                }
                continue
            }

            if ($skipMcpSection -and $line -match '^\s*\[[^\]]+\]\s*(?:#.*)?$') {
                $skipMcpSection = $false
                $kept.Add($line) | Out-Null
                continue
            }

            if (-not $skipMcpSection) {
                $kept.Add($line) | Out-Null
            }
        }
    }

    while ($kept.Count -gt 0 -and [string]::IsNullOrWhiteSpace($kept[$kept.Count - 1])) {
        $kept.RemoveAt($kept.Count - 1)
    }

    $output = New-Object System.Collections.Generic.List[string]
    # MCP sync owns only MCP sections. Preserve host-owned model, approval,
    # sandbox, feature, and every other non-MCP setting byte-for-byte.
    $output.AddRange([string[]]$kept.ToArray())

    if ($managedNames.Count -gt 0) {
        if ($output.Count -gt 0) { $output.Add("") | Out-Null }
        foreach ($name in $managedNames) {
            Need (Test-TomlBareKey $name) ("mcp_server 名不是合法的 Codex TOML bare key，拒绝写入 config.toml：{0}" -f $name)
            $entry = $managedMap.$name
            $output.Add(("[mcp_servers.{0}]" -f $name)) | Out-Null
            foreach ($prop in $entry.PSObject.Properties) {
                $key = [string]$prop.Name
                $val = $prop.Value
                if ($null -eq $val) { continue }
                if ($val -is [Array]) {
                    $arr = @($val | ForEach-Object { ConvertTo-TomlBasicValue $_ })
                    $output.Add(("{0} = [{1}]" -f (ConvertTo-TomlKey $key), ($arr -join ", "))) | Out-Null
                    continue
                }
                if ($val -is [hashtable] -or $val -is [System.Collections.IDictionary] -or $val -is [pscustomobject]) {
                    $dict = @{}
                    if ($val -is [pscustomobject]) {
                        foreach ($p in $val.PSObject.Properties) { $dict[[string]$p.Name] = $p.Value }
                    }
                    else {
                        foreach ($k in $val.Keys) { $dict[[string]$k] = $val[$k] }
                    }
                    foreach ($k in $dict.Keys) { Assert-McpHostValueNotEnvTemplate $name $key ([string]$k) ([string]$dict[$k]) }
                    $pairs = @($dict.Keys | Sort-Object | ForEach-Object { "{0} = {1}" -f (ConvertTo-TomlKey $_), (ConvertTo-TomlBasicValue $dict[$_]) })
                    $output.Add(("{0} = {{ {1} }}" -f $key, ($pairs -join ", "))) | Out-Null
                    continue
                }
                $output.Add(("{0} = {1}" -f (ConvertTo-TomlKey $key), (ConvertTo-TomlBasicValue $val))) | Out-Null
            }
            $output.Add("") | Out-Null
        }
        while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            $output.RemoveAt($output.Count - 1)
        }
    }

    return ($output -join "`r`n")
}

function Resolve-GeminiAntigravityRootsFromCandidates($paths) {
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $paths) { return @() }
    $token = ".gemini\antigravity"
    $tokenLower = $token.ToLowerInvariant()
    foreach ($p in $paths) {
        if ([string]::IsNullOrWhiteSpace([string]$p)) { continue }
        $norm = ([string]$p).Replace("/", "\")
        $lower = $norm.ToLowerInvariant()
        $searchStart = 0
        while ($searchStart -lt $lower.Length) {
            $idx = $lower.IndexOf($tokenLower, $searchStart)
            if ($idx -lt 0) { break }
            if ($idx -gt 0 -and $norm[$idx - 1] -ne '\') {
                $searchStart = $idx + 1
                continue
            }
            $end = $idx + $token.Length
            # Require a directory boundary to avoid false matches like antigravity-backup.
            if ($end -lt $norm.Length -and $norm[$end] -ne '\') {
                $searchStart = $idx + 1
                continue
            }
            $root = $norm.Substring(0, $idx + $token.Length)
            if (-not [string]::IsNullOrWhiteSpace($root)) { $roots.Add($root) | Out-Null }
            $searchStart = $idx + $token.Length
        }
    }
    # 平铺返回：调用点统一以 @(...) 收集数组形状。单目逗号防展开与调用点
    # @() 叠加会再包一层嵌套（Count 恒 1），使空目标守卫恒真、多 root 期望
    # 集错乱、Gemini 多 root 参数绑定崩溃。
    return @($roots | Sort-Object)
}

function Get-TraeProjectMcpConfigPath([string]$repoRoot) {
    Need (-not [string]::IsNullOrWhiteSpace($repoRoot)) "repoRoot 不能为空"
    return (Join-Path (Join-Path $repoRoot ".trae") "mcp.json")
}

function Get-ZCodeMcpConfigPath([string]$zcodeRoot) {
    $root = [IO.Path]::GetFullPath($zcodeRoot).TrimEnd('\', '/')
    $userRoot = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('UserProfile')) '.zcode')).TrimEnd('\', '/')
    if ($root.Equals($userRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return (Join-Path $root 'cli\config.json')
    }
    return (Join-Path $root 'config.json')
}

function Get-McpTargetCandidatePaths($cfg) {
    $paths = New-Object System.Collections.Generic.List[string]
    if ($null -eq $cfg) { return @() }
    if ($cfg.PSObject.Properties.Match("mcp_targets").Count -gt 0 -and $cfg.mcp_targets -ne $null) {
        foreach ($mt in $cfg.mcp_targets) {
            if ($mt -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($mt)) { $paths.Add($mt) | Out-Null }
            }
            elseif ($mt.PSObject.Properties.Match("path").Count -gt 0) {
                $v = [string]$mt.path
                if (-not [string]::IsNullOrWhiteSpace($v)) { $paths.Add($v) | Out-Null }
            }
        }
    }
    foreach ($t in $cfg.targets) {
        if ($t.PSObject.Properties.Match("path").Count -gt 0) {
            $v = [string]$t.path
            if (-not [string]::IsNullOrWhiteSpace($v)) { $paths.Add($v) | Out-Null }
        }
    }
    $resolved = New-Object System.Collections.Generic.List[string]
    foreach ($path in $paths) {
        $r = Resolve-TargetDir $path
        if (-not [string]::IsNullOrWhiteSpace($r)) { $resolved.Add($r.Replace("/", "\")) | Out-Null }
    }
    return @($resolved)
}

function Resolve-McpTargetRootsFromCfg($cfg) {
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $cfg) { return @() }

    $candidates = Get-McpTargetCandidatePaths $cfg
    foreach ($path in $candidates) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $norm = $path.Replace("/", "\")
        $lower = $norm.ToLowerInvariant()

        $dotDirs = @(".claude", ".codex", ".gemini", ".trae", ".zcode")
        $matched = $false
        $bestIdx = -1
        $bestNeedleLen = 0
        foreach ($dotDir in $dotDirs) {
            $needle = "\" + $dotDir.ToLowerInvariant()
            $searchStart = 0
            while ($searchStart -lt $lower.Length) {
                $idx = $lower.IndexOf($needle, $searchStart)
                if ($idx -lt 0) { break }
                $end = $idx + $needle.Length
                # Require directory boundary so ".gemini_backup" does not match ".gemini".
                if ($end -lt $norm.Length -and $norm[$end] -ne '\') {
                    $searchStart = $idx + 1
                    continue
                }
                if ($bestIdx -lt 0 -or $idx -lt $bestIdx) {
                    $bestIdx = $idx
                    $bestNeedleLen = $needle.Length
                }
                $matched = $true
                break
            }
        }
        if ($matched -and $bestIdx -ge 0) {
            $root = $norm.Substring(0, $bestIdx + $bestNeedleLen)
            $roots.Add($root) | Out-Null
        }
        if ($matched) { continue }

        $leaf = Split-Path $norm -Leaf
        if ($leaf.Equals("skills", [System.StringComparison]::OrdinalIgnoreCase)) {
            $parent = Split-Path $norm -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent)) { $roots.Add($parent) | Out-Null }
            continue
        }

        $roots.Add($norm) | Out-Null
    }

    # 平铺返回：调用点统一以 @(...) 收集数组形状。单目逗号防展开与调用点
    # @() 叠加会再包一层嵌套（Count 恒 1），使空目标守卫恒真、多 root 期望
    # 集错乱、Gemini 多 root 参数绑定崩溃。
    return @($roots | Sort-Object)
}
