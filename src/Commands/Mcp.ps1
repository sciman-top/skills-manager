function Parse-McpInstallArgs([string[]]$tokens) {
    Need ($tokens -and $tokens.Count -gt 0) "缺少 MCP 服务参数。示例：安装MCP context7 --cmd npx -- -y @upstash/context7-mcp"
    $result = [ordered]@{
        name = $null
        transport = "stdio"
        command = $null
        args = @()
        url = $null
        env = @{}
        headers = @{}
        bearer_token_env_var = $null
    }
    $collectProcessArgs = $false

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -eq "--") {
            if ($i + 1 -lt $tokens.Count) {
                $result.args += $tokens[($i + 1)..($tokens.Count - 1)]
            }
            break
        }

        if ($collectProcessArgs) {
            $result.args += $t
            continue
        }

        if (-not $t.StartsWith("-")) {
            if (-not $result.name) {
                $result.name = $t
                continue
            }
            # Backward compatible: allow "name <cmd> <args...>" without --cmd or "--".
            if ($result.transport -eq "stdio" -and [string]::IsNullOrWhiteSpace($result.command) -and [string]::IsNullOrWhiteSpace($result.url)) {
                $collectProcessArgs = $true
                $result.args += $t
                continue
            }
            $result.args += $t
            continue
        }

        $key = $t.ToLowerInvariant()
        if ($key -eq "--transport" -or $key -eq "-t") {
            Need ($i + 1 -lt $tokens.Count) ("参数缺少值：{0}" -f $t)
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) ("参数缺少值：{0}" -f $t)
            $result.transport = $nextVal
            continue
        }
        if ($key -eq "--cmd" -or $key -eq "--command") {
            Need ($i + 1 -lt $tokens.Count) ("参数缺少值：{0}" -f $t)
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) ("参数缺少值：{0}" -f $t)
            $result.command = $nextVal
            continue
        }
        if ($key -eq "--url") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--url"
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) "参数缺少值：--url"
            $result.url = $nextVal
            continue
        }
        if ($key -eq "--arg") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--arg"
            $result.args += $tokens[++$i]
            continue
        }
        if ($key.StartsWith("--arg=")) {
            $result.args += $t.Substring(6)
            continue
        }
        if ($key -eq "--env") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--env"
            $pair = Parse-KeyValueToken $tokens[++$i] "--env"
            $result.env[$pair.key] = $pair.value
            continue
        }
        if ($key -eq "--header") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--header"
            $pair = Parse-KeyValueToken $tokens[++$i] "--header"
            $result.headers[$pair.key] = $pair.value
            continue
        }
        if ($key -eq "--bearer-token-env-var") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--bearer-token-env-var"
            $result.bearer_token_env_var = [string]$tokens[++$i]
            continue
        }

        # Backward compatible: in stdio mode, unknown options are treated as process
        # arguments so users can omit "--" (PowerShell may swallow the separator).
        if (-not [string]::IsNullOrWhiteSpace($result.name) -and $result.transport -eq "stdio" -and [string]::IsNullOrWhiteSpace($result.url)) {
            if (-not [string]::IsNullOrWhiteSpace($result.command)) {
                $result.args += $t
                continue
            }
            $collectProcessArgs = $true
            $result.args += $t
            continue
        }
        throw ("未知参数：{0}" -f $t)
    }

    Need (-not [string]::IsNullOrWhiteSpace($result.name)) "缺少 MCP 服务名称。示例：安装MCP context7 --cmd npx -- -y @upstash/context7-mcp"

    if (-not [string]::IsNullOrWhiteSpace($result.transport)) {
        $result.transport = $result.transport.Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($result.transport)) { $result.transport = "stdio" }
    Need (($result.transport -eq "stdio") -or ($result.transport -eq "http")) "transport 仅支持 stdio/http；旧 SSE 已弃用"

    if ($result.transport -eq "stdio") {
        Assert-McpKeyValueMapSafe $result.env "--env"
        Assert-McpProcessArgsSafe $result.args '--args'
        if ([string]::IsNullOrWhiteSpace($result.command) -and $result.args.Count -gt 0) {
            $result.command = [string]$result.args[0]
            if ($result.args.Count -gt 1) {
                $result.args = $result.args[1..($result.args.Count - 1)]
            }
            else {
                $result.args = @()
            }
        }
        Need (-not [string]::IsNullOrWhiteSpace($result.command)) "stdio MCP 需要 --cmd/--command"
        if ($result.command.Contains(" ") -and $result.args.Count -eq 0) {
            $parts = Split-Args $result.command
            Need ($parts.Count -gt 0) "无法解析 --cmd 命令"
            $result.command = $parts[0]
            if ($parts.Count -gt 1) {
                $result.args = $parts[1..($parts.Count - 1)]
            }
        }
    }
    else {
        Assert-McpRemoteUrl ([string]$result.url) ([string]$result.name) ([string]$result.transport)
        Assert-McpKeyValueMapSafe $result.headers "--header"
        if (-not [string]::IsNullOrWhiteSpace([string]$result.bearer_token_env_var)) {
            $result.bearer_token_env_var = [string]$result.bearer_token_env_var.Trim()
            Need (Test-ValidEnvVarName $result.bearer_token_env_var) ("bearer token 环境变量名非法：{0}" -f $result.bearer_token_env_var)
        }
    }

    $fallbackSeed = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$result.command)) {
        $fallbackSeed = [string]$result.command
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$result.url)) {
        $fallbackSeed = [string]$result.url
    }
    $result.name = Normalize-McpServiceNameWithFallback $result.name $fallbackSeed

    return [pscustomobject]$result
}

function Extract-McpTrailingDryRunToken([string[]]$tokens) {
    $list = @($tokens)
    if ($list.Count -eq 0) {
        return [pscustomobject]@{
            tokens = @()
            dry_run = $false
        }
    }
    $last = [string]$list[$list.Count - 1]
    $tail = $last.Trim().ToLowerInvariant()
    if ($tail -eq "-dryrun" -or $tail -eq "--dryrun" -or $tail -eq "--dry-run") {
        $trimmed = @()
        if ($list.Count -gt 1) {
            $trimmed = @($list[0..($list.Count - 2)])
        }
        return [pscustomobject]@{
            tokens = $trimmed
            dry_run = $true
        }
    }
    return [pscustomobject]@{
        tokens = $list
        dry_run = $false
    }
}

function New-McpServerObject($parsed) {
    $obj = [ordered]@{
        name = $parsed.name
        transport = $parsed.transport
    }
    if ($parsed.transport -eq "stdio") {
        $obj.command = $parsed.command
        $obj.args = @($parsed.args)
        if ($parsed.env.Count -gt 0) { $obj.env = $parsed.env }
    }
    else {
        $obj.url = $parsed.url
        if ($parsed.headers.Count -gt 0) { $obj.headers = $parsed.headers }
        if (-not [string]::IsNullOrWhiteSpace([string]$parsed.bearer_token_env_var)) {
            $obj.bearer_token_env_var = [string]$parsed.bearer_token_env_var
        }
    }
    return [pscustomobject]$obj
}

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
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) { $entry.env = $s.env }
        }
        else {
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) {
                if ($transport -eq "http") { $entry.httpUrl = [string]$s.url }
                else { $entry.url = [string]$s.url }
            }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) { $entry.headers = $s.headers }
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

