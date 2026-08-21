Describe "Skill integrity verifier" {
    BeforeAll {
$scriptPath = Join-Path $PSScriptRoot "..\..\scripts\verify-skill-integrity.ps1"
function New-IntegrityFixture([string]$name, [string]$body, [object[]]$dependencies = @()) {
        $root = Join-Path $TestDrive $name
        $agentRoot = Join-Path $root "agent"
        $skillRoot = Join-Path $agentRoot "demo"
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        @"
---
name: demo
description: fixture
---
$body
"@ | Set-Content -Path (Join-Path $skillRoot "SKILL.md") -Encoding UTF8

        $configPath = Join-Path $root "skills.json"
        @{
            mcp_servers = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8

        $contractPath = Join-Path $root "skill-dependency-closure.json"
        @{
            schema_version = 1
            dependencies = $dependencies
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $contractPath -Encoding UTF8

        return [pscustomobject]@{
            AgentRoot = $agentRoot
            ConfigPath = $configPath
            ContractPath = $contractPath
            ReportPath = (Join-Path $root "report.json")
        }
    }
function Invoke-IntegrityFixture($fixture) {
        $output = @(& $scriptPath `
                -AgentRoot $fixture.AgentRoot `
                -ConfigPath $fixture.ConfigPath `
                -DependencyContractPath $fixture.ContractPath `
                -ReportPath $fixture.ReportPath `
                -Json -NoExit 2>&1)
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = ($output -join "`n")
            Report = if (Test-Path $fixture.ReportPath) { Get-Content -Raw $fixture.ReportPath | ConvertFrom-Json } else { $null }
        }
    }
function Add-IntegrityFixtureSkill($fixture, [string]$directory, [string]$name, [string]$body = "") {
        $skillRoot = Join-Path $fixture.AgentRoot $directory
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        @"
---
name: $name
description: fixture
---
$body
"@ | Set-Content -Path (Join-Path $skillRoot "SKILL.md") -Encoding UTF8
        return $skillRoot
    }
function Set-IntegrityFixtureOpenAiYaml($fixture, [string]$content) {
        $agentsRoot = Join-Path (Join-Path $fixture.AgentRoot "demo") "agents"
        New-Item -ItemType Directory -Path $agentsRoot -Force | Out-Null
        $content | Set-Content -Path (Join-Path $agentsRoot "openai.yaml") -Encoding UTF8
    }
}

    It "fails when a skill entrypoint references a missing local file" {
        $fixture = New-IntegrityFixture "broken-link" "Read [missing](references/missing.md)."

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        $result.Report | Should -Not -BeNullOrEmpty
        @($result.Report.errors | Where-Object code -eq "broken_relative_link").Count | Should -Be 1
    }

    It "fails when a skill name appears outside YAML frontmatter" {
        $fixture = New-IntegrityFixture "name-outside-frontmatter" ""
        @'
# Demo

name: demo
'@ | Set-Content -Path (Join-Path (Join-Path $fixture.AgentRoot "demo") "SKILL.md") -Encoding UTF8

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq "missing_skill_name").Count | Should -Be 1
    }

    It 'fails when the package directory differs from the declared skill name' {
        $fixture = New-IntegrityFixture 'directory-name-mismatch' ''
        $skillFile = Join-Path (Join-Path $fixture.AgentRoot 'demo') 'SKILL.md'
        (Get-Content -LiteralPath $skillFile -Raw).Replace('name: demo', 'name: canonical-demo') |
            Set-Content -LiteralPath $skillFile -Encoding utf8

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq 'skill_directory_name_mismatch').Count | Should -Be 1
    }

    It "fails when an entrypoint resource escapes the agent root" {
        $fixture = New-IntegrityFixture "link-outside-agent-root" "Read [outside](../../outside.md)."
        "outside" | Set-Content -Path (Join-Path (Split-Path $fixture.AgentRoot -Parent) "outside.md") -Encoding UTF8

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq "relative_link_outside_agent_root").Count | Should -Be 1
    }

    It "fails when a declared required skill is not installed" {
        $fixture = New-IntegrityFixture "missing-skill" "" @(
            @{ skill = "demo"; requires = @("required-skill") }
        )

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq "missing_required_skill").Count | Should -Be 1
    }

    It "validates dependency closure from tracked portable declarations when imported packages are not materialized" {
        $fixture = New-IntegrityFixture "clean-portable-inventory" "" @(
            @{ skill = "imported-caller"; requires = @("mapped-required") },
            @{ skill = "mapped-caller"; requires = @("imported-required") }
        )
        $config = Get-Content -Raw $fixture.ConfigPath | ConvertFrom-Json
        $config | Add-Member -NotePropertyName imports -NotePropertyValue @(
            @{ name = "caller-source"; skill = "skills\imported-caller" },
            @{ name = "required-source"; skill = "skills\imported-required" }
        )
        $config | Add-Member -NotePropertyName mappings -NotePropertyValue @(
            @{ vendor = "fixture"; from = "skills\mapped-caller"; to = "fixture-mapped-caller" },
            @{ vendor = "fixture"; from = "skills\mapped-required"; to = "fixture-mapped-required" }
        )
        $config | ConvertTo-Json -Depth 8 | Set-Content -Path $fixture.ConfigPath -Encoding UTF8

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 0
        @($result.Report.errors).Count | Should -Be 0
    }

    It "fails when OpenAI metadata references a missing icon" {
        $fixture = New-IntegrityFixture "missing-openai-icon" ""
        Set-IntegrityFixtureOpenAiYaml $fixture @'
interface:
  icon_small: "./assets/missing.svg"
'@

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq "broken_openai_resource").Count | Should -Be 1
    }

    It "fails when an OpenAI icon escapes the skill directory" {
        $fixture = New-IntegrityFixture "openai-icon-outside-skill" ""
        "outside" | Set-Content -Path (Join-Path $fixture.AgentRoot "outside.svg") -Encoding UTF8
        Set-IntegrityFixtureOpenAiYaml $fixture @'
interface:
  icon_small: "../outside.svg"
'@

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq "openai_resource_outside_skill").Count | Should -Be 1
    }

    It "fails when OpenAI metadata requires an unconfigured MCP server" {
        $fixture = New-IntegrityFixture "missing-openai-mcp" ""
        Set-IntegrityFixtureOpenAiYaml $fixture @'
dependencies:
  tools:
    - type: "mcp"
      value: "missing-docs"
'@

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq "missing_required_mcp").Count | Should -Be 1
    }

    It 'fails when OpenAI invocation policy is not boolean' {
        $fixture = New-IntegrityFixture 'invalid-openai-policy' ''
        Set-IntegrityFixtureOpenAiYaml $fixture @'
policy:
  allow_implicit_invocation: sometimes
'@

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq 'invalid_openai_invocation_policy').Count | Should -BeGreaterThan 0
    }

    It 'fails when OpenAI invocation policy is placed under the wrong section' {
        $fixture = New-IntegrityFixture 'wrong-section-openai-policy' ''
        Set-IntegrityFixtureOpenAiYaml $fixture @'
interface:
  allow_implicit_invocation: true
'@

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq 'invalid_openai_invocation_policy').Count | Should -Be 1
    }

    It 'accepts a boolean invocation policy directly under policy' {
        $fixture = New-IntegrityFixture 'valid-openai-policy' ''
        Set-IntegrityFixtureOpenAiYaml $fixture @'
policy:
  allow_implicit_invocation: true
'@

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 0
        @($result.Report.errors).Count | Should -Be 0
    }

    It 'fails when an OpenAI MCP dependency uses a retired transport or invalid URL' {
        $fixture = New-IntegrityFixture 'invalid-openai-mcp-transport' ''
        $config = Get-Content -Raw $fixture.ConfigPath | ConvertFrom-Json
        $config.mcp_servers = @([pscustomobject]@{ name = 'docs'; transport = 'http'; url = 'https://example.invalid/mcp' })
        $config | ConvertTo-Json -Depth 8 | Set-Content -Path $fixture.ConfigPath -Encoding UTF8
        Set-IntegrityFixtureOpenAiYaml $fixture @'
dependencies:
  tools:
    - type: "mcp"
      value: "docs"
      transport: "sse"
      url: "relative/mcp"
'@

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 1
        @($result.Report.errors | Where-Object code -eq 'invalid_openai_mcp_transport').Count | Should -Be 1
        @($result.Report.errors | Where-Object code -eq 'invalid_openai_mcp_url').Count | Should -Be 1
    }

    It 'accepts the official Streamable HTTP dependency shape' {
        $fixture = New-IntegrityFixture 'valid-openai-mcp' ''
        $config = Get-Content -Raw $fixture.ConfigPath | ConvertFrom-Json
        $config.mcp_servers = @([pscustomobject]@{ name = 'docs'; transport = 'http'; url = 'https://example.invalid/mcp' })
        $config | ConvertTo-Json -Depth 8 | Set-Content -Path $fixture.ConfigPath -Encoding UTF8
        Set-IntegrityFixtureOpenAiYaml $fixture @'
dependencies:
  tools:
    - type: "mcp"
      value: "docs"
      description: "Docs server"
      transport: "streamable_http"
      url: "https://example.invalid/mcp"
'@

        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 0
        @($result.Report.errors).Count | Should -Be 0
    }

    It "passes for valid resources and a complete dependency closure" {
        $fixture = New-IntegrityFixture "valid" "Read [guide](references/guide.md)." @(
            @{ skill = "demo"; requires = @("required-skill") }
        )
        $skillRoot = Add-IntegrityFixtureSkill $fixture "required-skill" "required-skill"
        $referenceRoot = Join-Path (Join-Path $fixture.AgentRoot "demo") "references"
        New-Item -ItemType Directory -Path $referenceRoot -Force | Out-Null
        "guide" | Set-Content -Path (Join-Path $referenceRoot "guide.md") -Encoding UTF8
        $result = Invoke-IntegrityFixture $fixture

        $result.ExitCode | Should -Be 0
        $result.Report.ok | Should -Be $true
        @($result.Report.errors).Count | Should -Be 0
    }

    It "runs with explicit fixture paths under PowerShell 7" {
        $pwsh = Get-Command pwsh -ErrorAction Stop | Select-Object -First 1
        $fixture = New-IntegrityFixture "powershell-7" ""
        $output = @(& $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
                -AgentRoot $fixture.AgentRoot `
                -ConfigPath $fixture.ConfigPath `
                -DependencyContractPath $fixture.ContractPath `
                -ReportPath $fixture.ReportPath `
                -Json 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        ($output -join "`n") | Should -Match '"ok":\s*true'
    }
}
