# Hoplon

A portable, uncensored, red-team-focused OpenCode distribution. It runs on
Venice AI, carries the Oh My OpenAgent (OMO) harness, and ships a custom
`hoplon` skin, a red-team agent roster, and rules-of-engagement skills. The
whole thing lives in this repository: clone it, install the binary, set one API
key, and run.

Hoplon is built for authorized offensive security work. It removes the
platform-level content filter between the operator and the task, and it assumes
the operator is a professional who will keep the engagement inside scope. See
[Rules of Engagement](#rules-of-engagement) and [Legal notice](#legal-notice).

## What it is

- A **self-contained OpenCode install**. The launcher isolates `HOME` and every
  XDG directory into `./home`, so Hoplon never reads or writes the host's
  OpenCode or OMO state.
- **Venice AI only**. Every model route points at Venice's uncensored family,
  with the strongest agentic models used where coding quality matters.
- **OMO harness**. The Oh My OpenAgent plugin supplies the agent and category
  routing, background tasks, and team mode.
- **Red-team tooling**. Six specialist subagents and five offense skills, gated
  by a mandatory rules-of-engagement skill.

## Layout

```
hoplon/
  hoplon                 launcher (isolated HOME, seed, OMO conflict handling)
  bin/                   bundled opencode binary (fetched by install.sh)
  config/
    opencode.jsonc       provider, agents, MCP servers, permissions
    omo.jsonc            OMO agent + category routing (all Venice)
    tui.json             theme and TUI settings
  themes/hoplon.json     the hoplon skin
  agents/                six red-team subagents (markdown)
  skills/                five red-team skills
  scripts/install.sh     binary fetch + optional OMO cache pre-seed
  .env.example           environment template
  home/                  isolated runtime state (gitignored)
```

## Install

Requirements: `bash`, `curl`, and either `tar` (Linux) or `unzip` (macOS). The
installer supports Linux and macOS on `x64` and `arm64`.

```bash
git clone <this-repo> hoplon
cd hoplon
scripts/install.sh
cp .env.example .env      # then set VENICE_API_KEY
./hoplon
```

`scripts/install.sh` downloads a pinned opencode binary into `bin/`. The default
version is `1.18.25`, overridable with `HOPLON_OPENCODE_VERSION`. The release
repo defaults to `anomalyco/opencode`, overridable with `HOPLON_OPENCODE_REPO`.
If a host OMO plugin cache exists at `~/.cache/opencode/packages/oh-my-openagent@5.0.0-beta.62`,
the installer copies it into the isolated home to speed up first launch and to
support offline use.

Get a Venice API key at <https://venice.ai> and put it in `.env` as
`VENICE_API_KEY`. The launcher sources `.env` on every run. Optional keys for
the offensive MCP servers (`SHODAN_API_KEY`, `NVD_API_KEY`, `VIRUSTOTAL_KEY`,
`GREYNOISE_API_KEY`, `NEO4J_PASSWORD`, `MSF_PASSWORD`) are only needed when you
enable those servers.

## Run

```bash
./hoplon                 # TUI in the current directory
./hoplon run "..."       # one-shot prompt
./hoplon <project>       # TUI on a project directory
./hoplon --help          # opencode CLI help
```

## Isolation model

The launcher is the security boundary. On every launch it:

1. Sets `HOME` to `./home` and points all four XDG variables
   (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME`)
   inside it. This is explicit because xdg-basedir resolves those from the
   environment at import time, and a host-exported XDG variable would otherwise
   leak state out.
2. Unsets host `OPENCODE_*` selectors (`OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR`,
   `OPENCODE_CONFIG_CONTENT`, `OPENCODE_TUI_CONFIG`, `OPENCODE_PERMISSION`,
   `OPENCODE_DB`, `OPENCODE_MODELS_PATH`, `OPENCODE_MODELS_URL`).
3. Disables autoupdate (`OPENCODE_DISABLE_AUTOUPDATE=1`) and OMO telemetry
   (`OMO_DISABLE_POSTHOG=1`, `OMO_SEND_ANONYMOUS_TELEMETRY=0`).
4. Puts `bin/` first on `PATH`.
5. Seeds config, theme, agents, and the OMO config into the isolated home on
   every launch. It copies rather than symlinks, because OMO rewrites its config
   with a temp-file plus rename replace, which would sever a symlink inode.
6. Seeds a git identity (`Hoplon Operator <operator@hoplon.local>` with
   `safe.directory=*`) and a login-shell `PATH` shim, since opencode's bash tool
   spawns login shells and `/etc/profile` can rebuild `PATH`.

Host credentials are absent by design. Two opt-in passthroughs exist:
`HOPLON_SHARE_SSH=1` symlinks the host `~/.ssh` into the isolated home, and
`HOPLON_SHARE_GH=1` symlinks the host `~/.config/gh`. `HOPLON_HOST_HOME`
overrides the real account home captured at launch.

### OMO conflict handling

OMO discovers its config by walking `.omo/omo.jsonc` from the working directory
upward (project layer) plus a user layer at `$HOME/.omo`. Because the isolated
`HOME` is not an ancestor of the working directory, a host `~/.omo/omo.jsonc`
that sits above the working directory is read as a **project** layer and would
override Hoplon's Venice routing.

The launcher detects that case, backs the host file up, takes it over for the
session, and restores it on exit (including on `INT` and `TERM`, with a
self-heal path if a prior run died before restoring). The practical consequence:
on a clean machine nothing on the host is touched; on a machine that already
uses OMO, the host file is temporarily swapped and restored. Set
`HOPLON_OMO_TAKEOVER=0` to disable the takeover and let the host config win.

## Model routing

All inference runs on Venice AI through the OpenAI-compatible adapter
(`@ai-sdk/openai-compatible`), base URL `https://api.venice.ai/api/v1`, key from
`VENICE_API_KEY`. Model references are always `venice/<model-id>`. The uncensored
models are used where it counts, with strong agentic models for pure coding.

### Agents

| Agent | Model |
| --- | --- |
| sisyphus, prometheus, hephaestus, atlas, build, plan, reviewer, frontend | `venice/qwen-3-6-plus` |
| oracle, metis, momus | `venice/aion-labs-aion-3-5` |
| sisyphus-junior, explore, librarian | `venice/olafangensan-glm-4.7-flash-heretic` |
| multimodal-looker | `venice/qwen-3-8-27b` |

### Categories

| Category | Model |
| --- | --- |
| visual-engineering, deep, unspecified-high | `venice/qwen-3-6-plus` |
| ultrabrain | `venice/aion-labs-aion-3-5` |
| quick, unspecified-low | `venice/olafangensan-glm-4.7-flash-heretic` |
| artistry, writing | `venice/venice-uncensored-1-2` |

The declared models, with their context and output limits, are:

| Model ID | Context | Output | Notes |
| --- | --- | --- | --- |
| `qwen-3-6-plus` | 1,000,000 | 65,536 | Uncensored flagship: code, reasoning, vision, tools |
| `aion-labs-aion-3-5` | 262,144 | 32,768 | Uncensored deep reasoning |
| `olafangensan-glm-4.7-flash-heretic` | 200,000 | 32,768 | Cheap uncensored reasoner with tools |
| `venice-uncensored-1-2` | 131,072 | 16,384 | Most-uncensored Venice model: chat, vision, tools |
| `qwen-3-8-27b` | 262,144 | 65,536 | Uncensored vision |
| `gemma-4-uncensored` | 262,144 | 32,768 | Uncensored vision chat |
| `z-ai-glm-5-3-flash` | 1,000,000 | 131,072 | Strong agentic coder |
| `deepseek-v4-pro-0813` | 1,000,000 | 32,768 | Default-code model |

### Venice-only features

The OpenAI-compatible adapter passes the model string through verbatim, so
Venice-only features can be enabled with model-ID suffixes. For example:

```
venice/venice-uncensored-1-2:enable_web_search=on
```

The same mechanism carries Venice's prompt-control suffixes. Set these on the
agent or category model string when a task needs them.

## MCP servers

Two recon and intel servers are enabled by default. The weapon servers are
present but disabled, and are enabled per specialist agent through each agent's
`tools` map. Every server that wraps a CLI tool requires the underlying binary
on `PATH`.

| Server | Type | Default | Requirement |
| --- | --- | --- | --- |
| `shodan` | local | enabled | `npx`, `SHODAN_API_KEY` |
| `cve` | local | enabled | `uvx`, optional NVD / VirusTotal / GreyNoise keys |
| `nmap` | local | disabled | `npx`, `mcp-nmap-server` |
| `pentest` | local | disabled | `npx`, `pentest-mcp` |
| `nuclei` | local | disabled | Docker image `nuclei-mcp:latest` |
| `sqlmap` | local | disabled | Docker image `sqlmap-mcp:latest` |
| `ffuf` | local | disabled | Docker image `ffuf-mcp:latest` |
| `burp` | remote | disabled | Burp BApp running, SSE at `http://127.0.0.1:9876` |
| `metasploit` | local | disabled | `/opt/MetasploitMCP`, `MSF_PASSWORD` |
| `bloodhound` | local | disabled | `/opt/BloodHound-MCP-AI`, Neo4j at `bolt://localhost:7687` |
| `ghidra` | local | disabled | Docker image `ghidra-mcp:latest`, samples at `/samples` |

Globally, the weapon tools are gated off (`nmap*`, `pentest*`, `nuclei*`,
`sqlmap*`, `ffuf*`, `burp*`, `metasploit*`, `bloodhound*`, `ghidra*` are all
`false`). An agent re-enables only what it owns.

## Red-team agents

Each agent is a markdown file in `agents/`, seeded into the isolated config on
launch.

| Agent | Role |
| --- | --- |
| `recon` | Passive and active asset discovery, service enumeration, attack-surface mapping |
| `web-attacker` | Web app testing: endpoint and parameter discovery, injection, access control, business logic |
| `ad-attacker` | Active Directory attack-path analysis toward Tier Zero, via BloodHound |
| `exploit-dev` | Weaponizes validated vulnerabilities into reliable, controlled exploits |
| `reverser` | Static analysis of binaries, firmware, and protocols with Ghidra |
| `report-writer` | Turns raw findings and evidence into a client-ready report |

## Red-team skills

Skills live in `skills/` and are loaded from `{env:HOPLON_HOME}/skills`.

| Skill | Purpose |
| --- | --- |
| `redteam-roe` | The mandatory rules-of-engagement gate. Loaded first, before any active action |
| `redteam-recon` | Recon methodology, passive first then active |
| `redteam-web` | Web testing mapped to OWASP WSTG categories |
| `redteam-exploit` | Exploitation and proof-of-concept development |
| `redteam-report` | Client-ready reporting with CVSS and remediation |

## Rules of Engagement

The `redteam-roe` skill gates every other offense skill. No active action runs
until it passes. Before any scanning, exploitation, or authenticated interaction
with a target:

1. Confirm there is written authorization for the engagement.
2. Confirm the exact scope: in-scope hosts, CIDRs, domains, accounts, and the
   time window.
3. If authorization or scope is missing, ambiguous, or expired, stop and ask.

Passive and public-source collection does not require the same gate. The moment
you send packets to, authenticate against, or modify a target, it does. The
scope is the contract. When the ROE and a convenient shortcut disagree, the ROE
wins.

## Legal notice

Use Hoplon only against systems you own or have explicit written authorization
to test. Unauthorized access, scanning, or exploitation is illegal in most
jurisdictions and can carry criminal and civil liability. The operator is solely
responsible for staying inside scope and for complying with all applicable
laws. The authors and maintainers of this distribution accept no liability for
misuse.

## Offline and portability notes

Hoplon is designed to be copied and run, but a few components are fetched on
first use and are not bundled:

- **OMO plugin**. Pre-seed the cache with `scripts/install.sh` (it copies a host
  cache if present), or vendor the plugin and reference it as a path plugin.
- **LSP servers**. Downloaded on first use.
- **`npx` / `uvx` MCP servers**. Downloaded on first use.
- **OMO's ast-grep runtime**. Downloaded on first use.

For a fully offline copy, vendor all of the above. The opencode binary itself is
large (roughly 180 MB) and is gitignored, so it is fetched by the installer
rather than committed.

## Verified

The launcher was tested to keep OMO routing on Venice when a host OMO config
sits above the working directory, and to restore that host config on exit. The
takeover is transparent: the host file is backed up, swapped for the session,
and put back when opencode exits, including on interrupt.
