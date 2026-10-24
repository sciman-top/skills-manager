# skills-manager

<p align="center">
  <strong>A Windows-First, Local-First AI Skills & MCP Server Versioned Manager</strong><br>
  Single Configuration · Managed Projection to Multiple Hosts · Version Locking · Zero Account Hijacking
</p>

<p align="center">
  <a href="https://github.com/sciman-top/skills-manager/releases"><img src="https://img.shields.io/github/v/release/sciman-top/skills-manager?color=0078D4&label=Release" alt="Release"></a>
  <img src="https://img.shields.io/badge/Platform-Windows-blue?logo=windows" alt="Platform: Windows">
  <img src="https://img.shields.io/badge/PowerShell-7.0%2B-5391FE?logo=powershell" alt="PowerShell 7+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT"></a>
  <a href="README.md"><img src="https://img.shields.io/badge/Language-中文-blue.svg" alt="Chinese README"></a>
</p>

---

### What Pain Point Does It Solve?

When using OpenAI Codex, Claude Code, ZCode, Antigravity (Gemini), or WorkBuddy across multiple Windows machines, you frequently run into:

- **Config Duplication**: Manually copying `.agents/skills` or configuring MCP JSON every time you switch from your desktop to your laptop.
- **Host Fragmentation**: Codex, Claude Code, ZCode, Antigravity, and WorkBuddy expose different skill and MCP entry points. Adding a single skill otherwise requires updating several paths.
- **Upstream Prompt Drift**: A third-party skill quietly updates upstream with breaking changes, degrading agent behavior without any commit history.
- **Over-Engineered Meta-Agents**: You want clean management, not a bloated daemon that hijacks your API keys or proxies your network traffic.

**skills-manager** solves this by unifying all your AI skills and MCP servers into a single, version-controlled `skills.json`. It pins exact Git commit SHAs (`skills.lock.json`) and projects cleanly into each host using native Windows junctions or configurations—**without touching your API keys, models, or network traffic**.

```text
                    ┌─── [ skills.json ] (Single Source of Truth) ───┐
                    │   • Upstream Skill Sources & Git SHA Locks      │
                    │   • Unified MCP Server Profiles (coding/web)    │
                    └──────────────────────┬─────────────────────────┘
                                           │
                             pwsh .\skills.ps1 构建生效
                                           │
       ┌──────────────┬────────────────────┼───────────────────┬──────────────┐
       ▼              ▼                    ▼                   ▼              ▼
  OpenAI Codex   Claude Code             ZCode            Antigravity     WorkBuddy
(~/.agents/skills) (~/.claude/skills)    (~/.zcode/skills)   (~/.gemini/...) (Local targets)
```

---

## Key Features

- 🎯 **One Config, Multiple Hosts**: Managed projection adapters for OpenAI Codex, Claude Code, ZCode, Antigravity (Gemini), and WorkBuddy. Projection does not by itself prove a fresh host session loaded the skill or that a live workflow passed.
- 🔒 **Version-Locked (Lockfile)**: `skills.lock.json` pins exact commit hashes to protect your prompt supply chain against breaking changes.
- 🔌 **Unified MCP Management**: Configure `stdio` or Streamable HTTP compatible MCP servers once. Switch profiles (`coding`, `browser`, `database`, `off`) and sync to the targets declared in `skills.json` with a single command.
- 🔍 **Target Repo Capability Audit**: Scan any local project repository, detect missing domain capabilities, and generate a safe, verifiable 3-file decision package (Snapshot -> Recommendation -> Receipt).
- 💻 **Interactive TUI Menu**: Launch `skills.cmd` to browse, pick, install, and sync skills using a clean terminal menu.
- 📦 **Portable & USB-Ready**: Pre-built `portable.zip` for offline / USB workflows without altering host settings.
- 🛡️ **Zero Hijacking**: Runs entirely locally. Does not touch API keys, does not proxy prompts, and has no daemon services.

---

## Host Support Matrix

| AI Host | Skill Projection | Default Profile | MCP Target Format |
| :--- | :--- | :--- | :--- |
| **OpenAI Codex** | Shared `~/.agents/skills`; optional Agent Bridge writes `~/.codex/agents` | `core-lean` (7 curated) | Native Codex MCP config |
| **Claude Code** | User-level `~/.claude/skills` junctions; Agent Bridge separately writes `~/.claude/agents` subagent definitions | `core-lean` (7 curated) | `~/.claude.json` / Desktop config |
| **ZCode** | `~/.zcode/skills` junction | `core-lean` (7 curated) | `~/.zcode/cli/config.json` |
| **Antigravity (Gemini)** | `~/.gemini/config/skills` junction | `core-ops` (8 enhanced) | `mcp_config.json` |
| **WorkBuddy** | Managed local targets | `core-ops` (8 enhanced) | Standard workspace config |

---

## Quick Start

Prerequisites: **Windows 10 / 11** with **PowerShell 7+** (`pwsh`) and **Git**. (*Windows PowerShell 5.1 is unsupported*).