function Convert-CodexNpxServerToCachedNodeWrapper($server) {
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
    $wrapperPath = Join-Path (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex\scripts") "mcp-node-cache-wrapper.mjs"
    $entry = [ordered]@{
        transport = "stdio"
        command = "node"
        args = @($wrapperPath, $packageSpec, $binRel) + @($extraArgs)
    }
    if ($server.PSObject.Properties.Match("env").Count -gt 0 -and $server.env -ne $null) { $entry.env = $server.env }
    return [pscustomobject]$entry
}

function Convert-CodexPostgresServerToCachedNodeWrapper($server) {
    if ($null -eq $server) { return $null }
    if (-not (Test-McpServerUsesPostgresConnectionString $server)) { return $null }

    $wrapperPath = Join-Path (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex\scripts") "mcp-postgres-env-wrapper.mjs"
    $entry = [ordered]@{
        transport = "stdio"
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

function Convert-McpServersToCodexConfigMap($servers) {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        if (Should-SkipCodexMcpKnownTaskkillStdoutLeak $s) {
            continue
        }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { [string]$s.transport }
        $entry.transport = $transport
        if ($transport -eq "stdio") {
            $wrapped = Convert-CodexPostgresServerToCachedNodeWrapper $s
            if ($null -eq $wrapped) {
                $wrapped = Convert-CodexNpxServerToCachedNodeWrapper $s
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
            Log ("MCP JSON 解析失败，将使用最小配置重建：{0}" -f $_.Exception.Message) "WARN"
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
            Log ("ZCode MCP JSON 解析失败，将使用最小配置重建：{0}" -f $_.Exception.Message) "WARN"
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

function Remove-McpServersFromPayload($payload, [string[]]$names) {
    if ($null -eq $payload -or $null -eq $names -or $names.Count -eq 0) { return $payload }
    if ($payload.PSObject.Properties.Match("mcpServers").Count -eq 0) { return $payload }
    $serverMap = $payload.mcpServers
    if ($null -eq $serverMap) { return $payload }

    foreach ($name in @($names)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        $match = @($serverMap.PSObject.Properties | Where-Object {
            [string]::Equals([string]$_.Name, [string]$name, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if ($match.Count -gt 0 -and $null -ne $match[0]) {
            $serverMap.PSObject.Properties.Remove($match[0].Name)
        }
    }

    return $payload
}

function Get-LegacyMcpServersToPrune() {
    return @("fetch", "filesystem")
}

function Get-McpServersToPrune($servers) {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(Get-LegacyMcpServersToPrune)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        if (Has-McpServerByName $servers ([string]$name)) { continue }
        $names.Add([string]$name) | Out-Null
    }
    return @($names.ToArray())
}

function Has-McpServerByName($servers, [string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    foreach ($s in @($servers)) {
        if ($null -eq $s) { continue }
        if ([string]::Equals([string]$s.name, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-McpUserEnvironmentVariable([string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace($name)) "环境变量名不能为空"
    return [System.Environment]::GetEnvironmentVariable($name, "User")
}

function Get-EnvironmentVariableWithScope([string]$name, [string[]]$scopes = @("Process", "User", "Machine")) {
    Need (-not [string]::IsNullOrWhiteSpace($name)) "环境变量名不能为空"
    foreach ($scope in @($scopes)) {
        $value = if ([string]$scope -eq "User") { Get-McpUserEnvironmentVariable $name } else { [System.Environment]::GetEnvironmentVariable($name, $scope) }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return [pscustomobject]@{
                name = $name
                scope = [string]$scope
                value = [string]$value
            }
        }
    }
    return $null
}

function Convert-PostgresKeyValueConnectionStringToUrl([string]$connectionString) {
    if ([string]::IsNullOrWhiteSpace($connectionString)) { return $null }
    if ($connectionString -match '^\s*postgres(ql)?://') { return $connectionString.Trim() }
    if ($connectionString -notmatch '(?i)(^|;)Host\s*=') { return $null }

    $map = @{}
    foreach ($part in ($connectionString -split ';')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $pair = $part -split '=', 2
        if ($pair.Count -ne 2) { continue }
        $key = $pair[0].Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $map[$key] = $pair[1].Trim()
    }

    $hostValue = $map["host"]
    $portValue = $map["port"]
    $databaseValue = $map["database"]
    $userValue = $map["username"]
    if ([string]::IsNullOrWhiteSpace($userValue)) { $userValue = $map["user id"] }
    if ([string]::IsNullOrWhiteSpace($userValue)) { $userValue = $map["userid"] }
    $passwordValue = $map["password"]

    if ([string]::IsNullOrWhiteSpace($hostValue) -or
        [string]::IsNullOrWhiteSpace($portValue) -or
        [string]::IsNullOrWhiteSpace($databaseValue) -or
        [string]::IsNullOrWhiteSpace($userValue) -or
        [string]::IsNullOrWhiteSpace($passwordValue)) {
        return $null
    }

    return ("postgresql://{0}:{1}@{2}:{3}/{4}" -f
        [System.Uri]::EscapeDataString($userValue),
        [System.Uri]::EscapeDataString($passwordValue),
        $hostValue,
        $portValue,
        [System.Uri]::EscapeDataString($databaseValue))
}

function Test-McpServerUsesPostgresConnectionString($server) {
    if ($null -eq $server) { return $false }
    if ([string]::Equals([string]$server.name, "postgres", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $text = ""
    if ($server.PSObject.Properties.Match("command").Count -gt 0) { $text += " " + [string]$server.command }
    if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $null -ne $server.args) { $text += " " + (@($server.args) -join " ") }
    return ($text -match 'POSTGRES_CONNECTION_STRING' -or $text -match '@modelcontextprotocol/server-postgres')
}

function Ensure-PostgresMcpEnvironment($servers) {
    $needsPostgres = $false
    foreach ($server in @($servers)) {
        if (-not (Test-McpServerUsesPostgresConnectionString $server)) { continue }

        $hasEnabled = $server.PSObject.Properties.Match("enabled").Count -gt 0
        if ($hasEnabled) {
            Need ($server.enabled -is [bool]) ("mcp_server.enabled 必须是布尔值：{0}" -f [string]$server.name)
            if (-not [bool]$server.enabled) { continue }
        }

        $needsPostgres = $true
        break
    }
    if (-not $needsPostgres) { return }

    $resolved = Get-EnvironmentVariableWithScope "POSTGRES_CONNECTION_STRING"
    Need ($null -ne $resolved) "检测到 postgres MCP，但缺少 POSTGRES_CONNECTION_STRING。请先设置用户级 postgresql:// 连接串。"

    $raw = [string]$resolved.value
    $normalized = Convert-PostgresKeyValueConnectionStringToUrl $raw
    Need (-not [string]::IsNullOrWhiteSpace($normalized)) "检测到 postgres MCP，但 POSTGRES_CONNECTION_STRING 不是可用的 postgresql:// URL，也无法从 Host=...;Port=...;Database=...;Username=...;Password=... 形态转换。"

    # Keep normalization process-scoped. The wrapper also normalizes User/Machine
    # values at invocation time, so sync never persists a database credential.
    $env:POSTGRES_CONNECTION_STRING = $normalized
    if ($raw -ne $normalized -or [string]$resolved.scope -ne "Process") {
        Log ("Postgres MCP 连接串仅注入当前同步进程：source_scope={0}, shape=postgres-url" -f [string]$resolved.scope) "INFO"
    }
}

function Ensure-GhAuthForGithubMcp($servers) {
    $requiresAuthentication = $false
    foreach ($server in @($servers)) {
        if ($null -eq $server -or -not [string]::Equals([string]$server.name, "github", [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $hasEnabled = $server.PSObject.Properties.Match("enabled").Count -gt 0
        if ($hasEnabled) {
            Need ($server.enabled -is [bool]) "mcp_server.enabled 必须是布尔值：github"
            if (-not [bool]$server.enabled) { continue }
        }

        $requiresAuthentication = $true
        break
    }
    if (-not $requiresAuthentication) { return }

    $githubResolved = Get-EnvironmentVariableWithScope "GITHUB_PERSONAL_ACCESS_TOKEN"
    $codexResolved = Get-EnvironmentVariableWithScope "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"
    $githubToken = if ($null -eq $githubResolved) { "" } else { [string]$githubResolved.value }
    $codexToken = if ($null -eq $codexResolved) { "" } else { [string]$codexResolved.value }
    if (-not [string]::IsNullOrWhiteSpace($githubToken) -and
        -not [string]::IsNullOrWhiteSpace($codexToken) -and
        $githubToken -cne $codexToken) {
        throw "检测到 GitHub MCP，但 GITHUB_PERSONAL_ACCESS_TOKEN 与 CODEX_GITHUB_PERSONAL_ACCESS_TOKEN 不一致；请由操作者统一配置。"
    }
    $token = if (-not [string]::IsNullOrWhiteSpace($codexToken)) { $codexToken } else { $githubToken }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "检测到 github MCP，但未发现已由操作者配置的 token 环境变量。请设置 GITHUB_PERSONAL_ACCESS_TOKEN 或 CODEX_GITHUB_PERSONAL_ACCESS_TOKEN；不会从 gh credential store 自动复制凭据。"
    }

    # Hydrate only this sync process. User/Machine values remain untouched.
    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $token
    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $token
    $sourceScope = if ($null -ne $codexResolved) { [string]$codexResolved.scope } elseif ($null -ne $githubResolved) { [string]$githubResolved.scope } else { "Process" }
    Log ("GitHub MCP 凭据预检通过：source_scope={0}，仅注入当前同步进程。" -f $sourceScope) "INFO"
}

function Resolve-ExternalCommandInvocation([string]$command, [string[]]$commandArgs = @()) {
    Need (-not [string]::IsNullOrWhiteSpace($command)) "外部命令名不能为空"
    $resolved = @(Get-Command $command -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($resolved.Count -gt 0 -and $null -ne $resolved[0]) {
        $resolvedPath = [string]$resolved[0].Path
        if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            $ext = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
            if ($ext -eq ".ps1") {
                return [pscustomobject]@{
                    file = Resolve-PowerShellExecutable
                    args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedPath) + @($commandArgs)
                }
            }
            return [pscustomobject]@{
                file = $resolvedPath
                args = @($commandArgs)
            }
        }
    }

    return [pscustomobject]@{
        file = $command
        args = @($commandArgs)
    }
}

function Convert-ExternalCommandTextToCapturedOutput([string]$outText, [string]$errText) {
    $combined = New-Object System.Collections.Generic.List[string]
    foreach ($line in @((($outText + "`n" + $errText) -split "`r?`n"))) {
        if ($null -ne $line -and $line -ne "") { $combined.Add([string]$line) | Out-Null }
    }
    return [pscustomobject]@{
        output = @($combined)
        error = if ([string]::IsNullOrWhiteSpace($errText)) { "" } else { $errText.Trim() }
    }
}

function Invoke-ExternalCommandWithTimeout(
    [string]$command,
    [Alias("args")]
    [string[]]$CommandArgs = @(),
    [string]$workingDir = $null,
    [int]$timeoutSeconds = 30,
    [hashtable]$EnvironmentOverrides = $null
) {
    Need (-not [string]::IsNullOrWhiteSpace($command)) "外部命令名不能为空"
    if ($timeoutSeconds -lt 1) { $timeoutSeconds = 1 }

    $proc = $null
    $stdoutTask = $null
    $stderrTask = $null
    try {
        $effectiveWorkingDir = if ([string]::IsNullOrWhiteSpace($workingDir)) { $PWD.Path } else { $workingDir }
        $invocation = Resolve-ExternalCommandInvocation $command @($CommandArgs)
        $argList = @($invocation.args | ForEach-Object { [string]$_ })
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = [string]$invocation.file
        $startInfo.WorkingDirectory = $effectiveWorkingDir
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        if ($EnvironmentOverrides -ne $null) {
            foreach ($entry in $EnvironmentOverrides.GetEnumerator()) {
                $key = [string]$entry.Key
                if ([string]::IsNullOrWhiteSpace($key)) { continue }
                if ($null -eq $entry.Value) {
                    [void]$startInfo.Environment.Remove($key)
                    continue
                }
                $startInfo.Environment[$key] = [string]$entry.Value
            }
        }
        foreach ($arg in $argList) {
            [void]$startInfo.ArgumentList.Add([string]$arg)
        }

        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $startInfo
        [void]$proc.Start()
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $exited = $proc.WaitForExit($timeoutSeconds * 1000)
        if (-not $exited) {
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
            try { $proc.WaitForExit(2000) | Out-Null } catch {}
            $outText = if ($null -ne $stdoutTask) { [string]$stdoutTask.GetAwaiter().GetResult() } else { "" }
            $errText = if ($null -ne $stderrTask) { [string]$stderrTask.GetAwaiter().GetResult() } else { "" }
            $captured = Convert-ExternalCommandTextToCapturedOutput $outText $errText
            return [pscustomobject]@{
                timed_out = $true
                exit_code = 124
                output = @($captured.output)
                error = if ([string]::IsNullOrWhiteSpace([string]$captured.error)) { ("timeout_after_{0}s" -f $timeoutSeconds) } else { ("timeout_after_{0}s: {1}" -f $timeoutSeconds, [string]$captured.error) }
            }
        }

        try { $proc.WaitForExit() | Out-Null } catch {}
        $outText = if ($null -ne $stdoutTask) { [string]$stdoutTask.GetAwaiter().GetResult() } else { "" }
        $errText = if ($null -ne $stderrTask) { [string]$stderrTask.GetAwaiter().GetResult() } else { "" }
        $captured = Convert-ExternalCommandTextToCapturedOutput $outText $errText

        return [pscustomobject]@{
            timed_out = $false
            exit_code = [int]$proc.ExitCode
            output = @($captured.output)
            error = [string]$captured.error
        }
    }
    catch {
        return [pscustomobject]@{
            timed_out = $false
            exit_code = 1
            output = @()
            error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $proc) { $proc.Dispose() }
    }
}

function Resolve-TimeoutSecondsFromEnv([string]$envName, [int]$defaultSeconds, [int]$minSeconds = 1, [int]$maxSeconds = 600) {
    $value = $defaultSeconds
    if ([string]::IsNullOrWhiteSpace($envName)) { return $value }

    $raw = [System.Environment]::GetEnvironmentVariable($envName)
    $parsed = 0
    if ([int]::TryParse([string]$raw, [ref]$parsed)) {
        $value = $parsed
    }

    if ($value -lt $minSeconds) { $value = $minSeconds }
    if ($value -gt $maxSeconds) { $value = $maxSeconds }
    return $value
}

function Test-EnvFlagEnabled([string]$envName) {
    if ([string]::IsNullOrWhiteSpace($envName)) { return $false }
    $raw = [System.Environment]::GetEnvironmentVariable($envName)
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $false }
    $v = ([string]$raw).Trim().ToLowerInvariant()
    return ($v -eq "1" -or $v -eq "true" -or $v -eq "yes" -or $v -eq "on")
}

function Should-RunNativeMcpSync() {
    return (Test-EnvFlagEnabled "SKILLS_MCP_NATIVE_SYNC")
}

function Should-VerifyLiveMcpCli() {
    return (Test-EnvFlagEnabled "SKILLS_MCP_VERIFY_LIVE_CLI")
}

function Get-McpListVerifyTimeoutSeconds([string]$cli) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    $defaultSeconds = switch ($cliName) {
        "gemini" { 18 }
        "claude" { 45 }
        "codex" { 45 }
        default { 30 }
    }

    $globalTimeout = Resolve-TimeoutSecondsFromEnv "SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS" $defaultSeconds 1 600
    $envSuffix = if ([string]::IsNullOrWhiteSpace($cliName)) { "DEFAULT" } else { $cliName.ToUpperInvariant() }
    $perCliVar = "SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_{0}" -f $envSuffix
    return (Resolve-TimeoutSecondsFromEnv $perCliVar $globalTimeout 1 600)
}

function Should-VerifyGeminiCli() {
    return (Test-EnvFlagEnabled "SKILLS_MCP_VERIFY_GEMINI_CLI")
}

function Get-NativeMcpCommandTimeoutSeconds() {
    return (Resolve-TimeoutSecondsFromEnv "SKILLS_MCP_NATIVE_TIMEOUT_SECONDS" 30 1 600)
}

function Invoke-ExternalCommandCapture(
    [string]$command,
    [Alias("args")]
    [string[]]$CommandArgs = @(),
    [int]$timeoutSeconds = 120,
    [hashtable]$EnvironmentOverrides = $null,
    [string]$workingDir = $null
) {
    $result = Invoke-ExternalCommandWithTimeout $command @($CommandArgs) $workingDir $timeoutSeconds $EnvironmentOverrides
    return [pscustomobject]@{
        command = $command
        args = @($CommandArgs)
        exit_code = [int]$result.exit_code
        timed_out = [bool]$result.timed_out
        error = [string]$result.error
        output = @($result.output)
    }
}

function Get-McpCliProcessEnvOverrides([string]$cli) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($cliName)) { return $null }

    $varsToHydrate = switch ($cliName) {
        "gemini" { @("GITHUB_PERSONAL_ACCESS_TOKEN") }
        "claude" { @("GITHUB_PERSONAL_ACCESS_TOKEN") }
        "codex" { @("CODEX_GITHUB_PERSONAL_ACCESS_TOKEN") }
        default { @() }
    }
    if ($varsToHydrate.Count -eq 0) { return $null }

    $overrides = [ordered]@{}
    foreach ($varName in $varsToHydrate) {
        if ([string]::IsNullOrWhiteSpace($varName)) { continue }
        $processValue = [System.Environment]::GetEnvironmentVariable($varName, "Process")
        if (-not [string]::IsNullOrWhiteSpace([string]$processValue)) { continue }
        $userValue = Get-McpUserEnvironmentVariable $varName
        if (-not [string]::IsNullOrWhiteSpace([string]$userValue)) {
            $overrides[$varName] = [string]$userValue
        }
    }

    if ($overrides.Count -eq 0) { return $null }
    return $overrides
}

function Get-McpCliVerificationWorkingDir([string]$cli) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    switch ($cliName) {
        "gemini" {
            $userHome = [Environment]::GetFolderPath("UserProfile")
            if (-not [string]::IsNullOrWhiteSpace([string]$userHome) -and (Test-Path -LiteralPath $userHome)) {
                return [string]$userHome
            }
            return $null
        }
        default { return $null }
    }
}

function Get-McpServerNamesFromJsonText([string]$jsonText) {
    if ([string]::IsNullOrWhiteSpace($jsonText)) { return @() }
    try {
        $obj = $jsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        return @()
    }
    if ($null -eq $obj) { return @() }
    if ($obj.PSObject.Properties.Match("mcpServers").Count -eq 0 -or $null -eq $obj.mcpServers) {
        return @()
    }
    return @($obj.mcpServers.PSObject.Properties | ForEach-Object { [string]$_.Name })
}

function Get-CodexMcpServerNamesFromTomlText([string]$tomlText) {
    if ([string]::IsNullOrWhiteSpace($tomlText)) { return @() }
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @(($tomlText -split "`r?`n"))) {
        $m = [regex]::Match([string]$line, '^\s*\[mcp_servers\.([^\.\]\s]+)(?:\.[^\]]+)?\]\s*$')
        if ($m.Success) {
            $set.Add([string]$m.Groups[1].Value) | Out-Null
        }
    }
    return @($set | Sort-Object)
}

function Get-McpExpectedServersByCli($roots) {
    $expected = [ordered]@{
        claude = @()
        codex = @()
        gemini = @()
    }
    foreach ($root in @($roots)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $leaf = (Split-Path ([string]$root) -Leaf).ToLowerInvariant()
        if ($leaf -eq ".claude") {
            $mcpPath = Join-Path $root ".mcp.json"
            if (Test-Path $mcpPath) {
                $names = Get-McpServerNamesFromJsonText (Get-ContentUtf8 $mcpPath)
                if ($names.Count -gt 0) { $expected.claude += $names }
            }
            continue
        }
        if ($leaf -eq ".gemini") {
            $settingsPath = Join-Path $root "settings.json"
            if (Test-Path $settingsPath) {
                $names = Get-McpServerNamesFromJsonText (Get-ContentUtf8 $settingsPath)
                if ($names.Count -gt 0) { $expected.gemini += $names }
            }
            continue
        }
        if ($leaf -eq ".codex") {
            $cfgPath = Join-Path $root "config.toml"
            if (Test-Path $cfgPath) {
                $names = Get-CodexMcpServerNamesFromTomlText (Get-ContentUtf8 $cfgPath)
                if ($names.Count -gt 0) { $expected.codex += $names }
            }
            continue
        }
    }

    foreach ($k in @("claude", "codex", "gemini")) {
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in @($expected[$k])) {
            if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
            $set.Add([string]$name) | Out-Null
        }
        $expected[$k] = @($set | Sort-Object)
    }
    return [pscustomobject]$expected
}

function Remove-AnsiEscapeSequences([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $text }
    return ([regex]::Replace($text, '\x1B\[[0-9;?]*[ -/]*[@-~]', ''))
}

function Mask-SensitiveMcpCommandText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    $masked = [string]$text
    $masked = [regex]::Replace($masked, '(?i)(Authorization\s*[:=]\s*Bearer\s+)([^"\s]+)', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)\bgithub_pat_[A-Za-z0-9_]+\b', '<redacted>')
    $masked = [regex]::Replace($masked, '(?i)\bgh[pousr]_[A-Za-z0-9_]+\b', '<redacted>')
    $masked = [regex]::Replace($masked, '(?i)((?:--)?(?:token|secret|password|passwd|api[-_]?key|authorization)\s*(?:=|:)\s*)([^\s"'']+)', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)((?:--)?(?:token|secret|password|passwd|api[-_]?key|authorization)\s+)([^\s"'']+)', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)(https?://)([^/@\s:]+):([^/@\s]+)@', '$1<redacted>@')
    return $masked
}

function Test-IsNonInteractiveMcpError([string]$text) {
    if ([string]::IsNullOrWhiteSpace([string]$text)) { return $false }
    $normalized = ([string]$text).Trim()
    $hints = @(
        "stdout is not a terminal",
        "Input must be provided either through stdin",
        "No input provided via stdin",
        "when using --print"
    )
    foreach ($hint in $hints) {
        if ($normalized -like ("*{0}*" -f $hint)) { return $true }
    }
    return $false
}

function Test-IsNativeMcpAlreadyExistsError([string]$text, [string]$name) {
    if ([string]::IsNullOrWhiteSpace([string]$text) -or [string]::IsNullOrWhiteSpace([string]$name)) {
        return $false
    }
    $normalized = ([string]$text).Trim()
    $escapedName = [regex]::Escape([string]$name)
    return ($normalized -match ("(?i)\bMCP server\s+{0}\s+already exists\b" -f $escapedName))
}

function Test-CliMcpServerReady([string]$cli, [string[]]$expectedServers) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    $isGemini = ($cliName -eq "gemini")
    if ($null -eq $expectedServers -or $expectedServers.Count -eq 0) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "no_expected_servers"
            missing = @()
            raw = @()
        }
    }
    if ($isGemini -and -not (Should-VerifyGeminiCli)) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "gemini_cli_verification_skipped"
            missing = @()
            raw = @()
        }
    }
    if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
        if ($isGemini) {
            return [pscustomobject]@{
                cli = $cli
                ok = $true
                reason = "gemini_cli_not_found_fallback"
                missing = @()
                raw = @()
            }
        }
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = "cli_not_found"
            missing = @($expectedServers)
            raw = @()
        }
    }

    $listTimeoutSeconds = Get-McpListVerifyTimeoutSeconds $cli
    $envOverrides = Get-McpCliProcessEnvOverrides $cliName
    $listWorkingDir = Get-McpCliVerificationWorkingDir $cliName
    $result = Invoke-ExternalCommandCapture -command $cli -args @("mcp", "list") -timeoutSeconds $listTimeoutSeconds -EnvironmentOverrides $envOverrides -workingDir $listWorkingDir
    $raw = @($result.output | ForEach-Object { Remove-AnsiEscapeSequences ([string]$_) })
    if ($result.timed_out) {
        if ($isGemini) {
            return [pscustomobject]@{
                cli = $cli
                ok = $true
                reason = ("gemini_cli_timeout_fallback_{0}s" -f $listTimeoutSeconds)
                missing = @()
                raw = $raw
            }
        }
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = ("timeout_after_{0}s" -f $listTimeoutSeconds)
            missing = @($expectedServers)
            raw = $raw
        }
    }

    $missing = New-Object System.Collections.Generic.List[string]
    $joined = ($raw -join "`n")
    $trimmedJoined = $joined.Trim()
    $nonInteractiveHints = @(
        "stdout is not a terminal",
        "Input must be provided either through stdin",
        "No input provided via stdin"
    )
    $isNonInteractive = $false
    foreach ($hint in $nonInteractiveHints) {
        if ($trimmedJoined -like ("*{0}*" -f $hint)) {
            $isNonInteractive = $true
            break
        }
    }
    if ($isNonInteractive) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "non_interactive_tty_required_fallback"
            missing = @()
            raw = $raw
        }
    }
    if ($trimmedJoined.Length -eq 0 -and $cli -eq "gemini") {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = if ($result.exit_code -eq 0) { "ok_empty_output" } else { ("ok_empty_output_exit_{0}" -f $result.exit_code) }
            missing = @()
            raw = $raw
        }
    }
    if ($trimmedJoined.Length -eq 0) {
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = ("empty_output_exit_{0}" -f $result.exit_code)
            missing = @($expectedServers)
            raw = $raw
        }
    }
    foreach ($name in @($expectedServers)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        $pattern = "^\s*(?:[^\w\r\n]+\s*)?{0}\b" -f [regex]::Escape([string]$name)
        $line = @($raw | Where-Object { [regex]::IsMatch([string]$_, $pattern) } | Select-Object -First 1)
        if ($line.Count -eq 0) {
            $missing.Add([string]$name) | Out-Null
            continue
        }
        $lineText = [string]$line[0]
        if ($cli -eq "claude") {
            if ($lineText -notmatch "Connected") {
                $missing.Add([string]$name) | Out-Null
            }
            continue
        }
        if ($cli -eq "codex") {
            if ($lineText -match '\bdisabled\b') {
                $missing.Add([string]$name) | Out-Null
            }
            continue
        }
        if ($cli -eq "gemini") {
            # Some Gemini CLI versions print minimal/empty table output.
            # Fallback: when list output has no rows, verify names from settings.json already written.
            if ($trimmedJoined.Length -eq 0) {
                continue
            }
        }
    }

    $reason = if ($missing.Count -eq 0) {
        if ($result.exit_code -eq 0) { "ok" } else { ("ok_with_nonzero_exit_{0}" -f $result.exit_code) }
    } else {
        if ($result.exit_code -eq 0) { "missing_or_unhealthy" } else { ("missing_or_unhealthy_exit_{0}" -f $result.exit_code) }
    }
    return [pscustomobject]@{
        cli = $cli
        ok = ($missing.Count -eq 0)
        reason = $reason
        missing = @($missing)
        raw = $raw
    }
}

