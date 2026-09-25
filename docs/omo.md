# OMO

Hoplon loads the Oh My OpenAgent (OMO) plugin as its agent and category routing
layer. This page explains what OMO provides, its license, and how to run Hoplon
without it.

## What OMO provides

- Agent and category routing (`config/omo.jsonc`).
- Background tasks with per-provider and per-model concurrency limits.
- Team mode (`max_parallel_members: 4`, tmux visualization).
- The `sisyphus`, `prometheus`, `metis`, `momus`, `hephaestus`, `atlas`,
  `sisyphus-junior`, and `librarian` agents.

## License disclosure

**OMO is not open source in the OSI sense.** It is distributed under the
Sustainable Use License (SUL-1.0), a source-available license with use
restrictions. It is loaded as an npm plugin at runtime and is **not
redistributed in this repository**. Read the license before you use it
commercially.

| Component | Package | Version | License |
| --- | --- | --- | --- |
| Oh My OpenAgent | `oh-my-openagent` | `5.0.0-beta.62` | SUL-1.0 (source-available) |

See [THIRD_PARTY_NOTICES.md](https://github.com/ShibbityShwab/hoplon/blob/main/THIRD_PARTY_NOTICES.md) for the full provenance
list, including OpenCode, Magic Context, the Venice MCP server, and the Venice
skills.

## The plugin entry

`config/opencode.jsonc` loads two plugins:

```jsonc
"plugin": [
  "oh-my-openagent@5.0.0-beta.62",
  "@cortexkit/opencode-magic-context@0.43.1"
]
```

Keep exactly one `oh-my-openagent` entry. Magic Context owns compaction, so
`config/omo.jsonc` disables OMO's `preemptive-compaction` hook to avoid two
systems compacting at once.

## Running without OMO

Set `HOPLON_ENABLE_OMO=0` to skip the OMO plugin and its config seeding. The
launcher also repoints `default_agent` from `sisyphus` to `build`, because
`sisyphus` is registered by OMO only.

```bash
HOPLON_ENABLE_OMO=0 ./hoplon
```

In that mode you get:

- Plain OpenCode on the Venice provider.
- The Hoplon agents, themes, and skills.
- The OpenCode-native agent roster from `config/opencode.jsonc`.

You do not get:

- OMO agent and category routing.
- Background tasks.
- Team mode.
- The OMO-specific agents (`sisyphus`, `prometheus`, `metis`, `momus`,
  `hephaestus`, `atlas`, `sisyphus-junior`, `librarian`).

## OMO config discovery

OMO reads a user layer at `$HOME/.omo/omo.jsonc` plus a project `.omo/omo.jsonc`
walked upward from the working directory. The launcher copies `config/omo.jsonc`
to the user layer in the isolated home. If a host `~/.omo/omo.jsonc` sits above
the working directory, the launcher takes it over for the session and restores
it on exit. See [Isolation](isolation.md).

## Telemetry

OMO telemetry is off:

```bash
export OMO_DISABLE_POSTHOG=1
export OMO_SEND_ANONYMOUS_TELEMETRY=0
```

`config/omo.jsonc` also sets `"telemetry": false`.

## Offline use

The OMO plugin is fetched on first use. `scripts/install.sh` pre-seeds the
plugin cache from the host if present, so a machine that already uses OMO can
run Hoplon offline. To vendor it fully, copy the plugin into the repo and
reference it as a path plugin. Warning: redistributing OMO falls outside the
Sustainable Use License (SUL-1.0) for commercial use; copying the plugin into
the repo is for private offline use only.