### Option A: GitHub Release Pre-built Package (Recommended)

Grab the latest release from [GitHub Releases](https://github.com/sciman-top/skills-manager/releases):

1. **Standard One-Step Setup**: Download `bootstrap.zip`, extract, and run:
   ```cmd
   .\setup.cmd
   ```
2. **Portable Edition (Offline / USB)**: Download `portable.zip` and run `skills.cmd`. It does not write to system host directories automatically.

> SHA-256 checksums are published in `SHA256SUMS.txt`. For details, see the [Installation and Migration Guide](docs/INSTALLATION_AND_MIGRATION.md).

### Option B: Run from Source / Interactive Menu

```powershell
git clone https://github.com/sciman-top/skills-manager.git
cd skills-manager
```

Double-click or run `skills.cmd` to open the interactive TUI menu:

```powershell
.\skills.cmd
```

```text
==============================================
         Skills Manager (Interactive Menu)
==============================================
  [1] Browse Skills      - View all available skills in sources
  [2] Pick Install       - Interactively select and install
  [3] Paste Command      - Parse and import add / npx commands
  [4] Rebuild & Sync     - Build & safely project to AI hosts
  [5] Update Upstream    - Pull updates for third-party skills
  [6] Target Repo Audit  - Scan repositories for missing skills
  [7] MCP Services       - Manage & sync MCP servers
  [8] Doctor             - Run environment health check
==============================================
```

---

## Common Commands

Keep the daily path short: `discover → install/lock → check updates → build and project → doctor`. Target audits, rule projection, migration, the native-agent bridge, and model presets are advanced maintenance capabilities rather than mandatory steps for every coding task.

### 1. Skills Management

```powershell
# Discover available skills across sources
.\skills.ps1 发现

# Interactively choose and install skills
.\skills.ps1 安装

# Add a single skill from GitHub
.\skills.ps1 add <github-user/repo> --skill <skill-name>

# Check upstream skill changes (read-only query)
.\skills.ps1 check-updates --json

# Pull updates and refresh the lockfile
.\skills.ps1 更新 -Upgrade

# Rebuild and safely project to AI hosts
.\skills.ps1 构建生效

# Project only to selected hosts (e.g., Codex and Claude)
.\skills.ps1 构建生效 -ProjectionHosts codex,claude
```

### 2. MCP Server Management

```powershell
# Add a stdio MCP server
.\skills.ps1 安装MCP fetch -- uvx mcp-server-fetch

# Add a Streamable HTTP remote MCP server
.\skills.ps1 安装MCP remote-api --transport http --url https://api.example.com/mcp

# List all MCP profiles
.\skills.ps1 MCP配置 列表

# Switch active MCP profile (e.g. coding profile)
.\skills.ps1 MCP配置 使用 coding

# Sync active profile to all installed AI hosts
.\skills.ps1 同步MCP
```

### 3. Target Repo Audit

Scan your other projects to identify needed AI agent capabilities:

```powershell
# 1. Register a project
.\skills.ps1 审查目标 添加 my-project D:\CODE\my-project

# 2. Scan requirements and generate snapshot
.\skills.ps1 审查目标 扫描

# 3. Preflight and dry-run recommendations
.\skills.ps1 审查目标 预检 --recommendations <recommendations.json>

# 4. Explicitly apply verified changes
.\skills.ps1 审查目标 应用 --recommendations <recommendations.json> --apply --yes
```

### 4. Cross-Machine Migration

```powershell
# Package all current skills + MCP into a private snapshot on machine A:
.\skills.ps1 迁移 --mode private-all --version v2026.10

# Restore instantly on machine B:
.\skills.ps1 migration-apply
```

---

## Distribution Packages

| Package | Distribution File | Description |
| :--- | :--- | :--- |
| **Standard Setup** | `bootstrap.zip` | Public release package deployed via `setup.cmd`. |
| **Portable** | `portable.zip` | Standalone portable package for USB / offline environments. |
| **Source** | `source.zip` or Git clone | Full development source archive. |
| **Private Snapshot** | `private-all.zip` | Plaintext private migration bundle for personal transfers. |

---

## Architectural Integrity

- **No Hijacking**: Does not manage models, intercept tokens, or hijack inference routes.
- **Verification Hierarchy**: Strictly enforces `repo_verified -> filesystem_projected -> host_loaded -> live_accepted`.
- **Fail-Closed Safety**: Supports `--plan` preview for rule and MCP mutations, preventing configuration contamination.
- For model orchestration presets, see [Model Orchestration](src/model-orchestration/README.md).

---

## Development & Gates

```powershell
# Build the CLI bundle
pwsh -NoProfile -File .\build.ps1

# Check for generated file drift
pwsh -NoProfile -File .\build.ps1 -Check

# Run automated local quality gates
pwsh -NoProfile -File .\scripts\quality\run-local-quality-gates.ps1 -Profile auto
```

---

## License

This project is licensed under the [MIT License](LICENSE). Third-party skills and dependencies remain subject to their respective upstream licenses.