function Verify-McpAcrossCliWithRetry($roots, [int]$maxAttempts = 6, [int]$intervalSeconds = 3) {
    $expected = Get-McpExpectedServersByCli $roots
    $targets = @(
        [pscustomobject]@{ cli = "claude"; names = @($expected.claude) },
        [pscustomobject]@{ cli = "codex"; names = @($expected.codex) },
        [pscustomobject]@{ cli = "gemini"; names = @($expected.gemini) }
    ) | Where-Object { @($_.names).Count -gt 0 }

    if ($targets.Count -eq 0) {
        Log "未检测到需校验的 CLI MCP 目标，跳过跨 CLI 可用性校验。" "WARN"
        return
    }

    if (-not (Should-VerifyLiveMcpCli)) {
        foreach ($target in $targets) {
            Log ("MCP 配置态校验通过：{0} -> {1}" -f $target.cli, ((@($target.names)) -join ", "))
        }
        Log "跨 CLI MCP live 校验默认跳过；如需实机 mcp list 校验，设置 SKILLS_MCP_VERIFY_LIVE_CLI=1。" "INFO"
        return
    }

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $failed = New-Object System.Collections.Generic.List[object]
        foreach ($target in $targets) {
            $check = Test-CliMcpServerReady ([string]$target.cli) @($target.names)
            if ($check.ok) {
                Log ("MCP 校验通过：{0} -> {1}" -f $check.cli, ((@($target.names)) -join ", "))
            }
            else {
                $failed.Add($check) | Out-Null
                Log ("MCP 校验未通过：{0}，缺失/异常：{1}（reason={2}）" -f $check.cli, (($check.missing) -join ", "), $check.reason) "WARN"
                $snippet = @($check.raw | Select-Object -First 6) -join " | "
                if (-not [string]::IsNullOrWhiteSpace($snippet)) {
                    Log ("{0} mcp list 输出片段：{1}" -f $check.cli, (Mask-SensitiveMcpCommandText $snippet)) "WARN"
                }
            }
        }

        if ($failed.Count -eq 0) {
            Log ("跨 CLI MCP 校验完成：全部通过（attempt={0}/{1}）。" -f $attempt, $maxAttempts) "INFO"
            return
        }
        if ($attempt -lt $maxAttempts) {
            Log ("跨 CLI MCP 校验第 {0}/{1} 次未全部通过，{2}s 后自动重试。" -f $attempt, $maxAttempts, $intervalSeconds) "WARN"
            Start-Sleep -Seconds $intervalSeconds
        }
    }

    throw ("跨 CLI MCP 校验失败：在 {0} 次重试后仍存在不可用服务，请检查日志中的 CLI 与缺失项。" -f $maxAttempts)
}

