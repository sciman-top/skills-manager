# Contract tests for the AI risk-control handover tools.
#
# docs/handover/ai-risk-control/ is a cross-machine deployment payload, not repo
# runtime, so these scripts have no other automated coverage: the manifest test
# only proves the bytes match, not that the tools still behave.
#
# Two layers here:
#   1. The bundled splitter acceptance fixture (ensure-split.test.ps1) is a
#      hermetic offline fixture (temp dirs + temp registry keys) and runs as-is.
#   2. The WorkBuddy self-check supports WB_AI_DIR / WB_APP_DIR / HOSTS_FILE /
#      V2RAY_CONFIG / WB_BUILTIN_DIR overrides (same contract as the .sh twin),
#      so its MCP classification can be driven against an injected fixture.
#
# The .sh twin's own fixture (workbuddy-risk-selfcheck.test.sh) is deliberately
# NOT wired here: it cannot complete in this project's sandbox (a registry-reading
# branch terminates the process group) and its CI behaviour is unverified, so
# asserting on it would risk a red build on unproven behaviour. Run it manually:
#   bash docs/handover/ai-risk-control/tools/workbuddy/workbuddy-risk-selfcheck.test.sh

BeforeAll {
    $script:toolsRoot = (Get-Item (Join-Path $PSScriptRoot '../../docs/handover/ai-risk-control/tools')).FullName
    $script:selfcheck = Join-Path $script:toolsRoot 'workbuddy/workbuddy-risk-selfcheck.ps1'
    $script:pwshExe = (Get-Process -Id $PID).Path
    $script:fixtures = [System.Collections.Generic.List[string]]::new()

    function New-WorkbuddyFixture {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('airc-tools-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'ai'), (Join-Path $d 'app/logs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'hosts') -Value '# clean hosts'
        Set-Content -LiteralPath (Join-Path $d 'ai/models.json') -Value '[]'
        Set-Content -LiteralPath (Join-Path $d 'ai/settings.json') -Value '{}'
        Set-Content -LiteralPath (Join-Path $d 'v2ray.json') -Value '{"SysProxyType":1,"SystemProxyExceptions":"localhost;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com;"}'
        $script:fixtures.Add($d) | Out-Null
        return $d
    }

    function Invoke-WorkbuddySelfcheck([string]$Fixture) {
        $pairs = [ordered]@{
            WB_AI_DIR      = Join-Path $Fixture 'ai'
            WB_APP_DIR     = Join-Path $Fixture 'app'
            HOSTS_FILE     = Join-Path $Fixture 'hosts'
            V2RAY_CONFIG   = Join-Path $Fixture 'v2ray.json'
            WB_BUILTIN_DIR = Join-Path $Fixture 'ai/plugins/cache/workbuddy-builtin'
        }
        $saved = @{}
        foreach ($k in $pairs.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $pairs[$k]) }
        try {
            $res = & $script:pwshExe -NoProfile -ExecutionPolicy Bypass -File $script:selfcheck -NoFile 2>&1
            return [pscustomobject]@{
                text = ($res | ForEach-Object { [string]$_ }) -join "`n"
                exit_code = $LASTEXITCODE
            }
        }
        finally {
            foreach ($k in $pairs.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
        }
    }
}

AfterAll {
    foreach ($d in $script:fixtures) {
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'AI risk-control handover tools' {
    It 'passes the bundled splitter acceptance fixture' {
        $fixture = Join-Path $script:toolsRoot 'ensure-split.test.ps1'
        Test-Path -LiteralPath $fixture -PathType Leaf | Should -BeTrue
        $res = & $script:pwshExe -NoProfile -ExecutionPolicy Bypass -File $fixture 2>&1
        $text = ($res | ForEach-Object { [string]$_ }) -join "`n"
        $LASTEXITCODE | Should -Be 0 -Because $text
        $text | Should -Match 'PASS 23 / FAIL 0'
    }

    It 'flags a self-added connector that keeps retrying as high risk' {
        $d = New-WorkbuddyFixture
        New-Item -ItemType Directory -Path (Join-Path $d 'ai/plugins/cache/workbuddy-builtin/mcp-ardot-mcp-app') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'app/logs/workbuddyMainThread__x.log') -Value @(
            '[MCP-ControllerState] id=custom-mcp:evil state=error'
            '[MCP-Probe] retry scheduled id=custom-mcp:evil'
            '[MCP-Probe] retry scheduled id=custom-mcp:evil'
            '[MCP-Probe] retry scheduled id=custom-mcp:evil'
            '[MCP-ControllerState] id=builtin:ardot state=error'
            '[MCP-ControllerState] id=custom-mcp:netdrive state=unauthorized'
            '[MCP-Connect] begin configId=custom-mcp:netdrive provider=x url=https://www.workbuddy.ai/console/agent-gateway/netdrive/mcp'
        )
        # A project session log echoes the strings above; it must not be counted.
        Set-Content -LiteralPath (Join-Path $d 'app/logs/proj__abc.log') -Value '[MCP-ControllerState] id=custom-mcp:decoy state=error'

        $r = Invoke-WorkbuddySelfcheck $d
        $r.text | Should -Match '\[高危\] MCP 认证失败（自加连接器）: custom-mcp:evil'
        $r.text | Should -Match '含 3 次探测重试'
        $r.text | Should -Not -Match 'decoy'
        $r.exit_code | Should -Be 1
    }

    It 'downgrades built-in plugins and official gateway connectors to expected behaviour' {
        $d = New-WorkbuddyFixture
        New-Item -ItemType Directory -Path (Join-Path $d 'ai/plugins/cache/workbuddy-builtin/mcp-ardot-mcp-app') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'app/logs/workbuddyMainThread__y.log') -Value @(
            '[MCP-ControllerState] id=builtin:ardot state=error'
            '[MCP-ControllerState] id=custom-mcp:netdrive state=unauthorized'
            '[MCP-Connect] begin configId=custom-mcp:netdrive provider=x url=https://www.workbuddy.ai/console/agent-gateway/netdrive/mcp'
        )
        $r = Invoke-WorkbuddySelfcheck $d
        $r.text | Should -Match 'MCP 认证失败（内置插件，非风控信号）: builtin:ardot'
        $r.text | Should -Match 'MCP 认证失败（官方网关连接器，非风控信号）: custom-mcp:netdrive'
        $r.text | Should -Not -Match '自加连接器'
    }

    It 'reports a clean fixture as no MCP failures' {
        $d = New-WorkbuddyFixture
        Set-Content -LiteralPath (Join-Path $d 'app/logs/workbuddyMainThread__z.log') -Value 'no connector state here'
        $r = Invoke-WorkbuddySelfcheck $d
        $r.text | Should -Match '\[正常\] 未发现 MCP 认证失败'
    }
}
