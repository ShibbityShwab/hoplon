# Hoplon

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![CI](https://github.com/ShibbityShwab/hoplon/actions/workflows/ci.yml/badge.svg)](https://github.com/ShibbityShwab/hoplon/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/ShibbityShwab/hoplon)](https://github.com/ShibbityShwab/hoplon/releases)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

A portable, uncensored, red-team-focused OpenCode distribution. It runs on
Venice AI, carries the Oh My OpenAgent (OMO) harness, and ships a custom `hoplon`
skin, a red-team agent roster, and rules-of-engagement skills. The whole thing
lives in this repository: clone it, install the binary, set one API key, and run.

Hoplon is built for authorized offensive security work. It removes the
platform-level content filter between the operator and the task, and it assumes
the operator is a professional who will keep the engagement inside scope. See
[Rules of Engagement](#rules-of-engagement) and [Legal notice](#legal-notice).

## Table of contents

- [Philosophy](#philosophy)
- [What it is](#what-it-is)
- [How it compares](#how-it-compares)
- [Layout](#layout)
- [Install](#install)
- [Run](#run)
- [Doctor](#doctor)
- [Sandbox](#sandbox)
- [Isolation model](#isolation-model)
- [OMO and the SUL-1.0 license](#omo-and-the-sul-10-license)
- [Model routing](#model-routing)
- [MCP servers](#mcp-servers)
- [Red-team agents](#red-team-agents)
- [Skills](#skills)
- [Rules of Engagement](#rules-of-engagement)
- [Hardening](#hardening)
- [How to verify](#how-to-verify)
- [Documentation](#documentation)
- [Legal notice](#legal-notice)
- [Offline and portability notes](#offline-and-portability-notes)

## Philosophy

Three commitments shape every choice in this build.

**Freedom should be free.** The point of a local agent is that it works for you,
not for a platform. Hoplon ships open source under AGPL-3.0, sends no telemetry
of its own, and puts no gatekeeper between you and the model. There is no signup
wall, no usage dashboard, no "contact sales" tier. The one thing you bring is a
Venice API key, and the key talks straight to the API. The launcher disables
OpenCode autoupdate and OMO's PostHog telemetry (`OPENCODE_DISABLE_AUTOUPDATE=1`,
`OMO_DISABLE_POSTHOG=1`, `OMO_SEND_ANONYMOUS_TELEMETRY=0`) so a portable copy
stays frozen and quiet.

**Credit where due.** Hoplon is a distribution, not a from-scratch agent. It
stands on OpenCode, the Oh My OpenAgent harness, the Magic Context plugin,
Venice's MCP server, and the Venice API skills. Each is named in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) with its license and provenance.
Nothing here is claimed as original work that is not.

**This is an opinionated build.** Hoplon makes choices for you: Venice only,
uncensored models only, YOLO permissions by default, a red-team roster, and a
rules-of-engagement gate. If you want a neutral, provider-agnostic OpenCode, use
vanilla OpenCode. Hoplon is tuned for one job and does not pretend to be
everything to everyone.

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
- **Venice-native tooling**. Venice's own MCP server (31 tools) and the 20
  official Venice API skills, so the agent can call Venice beyond chat:
  embeddings, image, video, audio, music, characters, web augment, crypto RPC.
- **Hoplon identity**. A solid bronze-on-iron `hoplon` theme (with a transparent
  `hoplon-ghost` variant) plus a TUI plugin that replaces the stock OpenCode logo
  with the HOPLON home banner.

## How it compares

| | Vanilla OpenCode | Generic OpenCode distributions | Hoplon |
| --- | --- | --- | --- |
| Provider | Bring your own, any | Usually one or many | Venice AI only |
| Content filtering | Depends on provider | Depends on provider | Venice uncensored family, no platform filter |
| Model catalog | Full models.dev catalog | Varies | Seven uncensored models, allowlisted |
| Agent roster | Default agents | Varies | Default agents plus six red-team specialists |
| Rules of engagement | None | None | Mandatory `redteam-roe` gate |
| Isolation | Host `HOME` | Varies | Isolated `HOME` and XDG under `./home` |
| Sandbox | None | Varies | Optional bubblewrap (`HOPLON_SANDBOX=1`) |
| Telemetry | Provider-dependent | Varies | Off (OpenCode autoupdate and OMO PostHog disabled) |
| License | MIT (upstream) | Varies | AGPL-3.0, with OMO disclosed as source-available |

The short version: vanilla OpenCode is a general tool you configure. Hoplon is a
configured tool for one job. If you want to pick your own providers and models,
start from OpenCode. If you want an uncensored red-team console that is ready on
clone, start here.

## Layout

```text
hoplon/
  hoplon                 launcher (isolated HOME, seed, OMO conflict handling)
  bin/                   bundled opencode binary (fetched by install.sh)
  config/
    opencode.jsonc       provider, agents, MCP servers, permissions
    omo.jsonc            OMO agent + category routing (all Venice)
    tui.json             theme and TUI settings
  themes/
    hoplon.json          the hoplon skin
    hoplon-ghost.json    transparent variant
  tui/hoplon-brand.tsx   TUI plugin: HOPLON home-screen banner
  agents/                six red-team subagents (markdown)
  skills/                5 red-team skills + 20 vendored Venice API skills
  scripts/install.sh     binary fetch + optional OMO cache pre-seed
  tests/                 shell tests (config, launcher, no-dash)
  .github/               CI, docs, scorecard workflows, issue and PR templates
  AGENTS.md              operator persona and rules of engagement
  THIRD_PARTY_NOTICES.md third-party provenance and licenses
  .env.example           environment template
  home/                  isolated runtime state (gitignored)
```

## Install

Requirements: `bash`, `curl`, and either `tar` (Linux) or `unzip` (macOS). The
installer supports Linux and macOS on `x64` and `arm64`.

```bash
git clone https://github.com/ShibbityShwab/hoplon.git hoplon
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

See [docs/installation.md](docs/installation.md) for the full walkthrough,
including the optional `HOPLON_OPENCODE_SHA256` integrity pin.

## Run

```bash
./hoplon                  # TUI in the current directory
./hoplon run "..."        # one-shot prompt
./hoplon <project>        # TUI on a project directory
./hoplon doctor           # report binary, key, sandbox, MCP and weapon tooling
HOPLON_SANDBOX=1 ./hoplon # run inside a bubblewrap sandbox
./hoplon --help           # opencode CLI help
```

## Doctor

`./hoplon doctor` is the first thing to run on a new box. It reports the opencode
version, whether `VENICE_API_KEY` is set, whether `bwrap` is available, which MCP
runtimes exist (`node`/`npx`, `uvx`, `docker`), which weapon binaries are
installed (`nmap`, `nuclei`, `sqlmap`, `ffuf`, `msfconsole`, `ghidra`), and
whether Venice is reachable. It does not seed config or launch the TUI.

## Sandbox

`HOPLON_SANDBOX=1` wraps opencode in `bubblewrap`. The host filesystem is hidden
except this repository and the target directory, the network stays up for the
Venice API, and the process runs in its own user, pid, ipc, and uts namespaces.
It requires `bwrap`. Everything under `/usr` is available and works: `grep`,
`sed`, `awk`, `curl` (TLS verified), `wget`, `ping`, `dig`, `openssl`, `ssh`,
`nmap`, `git`, `python3`, `node`, `npx`, `uvx`, `jq`, `docker`, `rg`, and the
rest of coreutils. DNS resolves, HTTPS reaches Venice, and `nmap -sT` (TCP
connect) works.

Two limits: raw-socket tooling (`nmap -sS`, ARP sweeps, packet capture) needs
`CAP_NET_RAW` and fails inside, and tools installed in the host user home
(`~/.local/bin`, `~/.cargo/bin`, `~/go/bin`, `~/.bun/bin`) are not mounted unless
you set `HOPLON_SANDBOX_BINS=1`. Host credentials under `~/.ssh` and `~/.config`
are not visible, `/etc/shadow` is not readable, and `/usr` is read-only. Run
raw-socket work unsandboxed with `HOPLON_SANDBOX=0`. Use the sandbox when
handling untrusted content or running risky code, not for raw-socket
reconnaissance.

Full detail in [docs/sandbox.md](docs/sandbox.md).

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

Full detail in [docs/isolation.md](docs/isolation.md).

## OMO and the SUL-1.0 license

Hoplon loads the Oh My OpenAgent (OMO) plugin, `oh-my-openagent@5.0.0-beta.62`,
as its agent and category routing layer. **OMO is not open source in the OSI
sense.** It is distributed under the Sustainable Use License (SUL-1.0), a
source-available license with use restrictions. It is loaded as an npm plugin at
runtime and is **not redistributed in this repository**. Read the license before
you use it commercially. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
and [docs/omo.md](docs/omo.md).

Because OMO is optional, Hoplon can run without it. Set `HOPLON_ENABLE_OMO=0` to
skip the OMO plugin and its config seeding. In that mode you get plain OpenCode
on the Venice provider with the Hoplon agents, themes, and skills, but no OMO
agent/category routing, background tasks, or team mode.

## Model routing

All inference runs on Venice AI through OpenCode's built-in venice provider,
base URL `https://api.venice.ai/api/v1`, key from `VENICE_API_KEY`. Model
references are always `venice/<model-id>`. Do not add an `"npm"` override to
`provider.venice`: the built-in provider lowers options into Venice's
`venice_parameters` (snake_case), and forcing a generic adapter bypasses that and
sends a camelCase object the API ignores.

### Agents

| Agent | Model |
| --- | --- |
| sisyphus, prometheus, oracle, hephaestus, atlas, build, plan, reviewer, frontend | `venice/qwen-3-6-plus` |
| metis, momus, multimodal-looker, asset-qa | `venice/qwen-3-8-27b` |
| sisyphus-junior, explore, librarian | `venice/olafangensan-glm-4.7-flash-heretic` |

### Categories

| Category | Model |
| --- | --- |
| visual-engineering, deep, ultrabrain, unspecified-high | `venice/qwen-3-6-plus` |
| quick, unspecified-low | `venice/olafangensan-glm-4.7-flash-heretic` |
| writing | `venice/venice-uncensored-1-2` |
| artistry | `venice/venice-uncensored-role-play` |

### Declared models

Seven models are declared and allowlisted. This is the complete set.

| Model ID | Context | Output | Notes |
| --- | --- | --- | --- |
| `qwen-3-6-plus` | 1,000,000 | 65,536 | Uncensored flagship: code, reasoning, vision, tools |
| `qwen-3-8-27b` | 262,144 | 65,536 | Uncensored: tunable reasoning effort + vision |
| `aion-labs-aion-3-5` | 262,144 | 32,768 | Uncensored deep reasoning |
| `olafangensan-glm-4.7-flash-heretic` | 200,000 | 24,000 | Cheap uncensored reasoner with tools |
| `venice-uncensored-1-2` | 128,000 | 8,192 | Most-uncensored Venice model: chat, vision, tools |
| `venice-uncensored-role-play` | 128,000 | 4,096 | Uncensored role-play and creative writing |
| `gemma-4-uncensored` | 256,000 | 8,192 | Uncensored vision chat |

`provider.venice.whitelist` restricts the catalog to those seven, so the
non-uncensored Venice models cannot be selected. The non-uncensored community
models (`glm-5-3-flash`, `deepseek-v4-pro`) are omitted on purpose: Venice does
not tag them uncensored, so upstream hosts can still filter them.

Reasoning effort is only assigned to models that advertise an effort control
(`qwen-3-8-27b`, `olafangensan-glm-4.7-flash-heretic`). Settings on models
without one (for example `qwen-3-6-plus`) are dropped by the harness rather than
sent, so they are inert. Sampling follows Venice's published per-model
constraints where they exist (`qwen-3-6-plus`: temperature 0.7, top_p 0.8).

Full detail in [docs/models.md](docs/models.md).

## MCP servers

The Venice server is enabled by default. Shodan and the CVE server are present
but off until you add API keys, because they fail without them. The weapon
servers are present but disabled, and are enabled per specialist agent through
each agent's `tools` map. Every server that wraps a CLI tool requires the
underlying binary on `PATH`.

| Server | Type | Default | Requirement |
| --- | --- | --- | --- |
| `venice` | local | enabled | `npx`, `VENICE_API_KEY` |
| `shodan` | local | disabled | `npx`, `SHODAN_API_KEY` |
| `cve` | local | disabled | `uvx`, optional NVD / VirusTotal / GreyNoise keys |
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

Every `npx` and `uvx` server is version-pinned (`@veniceai/mcp-server@0.2.0`,
`@burtthecoder/mcp-shodan@1.0.32`, `cve-mcp-server==0.5.0`, `mcp-nmap-server@1.0.1`,
`pentest-mcp@0.9.0`). The four `docker` images (`nuclei-mcp`, `sqlmap-mcp`,
`ffuf-mcp`, `ghidra-mcp`) are locally built and currently tagged `:latest`; pin
them by tagging each build with the bundled tool version and a date, then pinning
the digest (`docker inspect --format '{{index .RepoDigests 0}}' <image:tag>`).
The `metasploit` and `bloodhound` servers run local checkouts under `/opt`; pin
those by git commit.

Full detail in [docs/mcp-servers.md](docs/mcp-servers.md).

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

The OpenCode-native roster also includes `asset-qa`, a visual asset QA subagent
on `venice/qwen-3-8-27b` for screenshots, textures, model previews, and reference
images, plus `multimodal-looker` for PDFs, images, diagrams, and video frames.

## Skills

Skills live in `skills/` and are loaded from `{env:HOPLON_HOME}/skills`. There
are 25: five red-team skills and 20 vendored Venice AI API skills.

Red-team skills:

| Skill | Purpose |
| --- | --- |
| `redteam-roe` | The mandatory rules-of-engagement gate. Loaded first, before any active action |
| `redteam-recon` | Recon methodology, passive first then active |
| `redteam-web` | Web testing mapped to OWASP WSTG categories |
| `redteam-exploit` | Exploitation and proof-of-concept development |
| `redteam-report` | Client-ready reporting with CVSS and remediation |

Venice skills, vendored verbatim from <https://github.com/veniceai/skills> (MIT):
`venice-api-overview`, `venice-auth`, `venice-api-keys`, `venice-chat`,
`venice-responses`, `venice-text-routing`, `venice-models`, `venice-embeddings`,
`venice-characters`, `venice-image-generate`, `venice-image-edit`,
`venice-video`, `venice-audio-speech`, `venice-audio-transcription`,
`venice-audio-music`, `venice-augment`, `venice-billing`, `venice-x402`,
`venice-crypto-rpc`, `venice-errors`. They give the agent the full Venice API
surface (parameters, feature suffixes, pricing, error shapes) on demand.

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

Full detail in [docs/rules-of-engagement.md](docs/rules-of-engagement.md).

## Hardening

- **Sandbox.** `HOPLON_SANDBOX=1` hides the host filesystem behind bubblewrap
  while keeping the network for the API. This is the real mitigation for the YOLO
  and prompt-injection risks below; raw-socket tools must run outside it.
- **Provider.** Venice runs through OpenCode's built-in venice provider, not a
  generic adapter. Do not add `"npm"` to `provider.venice`: the override bypasses
  the `venice_parameters` lowering and sends a camelCase object the API ignores.
- **Permissions.** Read prompts for `.env`, but bash is allowed, so the agent can
  still reach the key with `cat .env`; treat the key as exposed to the model. The
  bash guards cover `rm`, `dd`, disk tools, recursive chown/chmod, `sudo`, fork
  bombs, and forced pushes, but no glob set stops every destructive command:
  wrappers (`sudo rm`, `bash -c '...'`) and unusual flag orders can slip through.
  Treat YOLO mode as host-level authority and run engagements on a disposable box.
- **Prompt injection.** With web fetch and search allowed, untrusted content can
  reach the model. Keep the API key scoped and prefer a proxy or container when
  working against hostile targets.
- **Install.** `scripts/install.sh` installs by rename, so a killed download
  never leaves a truncated binary, and verifies the archive when
  `HOPLON_OPENCODE_SHA256` is set.
- **Launcher.** The OMO takeover backs up at mode 600, writes atomically, and
  restores on `EXIT`, `INT`, `TERM`, and `HUP`. A `SIGKILL` can still leave the
  host file swapped; the next run from the same tree self-heals from the backup.

Full detail in [docs/security.md](docs/security.md).

## How to verify

Every claim above is checkable from the repository. Run these from the repo
root. They do not need a Venice key.

```bash
# The seven declared models, and only those.
grep -c '"' config/opencode.jsonc >/dev/null   # sanity: file is present
python3 -c "import re;s=open('config/opencode.jsonc').read();m=re.search(r'\"whitelist\":\s*\[(.*?)\]',s,re.S);print(len(re.findall(r'\"([^\"]+)\"',m.group(1))))"
# expected: 7

# MCP defaults: venice enabled, shodan and cve disabled. Target each MCP block
# directly (an "enabled" near the key, not the provider's enabled_providers).
awk '/^    "venice": \{/,/^    \}/' config/opencode.jsonc | grep -m1 enabled
grep -A5 '"shodan"' config/opencode.jsonc | grep enabled
awk '/^    "cve": \{/,/^    \}/' config/opencode.jsonc | grep -m1 enabled

# The launcher and installer parse.
bash -n hoplon
bash -n scripts/install.sh

# The config files parse as JSONC. This is the same normaliser the test suite
# uses in tests/test_config_jsonc.sh: strip // and /* */ comments and trailing
# commas, then pipe strict JSON to jq.
strip_jsonc() {
  awk '
    { text = text $0 "\n" }
    END {
      n = length(text); out = ""; instr = 0; esc = 0; inblock = 0; pending = 0; i = 1
      while (i <= n) {
        c = substr(text, i, 1); two = substr(text, i, 2)
        if (inblock) {
          if (two == "*/") { inblock = 0; i += 2 } else { i++ }
          continue
        }
        if (instr) {
          if (pending) { out = out ","; pending = 0 }
          out = out c
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") { instr = 0 }
          i++; continue
        }
        if (c == "\"") {
          if (pending) { out = out ","; pending = 0 }
          instr = 1; out = out c; i++; continue
        }
        if (two == "//") {
          j = index(substr(text, i), "\n")
          if (j == 0) { i = n + 1 } else { i = i + j - 1 }
          continue
        }
        if (two == "/*") { inblock = 1; i += 2; continue }
        if (c == ",") { pending = 1; i++; continue }
        if (c == "}" || c == "]") { pending = 0; out = out c; i++; continue }
        if (pending && c !~ /[ \t\r\n]/) { out = out ","; pending = 0 }
        out = out c; i++
      }
      printf "%s", out
    }
  ' "$1"
}
strip_jsonc config/opencode.jsonc | jq -e . >/dev/null && echo 'opencode.jsonc ok'
strip_jsonc config/omo.jsonc | jq -e . >/dev/null && echo 'omo.jsonc ok'

# No em dashes or en dashes in project-authored files.
! grep -rlP '[\x{2014}\x{2013}]' README.md AGENTS.md THIRD_PARTY_NOTICES.md .env.example hoplon scripts/install.sh config/ themes/ tui/ agents/ skills/redteam-*/ docs/ && echo "no dashes"

# Doctor reports what the box can do.
./hoplon doctor
```

The `tests/` directory holds the same checks as runnable shell tests.

## Documentation

- [Installation](docs/installation.md)
- [Getting started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [Models](docs/models.md)
- [MCP servers](docs/mcp-servers.md)
- [Sandbox](docs/sandbox.md)
- [Isolation](docs/isolation.md)
- [Rules of engagement](docs/rules-of-engagement.md)
- [OMO](docs/omo.md)
- [Troubleshooting](docs/troubleshooting.md)
- [FAQ](docs/faq.md)
- [Architecture](docs/architecture.md)
- [Security](docs/security.md)

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
- **`npx` / `uvx` MCP servers**. Downloaded on first use; all version-pinned,
  including the Venice MCP server (`@veniceai/mcp-server@0.2.0`).
- **OMO's ast-grep runtime**. Downloaded on first use.

For a fully offline copy, vendor all of the above. The opencode binary itself is
large (roughly 180 MB) and is gitignored, so it is fetched by the installer
rather than committed.

## License

Hoplon is licensed under the GNU Affero General Public License v3.0 or later
(AGPL-3.0-or-later). See [LICENSE](LICENSE). Third-party components retain their
own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