function Invoke-NativeMcpSync($servers) {
    if (-not (Should-RunNativeMcpSync)) {
        Log "原生 Claude MCP 注册默认跳过；已写入配置文件。如需执行 claude mcp add/remove，设置 SKILLS_MCP_NATIVE_SYNC=1。" "INFO"
        return
    }
    if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
        Log "未检测到 claude 命令，已跳过原生 MCP 同步（仅写入 .mcp.json）。" "WARN"
        return
    }
    if ($script:SkipNativeMcpForSession) {
        Log "已检测到原生 MCP CLI 非交互不可用，本轮跳过后续原生 MCP 同步。" "WARN"
        return
    }
    if ($null -eq $servers -or $servers.Count -eq 0) {
        Log "当前 mcp_servers 为空，跳过原生 MCP 注册。" "WARN"
        return
    }

    foreach ($s in $servers) {
        $scope = "user"
        try {
            $args = Get-NativeMcpAddArgs $s $scope
            $cmdText = "claude {0}" -f (($args | ForEach-Object { [string]$_ }) -join " ")
            if ($DryRun) {
                $safeCmdText = Mask-SensitiveMcpCommandText $cmdText
                Write-Host ("DRYRUN：将执行原生 MCP 同步 -> {0}" -f $safeCmdText)
                continue
            }
            $timeoutSeconds = Get-NativeMcpCommandTimeoutSeconds
            $native = Invoke-ExternalCommandWithTimeout "claude" @($args) $script:Root $timeoutSeconds
            if ($native.timed_out) {
                Log ("原生 MCP 同步超时（已忽略）：{0}（scope={1}，timeout={2}s）" -f [string]$s.name, $scope, $timeoutSeconds) "WARN"
                continue
            }
            if ($native.exit_code -ne 0) {
                if (Test-IsNativeMcpAlreadyExistsError ([string]$native.error) ([string]$s.name)) {
                    Log ("原生 MCP 已存在，尝试替换：{0}（scope={1}）" -f [string]$s.name, $scope) "WARN"
                    $removeArgs = @("mcp", "remove", [string]$s.name, "--scope", $scope)
                    $removed = Invoke-ExternalCommandWithTimeout "claude" @($removeArgs) $script:Root $timeoutSeconds
                    if ($removed.timed_out -or $removed.exit_code -ne 0) {
                        Log ("原生 MCP 替换前清理失败（已忽略）：{0}（scope={1}，exit={2}）{3}" -f [string]$s.name, $scope, $removed.exit_code, (Mask-SensitiveMcpCommandText ([string]$removed.error))) "WARN"
                        continue
                    }

                    $native = Invoke-ExternalCommandWithTimeout "claude" @($args) $script:Root $timeoutSeconds
                    if (-not $native.timed_out -and $native.exit_code -eq 0) {
                        Log ("已替换原生 MCP：{0}（scope={1}）" -f [string]$s.name, $scope)
                        continue
                    }
                }
                Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}，exit={2}）{3}" -f [string]$s.name, $scope, $native.exit_code, (Mask-SensitiveMcpCommandText ([string]$native.error))) "WARN"
                if (Test-IsNonInteractiveMcpError ([string]$native.error)) {
                    $script:SkipNativeMcpForSession = $true
                    Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 同步。" "WARN"
                    break
                }
                continue
            }
            Log ("已同步原生 MCP：{0}（scope={1}）" -f [string]$s.name, $scope)
        }
        catch {
            Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}） -> {2}" -f [string]$s.name, $scope, (Mask-SensitiveMcpCommandText $_.Exception.Message)) "WARN"
            if (Test-IsNonInteractiveMcpError $_.Exception.Message) {
                $script:SkipNativeMcpForSession = $true
                Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 同步。" "WARN"
                break
            }
        }
    }
}

