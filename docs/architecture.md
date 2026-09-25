# Architecture

Hoplon is a distribution, not a fork. It wraps a pinned OpenCode binary with an
isolated home, a Venice-only config, an OMO routing layer, and a red-team roster.
This page describes how the pieces fit.

## Components

| Component | Role | Where |
| --- | --- | --- |
| `hoplon` | launcher: isolation, seed, OMO conflict handling, sandbox | repo root |
| `scripts/install.sh` | fetch and verify the opencode binary, pre-seed caches | `scripts/` |
| OpenCode | the agent runtime | `bin/opencode` (fetched) |
| Oh My OpenAgent | agent and category routing, background tasks, team mode | npm plugin |
| Magic Context | long-session context management and compaction | npm plugin |
| Venice provider | inference, OpenAI-compatible | OpenCode built-in |
| Venice MCP server | 31 tools over the Venice API | `npx` |
| Red-team agents | six specialist subagents | `agents/` |
| Skills | 5 red-team + 20 Venice API skills | `skills/` |

## Launch flow

```text
./hoplon
  |
  +-- resolve HOPLON_HOME from script location
  +-- capture HOPLON_HOST_HOME
  +-- source .env
  +-- isolate HOME and XDG into ./home
  +-- unset host OPENCODE_* selectors
  +-- disable autoupdate and OMO telemetry
  +-- preflight: bin/opencode, config/opencode.jsonc, VENICE_API_KEY
  +-- (doctor? print report and exit)
  +-- seed config, themes, agents, tui into isolated home
  +-- seed git identity and login-shell profile
  +-- OMO conflict handling (takeover + restore trap)
  +-- (sandbox? wrap in bwrap)
  +-- run bin/opencode as a child process (not exec)
```

The launcher does not `exec` opencode. It runs `bin/opencode` as a child
process (not `exec`) so the `EXIT`/`INT`/`TERM`/`HUP` trap can restore a
taken-over host config.

## Isolation boundary

The launcher is the security boundary. It isolates `HOME` and all four XDG
variables, drops host `OPENCODE_*` selectors, and seeds config by copy. See
[Isolation](isolation.md).

## Configuration layers

| Layer | File | Owns |
| --- | --- | --- |
| OpenCode | `config/opencode.jsonc` | provider, agents, MCP, permissions, runtime |
| OMO | `config/omo.jsonc` | agent and category routing, concurrency, team mode |
| TUI | `config/tui.json` | theme and TUI plugin |

The launcher seeds OpenCode config into `$XDG_CONFIG_HOME/opencode/` and OMO
config into `$HOME/.omo/`. OMO discovers its config by walking `.omo/omo.jsonc`
upward plus the user layer; the launcher handles the case where a host file
would override the routing.

## Model routing

All inference goes to Venice through OpenCode's built-in venice provider. The
`whitelist` restricts the catalog to seven uncensored models. OMO maps each
agent and category to one of them. See [Models](models.md).

## MCP topology

Twelve MCP servers are declared. `venice` is enabled; the rest are disabled.
Weapon tools are globally gated off and re-enabled per agent. See
[MCP servers](mcp-servers.md).

## Context management

Magic Context owns compaction. OMO's `preemptive-compaction` hook is disabled to
avoid two systems compacting at once. `config/opencode.jsonc` also enables
`compaction.auto` and `compaction.prune`.

## Portability

The repository is the source of truth. Runtime state lives in `./home`, which is
gitignored. Copy the tree anywhere and `HOPLON_HOME` resolves to the new
location. Nothing outside the tree is written except the temporary OMO takeover,
which is restored on exit.

## Testing

The `tests/` directory holds shell tests: config parsing, whitelist count,
launcher behavior, and the no-dash check. CI runs them on push and pull request.
See `.github/workflows/`.