function Get-NativeMcpCleanupCommands([string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace($name)) "MCP 服务名不能为空"
    return @(
        [pscustomobject]@{ command = "claude"; args = @("mcp", "remove", $name, "--scope", "user"); project = $false }
        [pscustomobject]@{ command = "claude"; args = @("mcp", "remove", $name, "--scope", "project"); project = $true }
    )
}

function Invoke-NativeMcpCleanup([string]$name) {
    if (-not (Should-RunNativeMcpSync)) {
        Log ("原生 Claude MCP 清理默认跳过：{0}。如需执行 claude mcp remove，设置 SKILLS_MCP_NATIVE_SYNC=1。" -f $name) "INFO"
        return
    }
    if ($script:SkipNativeMcpForSession) {
        Log ("已检测到原生 MCP CLI 非交互不可用，跳过清理：{0}" -f $name) "WARN"
        return
    }
    $ops = Get-NativeMcpCleanupCommands $name
    foreach ($op in $ops) {
        if (-not (Get-Command $op.command -ErrorAction SilentlyContinue)) { continue }
        $cmdText = "{0} {1}" -f $op.command, (($op.args | ForEach-Object { [string]$_ }) -join " ")
        if ($DryRun) {
            Write-Host ("DRYRUN：清理原生 MCP -> {0}" -f $cmdText)
            continue
        }
        try {
            $timeoutSeconds = Get-NativeMcpCommandTimeoutSeconds
            $workingDir = if ($op.project) { $script:Root } else { $null }
            $native = Invoke-ExternalCommandWithTimeout ([string]$op.command) @($op.args) $workingDir $timeoutSeconds
            if ($native.timed_out) {
                Log ("原生 MCP 清理超时（已忽略）：{0}（timeout={1}s）" -f $cmdText, $timeoutSeconds) "WARN"
                continue
            }
            if ($native.exit_code -ne 0) {
                Log ("原生 MCP 清理失败（已忽略）：{0}（exit={1}）{2}" -f (Mask-SensitiveMcpCommandText $cmdText), $native.exit_code, (Mask-SensitiveMcpCommandText ([string]$native.error))) "WARN"
                if (Test-IsNonInteractiveMcpError ([string]$native.error)) {
                    $script:SkipNativeMcpForSession = $true
                    Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 清理。" "WARN"
                    break
                }
                continue
            }
            Log ("已执行原生 MCP 清理：{0}" -f $cmdText)
        }
        catch {
            Log ("原生 MCP 清理失败（已忽略）：{0} -> {1}" -f (Mask-SensitiveMcpCommandText $cmdText), (Mask-SensitiveMcpCommandText $_.Exception.Message)) "WARN"
            if (Test-IsNonInteractiveMcpError $_.Exception.Message) {
                $script:SkipNativeMcpForSession = $true
                Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 清理。" "WARN"
                break
            }
        }
    }
}

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
            Log ("Gemini settings.json 解析失败，将使用最小配置重建：{0}" -f $_.Exception.Message) "WARN"
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

function Build-CodexConfigToml([string]$existingToml, $servers) {
    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($existingToml)) {
        $lines = $existingToml -split "`r?`n"
    }
    $codexServers = @()
    $skippedGithubForMissingToken = $false
    $hasGithubToken = -not [string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)
    if ([string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)) {
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

    $managedMap = Convert-McpServersToCodexConfigMap $codexServers
    $managedNames = @($managedMap.PSObject.Properties.Name | Sort-Object)
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
            if ($line -match '^\s*\[mcp_servers\.([^\.\]]+)(?:\.[^\]]+)?\]\s*$') {
                $serverName = [string]$Matches[1]
                $skipMcpSection = -not $hostOwnedMcpNames.Contains($serverName)
                if (-not $skipMcpSection) {
                    $kept.Add($line) | Out-Null
                }
                continue
            }

            if ($skipMcpSection -and $line -match '^\s*\[[^\]]+\]\s*$') {
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
            $entry = $managedMap.$name
            $output.Add(("[mcp_servers.{0}]" -f $name)) | Out-Null
            foreach ($prop in $entry.PSObject.Properties) {
                $key = [string]$prop.Name
                $val = $prop.Value
                if ($null -eq $val) { continue }
                if ($val -is [Array]) {
                    $arr = @($val | ForEach-Object { ConvertTo-TomlBasicValue $_ })
                    $output.Add(("{0} = [{1}]" -f $key, ($arr -join ", "))) | Out-Null
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
                    $pairs = @($dict.Keys | Sort-Object | ForEach-Object { "{0} = {1}" -f $_, (ConvertTo-TomlBasicValue $dict[$_]) })
                    $output.Add(("{0} = {{ {1} }}" -f $key, ($pairs -join ", "))) | Out-Null
                    continue
                }
                $output.Add(("{0} = {1}" -f $key, (ConvertTo-TomlBasicValue $val))) | Out-Null
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
    # Keep array shape when only one root is found.
    return ,@($roots | Sort-Object)
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

    # Keep array shape when only one root is found.
    return ,@($roots | Sort-Object)
}

function ConvertTo-OrderedSignatureValue($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [string]) { return [string]$value }
    if ($value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($k in @($value.Keys | Sort-Object)) {
            $ordered[[string]$k] = ConvertTo-OrderedSignatureValue $value[$k]
        }
        return [pscustomobject]$ordered
    }
    if ($value -is [pscustomobject]) {
        $ordered = [ordered]@{}
        foreach ($p in @($value.PSObject.Properties | Sort-Object Name)) {
            $ordered[[string]$p.Name] = ConvertTo-OrderedSignatureValue $p.Value
        }
        return [pscustomobject]$ordered
    }
    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [byte[]])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($value)) {
            $items.Add((ConvertTo-OrderedSignatureValue $item)) | Out-Null
        }
        return @($items)
    }
    return $value
}

function Get-McpServerSignature($server) {
    if ($null -eq $server) { return $null }
    $transport = if ($server.PSObject.Properties.Match("transport").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.transport)) {
        [string]$server.transport
    }
    else {
        "stdio"
    }
    $transport = $transport.Trim().ToLowerInvariant()
    $sig = [ordered]@{ transport = $transport }
    if ($transport -eq "stdio") {
        if ($server.PSObject.Properties.Match("command").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.command)) {
            $sig.command = [string]$server.command
        }
        if ($server.PSObject.Properties.Match("args").Count -gt 0) {
            $sig.args = @($server.args)
        }
        if ($server.PSObject.Properties.Match("env").Count -gt 0 -and $null -ne $server.env) {
            $sig.env = ConvertTo-OrderedSignatureValue $server.env
        }
    }
    else {
        if ($server.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.url)) {
            $sig.url = [string]$server.url
        }
        if ($server.PSObject.Properties.Match("headers").Count -gt 0 -and $null -ne $server.headers) {
            $sig.headers = ConvertTo-OrderedSignatureValue $server.headers
        }
        if ($server.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.bearer_token_env_var)) {
            $sig.bearer_token_env_var = [string]$server.bearer_token_env_var
        }
    }
    if ($server.PSObject.Properties.Match("enabled").Count -gt 0) {
        Need ($server.enabled -is [bool]) "mcp_server.enabled 必须是布尔值"
        $sig.enabled = [bool]$server.enabled
    }
    if ($server.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $server.enabled_tools) {
        $tools = @()
        foreach ($rawTool in @($server.enabled_tools)) {
            $tool = ([string]$rawTool).Trim()
            Need (-not [string]::IsNullOrWhiteSpace($tool)) "mcp_server.enabled_tools 不得包含空值"
            Need (-not ($tool.Contains("`r") -or $tool.Contains("`n"))) "mcp_server.enabled_tools 不得包含换行"
            if ($tools -notcontains $tool) { $tools += $tool }
        }
        $sig.enabled_tools = @($tools | Sort-Object)
    }
    return ($sig | ConvertTo-Json -Depth 30 -Compress)
}

function Test-McpServerEquivalent($a, $b) {
    $sa = Get-McpServerSignature $a
    $sb = Get-McpServerSignature $b
    if ([string]::IsNullOrWhiteSpace($sa) -or [string]::IsNullOrWhiteSpace($sb)) { return $false }
    return ($sa -eq $sb)
}

function Find-EquivalentMcpServer($servers, $candidate) {
    foreach ($server in @($servers)) {
        if (Test-McpServerEquivalent $server $candidate) { return $server }
    }
    return $null
}

function 安装MCP([string[]]$tokens = @()) {
    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw

    $tokenList = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $trailingDryRun = Extract-McpTrailingDryRunToken $tokenList
    $tokenList = @($trailingDryRun.tokens)
    if (-not $DryRun -and [bool]$trailingDryRun.dry_run) {
        $script:DryRun = $true
        Write-Host "检测到尾部 -DryRun 参数，已切换为预演模式。"
    }
    if ($tokenList.Count -eq 1 -and $tokenList[0] -is [string] -and $tokenList[0].Contains(" ")) {
        $tokenList = Split-Args $tokenList[0]
    }

    $parsed = $null
    if ($tokenList.Count -gt 0) {
        $parsed = Parse-McpInstallArgs $tokenList
    }
    else {
        $name = Normalize-NameWithNotice (Read-HostSafe "MCP 服务名（如 context7）") "MCP 服务名"
        $transport = Read-HostSafe "transport（stdio/http，默认 stdio）"
        if ([string]::IsNullOrWhiteSpace($transport)) { $transport = "stdio" }
        $transport = $transport.Trim().ToLowerInvariant()
        if ($transport -ne "stdio" -and $transport -ne "http") {
            Write-Host "无效 transport，已使用默认值 stdio"
            $transport = "stdio"
        }

        if ($transport -eq "stdio") {
            $cmdLine = Read-HostSafe "命令（示例：npx -y @upstash/context7-mcp）"
            $parts = Split-Args $cmdLine
            Need ($parts.Count -gt 0) "命令不能为空"
            $parsed = [pscustomobject]@{
                name = $name
                transport = "stdio"
                command = $parts[0]
                args = if ($parts.Count -gt 1) { $parts[1..($parts.Count - 1)] } else { @() }
                url = $null
                env = @{}
                headers = @{}
            }
        }
        else {
            $url = Read-HostSafe "URL（示例：https://example.com/mcp）"
            Need (-not [string]::IsNullOrWhiteSpace($url)) "URL 不能为空"
            $parsed = [pscustomobject]@{
                name = $name
                transport = $transport
                command = $null
                args = @()
                url = $url
                env = @{}
                headers = @{}
            }
        }
    }

    $server = New-McpServerObject $parsed
    $existing = @($cfg.mcp_servers)
    $existingSameName = $existing | Where-Object { [string]$_.name -eq [string]$server.name } | Select-Object -First 1
    $updated = @()
    $replaced = $false
    $equivalent = Find-EquivalentMcpServer $existing $server
    if ($existingSameName -and (Test-McpServerEquivalent $existingSameName $server)) {
        Write-Host ("MCP 服务已存在且配置一致：{0}" -f $server.name)
        return
    }
    foreach ($s in $existing) {
        if ([string]$s.name -eq [string]$server.name) {
            $updated += $server
            $replaced = $true
        }
        else {
            $updated += $s
        }
    }
    if ($equivalent -and -not $replaced) {
        Write-Host ("已存在等效 MCP 服务：{0}（名称：{1}），已跳过" -f $server.name, [string]$equivalent.name)
        return
    }
    if (-not $replaced) { $updated += $server }
    $cfg.mcp_servers = $updated
    SaveCfgSafe $cfg $cfgRaw

    if ($DryRun) {
        if ($replaced) {
            Write-Host ("DRYRUN：将更新 MCP 服务：{0}" -f $server.name)
        }
        else {
            Write-Host ("DRYRUN：将安装 MCP 服务：{0}" -f $server.name)
        }
    }
    elseif ($replaced) {
        Write-Host ("已更新 MCP 服务：{0}" -f $server.name)
    }
    else {
        Write-Host ("已安装 MCP 服务：{0}" -f $server.name)
    }
    同步MCP
}

function 卸载MCP([string[]]$tokens = @()) {
    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw
    $servers = @($cfg.mcp_servers)
    if ($servers.Count -eq 0) {
        Write-Host "当前没有已安装的 MCP 服务。"
        return
    }

    $name = $null
    $tokenList = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $trailingDryRun = Extract-McpTrailingDryRunToken $tokenList
    $tokenList = @($trailingDryRun.tokens)
    if (-not $DryRun -and [bool]$trailingDryRun.dry_run) {
        $script:DryRun = $true
        Write-Host "检测到尾部 -DryRun 参数，已切换为预演模式。"
    }
    if ($tokenList.Count -gt 0) {
        $name = Normalize-NameWithNotice ([string]$tokenList[0]) "MCP 服务名"
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "已安装 MCP 服务："
        for ($i = 0; $i -lt $servers.Count; $i++) {
            Write-Host ("{0,3}) {1}" -f ($i + 1), $servers[$i].name)
        }
        $picked = Read-HostSafe "输入序号或名称"
        if ($picked -match "^\d+$") {
            $idx = [int]$picked - 1
            Need ($idx -ge 0 -and $idx -lt $servers.Count) "序号越界。"
            $name = [string]$servers[$idx].name
        }
        else {
            $name = Normalize-NameWithNotice $picked "MCP 服务名"
        }
    }

    $remaining = @()
    $removed = $false
    foreach ($s in $servers) {
        if ([string]$s.name -eq $name) {
            $removed = $true
        }
        else {
            $remaining += $s
        }
    }
    Need $removed ("未找到 MCP 服务：{0}" -f $name)

    $cfg.mcp_servers = $remaining
    Remove-McpProfileServerReferences $cfg @($name) | Out-Null
    SaveCfgSafe $cfg $cfgRaw
    if ($DryRun) {
        Write-Host ("DRYRUN：将卸载 MCP 服务：{0}" -f $name)
    }
    else {
        Write-Host ("已卸载 MCP 服务：{0}" -f $name)
        Invoke-NativeMcpCleanup $name
    }
    同步MCP
}

function Get-McpSyncManagedTargetSpecs {
    param(
        $Roots = @(),
        $CandidatePaths = @(),
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $specs = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $flatRoots = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($Roots)) {
        foreach ($value in @($entry)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $flatRoots.Add([string]$value) | Out-Null }
        }
    }

    function Add-McpTargetSpec([string]$Path, [string]$Kind, [string]$Root) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        $key = Normalize-OperationPathKey $Path
        if (-not $seen.Add($key)) { return }
        $specs.Add([pscustomobject][ordered]@{
                path = $Path
                kind = $Kind
                root = $Root
            }) | Out-Null
    }

    foreach ($root in @($flatRoots.ToArray() | Where-Object { -not (Split-Path ([string]$_) -Leaf).Equals('.zcode', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root '.mcp.json') 'generic_json' $root
    }
    foreach ($root in @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.gemini', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'settings.json') 'gemini_settings' $root
    }
    foreach ($root in @(Resolve-GeminiAntigravityRootsFromCandidates $CandidatePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'settings.json') 'gemini_antigravity_settings' $root
    }
    foreach ($root in @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.codex', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'config.toml') 'codex_toml' $root
    }
    foreach ($root in @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.zcode', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Get-ZCodeMcpConfigPath $root) 'zcode_json' $root
    }
    $traeRoots = @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.trae', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)
    foreach ($root in $traeRoots) {
        Add-McpTargetSpec (Join-Path $root 'mcp.json') 'trae_json' $root
    }
    if ($traeRoots.Count -gt 0) {
        Add-McpTargetSpec (Get-TraeProjectMcpConfigPath $RepoRoot) 'trae_project_json' $RepoRoot
    }

    return @($specs.ToArray())
}

function Get-McpExistingStateValue($ExistingStates, [string]$Path) {
    if ($null -eq $ExistingStates) {
        return [pscustomobject]@{ exists = $false; content = '' }
    }
    $key = Normalize-OperationPathKey $Path
    if ($ExistingStates -is [System.Collections.IDictionary] -and $ExistingStates.Contains($key)) {
        return $ExistingStates[$key]
    }
    if ($ExistingStates -is [pscustomobject]) {
        $property = @($ExistingStates.PSObject.Properties | Where-Object { $_.Name -eq $key } | Select-Object -First 1)
        if ($property.Count -eq 1) { return $property[0].Value }
    }
    return [pscustomobject]@{ exists = $false; content = '' }
}

function New-McpSyncDesiredState {
    param(
        [object[]]$Specs = @(),
        [object[]]$Servers = @(),
        [object[]]$ActiveServers = @(),
        [string[]]$ProfileDisabledNames = @(),
        [string[]]$PruneNames = @(),
        $ExistingStates = $null
    )

    $desired = New-Object System.Collections.Generic.List[object]
    foreach ($spec in @($Specs)) {
        $path = [string]$spec.path
        $state = Get-McpExistingStateValue $ExistingStates $path
        $existing = if ($null -eq $state -or $null -eq $state.content) { '' } else { [string]$state.content }
        $content = $null

        switch ([string]$spec.kind) {
            'generic_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload @($PruneNames + $ProfileDisabledNames)
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'gemini_settings' {
                $payload = Build-GeminiSettingsPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'gemini_antigravity_settings' {
                $payload = Build-GeminiSettingsPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'codex_toml' {
                $content = Build-CodexConfigToml $existing $Servers
            }
            'zcode_json' {
                $payload = Build-ZCodeMcpPayload $existing $ActiveServers
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'trae_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'trae_project_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            default { throw ('Unsupported MCP managed target kind: {0}' -f [string]$spec.kind) }
        }

        $beforeHash = if ([bool]$state.exists) { Get-OperationSha256 $existing } else { $null }
        $desiredHash = Get-OperationSha256 ([string]$content)
        $desired.Add([pscustomobject][ordered]@{
                target_ref = 'mcp-target-{0}' -f (Get-OperationSha256 (Normalize-OperationPathKey $path)).Substring(0, 16)
                path = $path
                kind = [string]$spec.kind
                root = [string]$spec.root
                owner = 'skills-manager:mcp:{0}' -f [string]$spec.kind
                existed = [bool]$state.exists
                before_hash = $beforeHash
                desired_hash = $desiredHash
                changed = ($beforeHash -ne $desiredHash)
                desired_content = [string]$content
            }) | Out-Null
    }
    return @($desired.ToArray() | Sort-Object target_ref)
}

function New-McpSyncOperationPlanResult {
    param(
        [object[]]$DesiredState = @(),
        [Parameter(Mandatory = $true)][string]$CreatedAt,
        [string]$SourceRevision
    )

    $targets = New-Object System.Collections.Generic.List[object]
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($target in @($DesiredState)) {
        $targets.Add([pscustomobject][ordered]@{
                target_ref = [string]$target.target_ref
                path = [string]$target.path
                before_hash = $target.before_hash
                desired_hash = [string]$target.desired_hash
                owner = [string]$target.owner
            }) | Out-Null
        if ([bool]$target.changed) {
            $verb = if ([bool]$target.existed) { 'Update' } else { 'Create' }
            $actions.Add([pscustomobject][ordered]@{
                    type = if ([bool]$target.existed) { 'update' } else { 'create' }
                    target_ref = [string]$target.target_ref
                    summary = ('{0} managed MCP target ({1})' -f $verb, [string]$target.kind)
                    risk = 'medium'
                    metadata = [pscustomobject]@{ target_kind = [string]$target.kind }
                }) | Out-Null
        }
    }

    $orderedTargets = @($targets.ToArray() | Sort-Object target_ref)
    $orderedActions = @($actions.ToArray() | Sort-Object target_ref, type)
    $fingerprint = Get-OperationSha256 (($orderedTargets | ConvertTo-Json -Depth 20 -Compress) + '|' + [string]$SourceRevision)
    $plan = New-OperationPlan `
        -OperationId ('mcp-sync-{0}' -f $fingerprint.Substring(0, 16)) `
        -Domain 'mcp' `
        -Mode 'dry_run' `
        -CreatedAt $CreatedAt `
        -SourceRevision $SourceRevision `
        -Targets $orderedTargets `
        -Actions $orderedActions `
        -Preconditions @('skills.json contract valid', 'managed target roots resolved') `
        -Verification @('repo target hashes only; host loading and live acceptance are not claimed') `
        -Rollback @('plan mode performs no managed target or native mutation')

    return [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'mcp_sync_plan'
        operation_plan = $plan
        summary = [pscustomobject][ordered]@{
            managed_target_count = @($DesiredState).Count
            changed_target_count = @($DesiredState | Where-Object changed).Count
            unchanged_target_count = @($DesiredState | Where-Object { -not [bool]$_.changed }).Count
            native_mutation_planned = $false
            profile_changed = $false
            host_loaded = 'not_run'
            live_accepted = 'not_run'
        }
    }
}

function Load-McpPlanConfigReadOnly {
    Need (Test-Path -LiteralPath $CfgPath -PathType Leaf) "缺少配置文件：$CfgPath"
    $raw = Get-ContentUtf8 $CfgPath
    $clean = $raw -replace '(?m)^\s*//.*', ''
    try { $cfg = $clean | ConvertFrom-Json }
    catch { throw ("skills.json 解析失败：{0}" -f $_.Exception.Message) }
    $contract = Get-CfgVersionedContractReport $cfg
    Need (@($contract.errors).Count -eq 0) "skills.json 未通过只读合同校验，plan 不会自动修复配置。"
    $cfg = Normalize-Cfg $cfg
    Assert-Cfg $cfg
    return [pscustomobject]@{ cfg = $cfg; raw = $raw }
}

function Parse-McpSyncPlanOptions([string[]]$Tokens = @()) {
    $json = $false
    $outPath = ''
    $plan = $false
    $items = @($Tokens | Where-Object { $null -ne $_ })
    for ($i = 0; $i -lt $items.Count; $i++) {
        $token = ([string]$items[$i]).Trim()
        switch -Regex ($token) {
            '^(?i)--plan$' { $plan = $true; continue }
            '^(?i)--json$' { $json = $true; continue }
            '^(?i)--out=(.+)$' { $outPath = [string]$Matches[1]; continue }
            '^(?i)--out$' {
                Need (($i + 1) -lt $items.Count) '--out 需要路径值。'
                $i++
                $outPath = [string]$items[$i]
                Need (-not [string]::IsNullOrWhiteSpace($outPath)) '--out 需要非空路径值。'
                continue
            }
            '^$' { continue }
            default { throw ('未知 MCP plan 参数：{0}' -f $token) }
        }
    }
    return [pscustomobject]@{ plan = $plan; json = $json; out_path = $outPath }
}

function Get-McpExistingStates([object[]]$Specs) {
    $states = @{}
    foreach ($spec in @($Specs)) {
        $path = [string]$spec.path
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $states[(Normalize-OperationPathKey $path)] = [pscustomobject]@{
            exists = $exists
            content = if ($exists) { Get-Content -LiteralPath $path -Raw -Encoding UTF8 } else { '' }
        }
    }
    return $states
}

function Get-McpSyncPlanningContext([switch]$ReadOnlyConfig) {
    $loaded = if ($ReadOnlyConfig) { Load-McpPlanConfigReadOnly } else { [pscustomobject]@{ cfg = (LoadCfg); raw = (Get-ContentUtf8 $CfgPath) } }
    $cfg = $loaded.cfg
    $servers = @(Resolve-McpProfileServers $cfg)
    $activeServers = @(Get-ActiveMcpServers $servers)
    $profileDisabledNames = @($servers | Where-Object { $_.PSObject.Properties.Match('enabled').Count -gt 0 -and -not [bool]$_.enabled } | ForEach-Object { [string]$_.name })
    $pruneNames = @(Get-McpServersToPrune $servers)
    $roots = @(Resolve-McpTargetRootsFromCfg $cfg)
    Need ($roots.Count -gt 0) "未找到可同步的 MCP 目标目录（请检查 targets/mcp_targets 配置）。"
    $candidatePaths = @(Get-McpTargetCandidatePaths $cfg)
    $specs = @(Get-McpSyncManagedTargetSpecs -Roots $roots -CandidatePaths $candidatePaths -RepoRoot $script:Root)
    $existingStates = Get-McpExistingStates $specs
    $desiredState = @(New-McpSyncDesiredState -Specs $specs -Servers $servers -ActiveServers $activeServers -ProfileDisabledNames $profileDisabledNames -PruneNames $pruneNames -ExistingStates $existingStates)
    return [pscustomobject]@{
        cfg = $cfg
        config_raw = [string]$loaded.raw
        config_revision = Get-OperationSha256 ([string]$loaded.raw)
        servers = $servers
        active_servers = $activeServers
        profile_disabled_names = $profileDisabledNames
        prune_names = $pruneNames
        roots = $roots
        desired_state = $desiredState
    }
}

function Invoke-McpSyncPlan([switch]$Json, [string]$OutPath = '') {
    $context = Get-McpSyncPlanningContext -ReadOnlyConfig
    $createdAt = (Get-Item -LiteralPath $CfgPath).LastWriteTimeUtc.ToString('o')
    $result = New-McpSyncOperationPlanResult -DesiredState $context.desired_state -CreatedAt $createdAt -SourceRevision $context.config_revision
    $validation = Test-OperationPlanContract $result.operation_plan
    Need ([bool]$validation.pass) ("MCP plan contract validation failed: {0}" -f (@($validation.findings.code) -join ', '))
    $serialized = $result | ConvertTo-Json -Depth 50

    if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
        $resolvedOut = Resolve-TargetDir $OutPath
        $parent = Split-Path $resolvedOut -Parent
        if (-not [string]::IsNullOrWhiteSpace($parent)) { EnsureDir $parent }
        Set-ContentUtf8 $resolvedOut $serialized
    }
    if ($Json) {
        Write-Output $serialized
        return
    }
    Write-Host ("MCP plan：targets={0}, changed={1}, unchanged={2}, native=0" -f $result.summary.managed_target_count, $result.summary.changed_target_count, $result.summary.unchanged_target_count)
    foreach ($action in @($result.operation_plan.actions)) {
        $target = @($result.operation_plan.targets | Where-Object target_ref -eq $action.target_ref | Select-Object -First 1)
        Write-Host ("- {0}: {1}" -f $action.type, [string]$target[0].path)
    }
    if (-not [string]::IsNullOrWhiteSpace($OutPath)) { Write-Host ("Plan JSON：{0}" -f (Resolve-TargetDir $OutPath)) }
}

function Write-McpDesiredTarget($target) {
    $path = [string]$target.path
    $parent = Split-Path $path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) { EnsureDir $parent }
    if ([string]$target.kind -eq 'codex_toml') { Ensure-CodexMcpNodeCacheWrapper ([string]$target.root) }
    Write-Utf8FileAtomic -Path $path -Content ([string]$target.desired_content)
    switch ([string]$target.kind) {
        'gemini_settings' { Log ("已同步 Gemini MCP 配置：{0}" -f $path) }
        'gemini_antigravity_settings' { Log ("已同步 Gemini Antigravity MCP 配置：{0}" -f $path) }
        'codex_toml' { Log ("已同步 Codex MCP 配置：{0}" -f $path) }
        'zcode_json' { Log ("已同步 ZCode MCP 配置：{0}" -f $path) }
        'trae_json' { Log ("已同步 Trae MCP 配置：{0}" -f $path) }
        'trae_project_json' { Log ("已同步项目级 Trae MCP 配置：{0}" -f $path) }
        default { Log ("已同步 MCP 配置：{0}" -f $path) }
    }
}

function Test-McpTargetReparsePath([string]$Path,[string]$Root) {
    $cursor=[IO.Path]::GetFullPath($Path);$boundary=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    while($true){
        if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $true}}
        if($cursor.TrimEnd('\','/').Equals($boundary,[StringComparison]::OrdinalIgnoreCase)){break}
        $parent=[IO.Directory]::GetParent($cursor);if($null -eq $parent -or -not (Test-OperationPathWithinRoot $parent.FullName $boundary)){break};$cursor=$parent.FullName
    }
    return $false
}

function Assert-McpDesiredStateFresh([object[]]$DesiredState,[string]$ExpectedConfigRevision='') {
    if(-not [string]::IsNullOrWhiteSpace($ExpectedConfigRevision)){
        $currentConfigRevision=Get-OperationSha256 (Get-ContentUtf8 $CfgPath)
        Need ($currentConfigRevision -eq $ExpectedConfigRevision) 'MCP source_revision_stale：skills.json changed after planning.'
    }
    foreach($target in @($DesiredState)){
        $path=[IO.Path]::GetFullPath([string]$target.path);$root=[IO.Path]::GetFullPath([string]$target.root)
        Need (Test-OperationPathWithinRoot $path $root) ("MCP target_out_of_root：{0}" -f $path)
        Need (-not (Test-McpTargetReparsePath $path $root)) ("MCP target_reparse_forbidden：{0}" -f $path)
        $exists=Test-Path -LiteralPath $path -PathType Leaf;$before=$target.before_hash
        if($null -eq $before){Need (-not $exists) ("MCP target_created_since_plan：{0}" -f $path)}
        else{Need $exists ("MCP target_missing_since_plan：{0}" -f $path);Need ((Get-OperationSha256 (Get-ContentUtf8 $path)) -eq [string]$before) ("MCP target_hash_stale：{0}" -f $path)}
    }
}

function Restore-McpManagedTargetSnapshot([object[]]$Snapshot) {
    $conflicts=New-Object System.Collections.Generic.List[string]
    foreach($entry in @($Snapshot)){
        $path=[string]$entry.path
        if(Test-Path -LiteralPath $path -PathType Leaf){
            $currentHash=Get-OperationSha256 (Get-ContentUtf8 $path)
            $allowed=@([string]$entry.before_hash,[string]$entry.desired_hash)|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}
            if($currentHash -notin $allowed){$conflicts.Add($path)|Out-Null;continue}
        }
        if([bool]$entry.existed){Write-BytesAtomic -Path $path -Bytes ([byte[]]$entry.bytes)}
        elseif(Test-Path -LiteralPath $path -PathType Leaf){Remove-Item -LiteralPath $path -Force}
    }
    Need ($conflicts.Count -eq 0) ("MCP rollback_conflict：managed targets changed outside this transaction: {0}" -f ($conflicts -join ', '))
}

function Get-McpImplicitSidecarTargets([object[]]$DesiredState) {
    $targets=New-Object System.Collections.Generic.List[object]
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($target in @($DesiredState|Where-Object{[string]$_.kind -eq 'codex_toml'})){
        $root=[IO.Path]::GetFullPath([string]$target.root)
        $nodePath=Join-Path $root 'scripts/mcp-node-cache-wrapper.mjs'
        if($seen.Add($nodePath)){$targets.Add([pscustomobject]@{path=$nodePath;root=$root;desired_content=(Get-CodexMcpNodeCacheWrapperContent)})|Out-Null}
        $postgresPath=Join-Path $root 'scripts/mcp-postgres-env-wrapper.mjs'
        if($seen.Add($postgresPath)){$targets.Add([pscustomobject]@{path=$postgresPath;root=$root;desired_content=(Get-CodexMcpPostgresEnvWrapperContent)})|Out-Null}
    }
    return @($targets.ToArray())
}

function Remove-McpCreatedRootIfEmpty([string]$Root) {
    if(-not (Test-Path -LiteralPath $Root -PathType Container)){return}
    if(Test-McpTargetReparsePath $Root $Root){return}
    $files=@([IO.Directory]::GetFiles($Root,'*',[IO.SearchOption]::AllDirectories))
    if($files.Count -gt 0){return}
    $reparse=@([IO.Directory]::GetFileSystemEntries($Root,'*',[IO.SearchOption]::AllDirectories)|Where-Object{([IO.File]::GetAttributes($_)-band [IO.FileAttributes]::ReparsePoint)-ne 0})
    if($reparse.Count -gt 0){return}
    Remove-Item -LiteralPath $Root -Recurse -Force
}

function Invoke-McpManagedTargetTransaction([object[]]$DesiredState,[string]$ExpectedConfigRevision='') {
    $lockEntries=New-Object System.Collections.Generic.List[object]
    $snapshot=New-Object System.Collections.Generic.List[object]
    $createdRoots=New-Object System.Collections.Generic.List[string]
    $transactionSucceeded=$false
    try{
        $roots=@($DesiredState|ForEach-Object{[IO.Path]::GetFullPath([string]$_.root)}|Sort-Object -Unique)
        foreach($root in $roots){
            $drive=[IO.Path]::GetPathRoot($root).TrimEnd('\','/');$trimmed=$root.TrimEnd('\','/')
            Need (-not $trimmed.Equals($drive,[StringComparison]::OrdinalIgnoreCase)) ("MCP target_root_forbidden：{0}" -f $root)
            if(Test-Path -LiteralPath $root){Need (Test-Path -LiteralPath $root -PathType Container) ("MCP target_root_not_directory：{0}" -f $root);continue}
            $parent=[IO.Directory]::GetParent($root)
            Need ($null -ne $parent -and (Test-Path -LiteralPath $parent.FullName -PathType Container)) ("MCP target_root_parent_missing：{0}" -f $root)
            Need (-not (Test-McpTargetReparsePath $parent.FullName $parent.FullName)) ("MCP target_root_parent_reparse_forbidden：{0}" -f $root)
        }
        foreach($root in $roots){
            if(-not (Test-Path -LiteralPath $root -PathType Container)){[IO.Directory]::CreateDirectory($root)|Out-Null;$createdRoots.Add($root)|Out-Null}
            Need (-not (Test-McpTargetReparsePath $root $root)) ("MCP target_reparse_forbidden：{0}" -f $root)
            $lockPath=Join-Path $root '.skills-manager-mcp-sync.lock'
            $stream=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $lockEntries.Add([pscustomobject]@{path=$lockPath;stream=$stream})|Out-Null
        }
        Assert-McpDesiredStateFresh $DesiredState $ExpectedConfigRevision
        foreach($target in @($DesiredState)){
            $path=[string]$target.path;$exists=Test-Path -LiteralPath $path -PathType Leaf
            $snapshot.Add([pscustomobject]@{path=$path;existed=$exists;bytes=$(if($exists){[IO.File]::ReadAllBytes($path)}else{[byte[]]::new(0)});before_hash=$target.before_hash;desired_hash=(Get-OperationSha256 ([string]$target.desired_content))})|Out-Null
        }
        $sidecars=@(Get-McpImplicitSidecarTargets $DesiredState)
        foreach($sidecar in $sidecars){
            $path=[IO.Path]::GetFullPath([string]$sidecar.path);$root=[IO.Path]::GetFullPath([string]$sidecar.root)
            Need (Test-OperationPathWithinRoot $path $root) ("MCP sidecar_out_of_root：{0}" -f $path)
            Need (-not (Test-McpTargetReparsePath $path $root)) ("MCP sidecar_reparse_forbidden：{0}" -f $path)
            $exists=Test-Path -LiteralPath $path -PathType Leaf
            $beforeHash=$(if($exists){Get-OperationSha256 (Get-ContentUtf8 $path)}else{$null})
            $sidecar|Add-Member -NotePropertyName before_hash -NotePropertyValue $beforeHash -Force
            $snapshot.Add([pscustomobject]@{path=$path;existed=$exists;bytes=$(if($exists){[IO.File]::ReadAllBytes($path)}else{[byte[]]::new(0)});before_hash=$beforeHash;desired_hash=(Get-OperationSha256 ([string]$sidecar.desired_content))})|Out-Null
        }
        foreach($target in @($DesiredState|Where-Object changed)){
            Assert-McpDesiredStateFresh @($target) $ExpectedConfigRevision
            if([string]$target.kind -eq 'codex_toml'){
                $targetRoot=[IO.Path]::GetFullPath([string]$target.root)
                foreach($sidecar in @($sidecars|Where-Object{[IO.Path]::GetFullPath([string]$_.root) -eq $targetRoot})){
                    $exists=Test-Path -LiteralPath $sidecar.path -PathType Leaf
                    if($null -eq $sidecar.before_hash){Need (-not $exists) ("MCP sidecar_created_since_lock：{0}" -f $sidecar.path)}
                    else{Need $exists ("MCP sidecar_missing_since_lock：{0}" -f $sidecar.path);Need ((Get-OperationSha256 (Get-ContentUtf8 $sidecar.path)) -eq [string]$sidecar.before_hash) ("MCP sidecar_hash_stale：{0}" -f $sidecar.path)}
                }
            }
            Write-McpDesiredTarget $target
        }
        $transactionSucceeded=$true
        return [pscustomobject]@{pass=$true;writes=@($DesiredState|Where-Object changed).Count;snapshot=@($snapshot.ToArray());rollback_policy='managed_files_only_before_native_effects'}
    }catch{
        if($snapshot.Count -gt 0){Restore-McpManagedTargetSnapshot @($snapshot.ToArray())}
        throw
    }finally{
        foreach($lock in @($lockEntries.ToArray())){$lock.stream.Dispose();if(Test-Path -LiteralPath $lock.path -PathType Leaf){Remove-Item -LiteralPath $lock.path -Force -ErrorAction SilentlyContinue}}
        if(-not $transactionSucceeded){foreach($root in @($createdRoots.ToArray())|Sort-Object Length -Descending){Remove-McpCreatedRootIfEmpty $root}}
    }
}

function 同步MCP {
    & {
        $script:SkipNativeMcpForSession = $false
        $context = Get-McpSyncPlanningContext
        if (-not $DryRun) {
            Ensure-PostgresMcpEnvironment $context.active_servers
            Ensure-GhAuthForGithubMcp $context.active_servers
        }

        $managedTransaction=$null
        foreach ($target in @($context.desired_state)) { if ($DryRun) { Write-Host ("DRYRUN：将写入 MCP 配置 -> {0}" -f [string]$target.path) } }
        if(-not $DryRun){$managedTransaction=Invoke-McpManagedTargetTransaction -DesiredState @($context.desired_state) -ExpectedConfigRevision ([string]$context.config_revision)}

        $nativeMutationEnabled=Should-RunNativeMcpSync
        try{
            Write-Host ("已同步 MCP 服务配置到 {0} 个目标。" -f @($context.desired_state).Count)
            foreach ($pruneName in @($context.prune_names)) { Invoke-NativeMcpCleanup $pruneName }
            Invoke-NativeMcpSync $context.active_servers
            if (-not $DryRun) {
                $attemptsParsed = 0
                $intervalParsed = 0
                $attempts = if ([int]::TryParse([string]$env:SKILLS_MCP_VERIFY_ATTEMPTS, [ref]$attemptsParsed)) { $attemptsParsed } else { 6 }
                $intervalSeconds = if ([int]::TryParse([string]$env:SKILLS_MCP_VERIFY_INTERVAL_SECONDS, [ref]$intervalParsed)) { $intervalParsed } else { 3 }
                if ($attempts -lt 1) { $attempts = 1 }
                if ($intervalSeconds -lt 1) { $intervalSeconds = 1 }
                Verify-McpAcrossCliWithRetry $context.roots $attempts $intervalSeconds
            }
        }catch{
            if($null -ne $managedTransaction -and -not $nativeMutationEnabled){Restore-McpManagedTargetSnapshot @($managedTransaction.snapshot)}
            elseif($null -ne $managedTransaction){Log 'MCP managed files were retained because opt-in native side effects may already have occurred and cannot be transactionally compensated.' 'WARN'}
            throw
        }
        if (@($context.servers).Count -eq 0) { Write-Host "提示：当前 mcp_servers 为空，已将各目标写为空配置。" }
    }
}
