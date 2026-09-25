# Configuration

Hoplon's configuration is four files in `config/`, seeded into the isolated
home on every launch. The repository is the source of truth: edit here, not in
`./home`, because the launcher overwrites the seeded copies.

| File | Seeded to | Purpose |
| --- | --- | --- |
| `config/opencode.jsonc` | `$HOME/.config/opencode/opencode.jsonc` | provider, agents, MCP servers, permissions, runtime |
| `config/omo.jsonc` | `$HOME/.omo/omo.jsonc` | OMO agent and category routing |
| `config/tui.json` | `$HOME/.config/opencode/tui.json` | theme and TUI settings |
| `config/magic-context.jsonc` | `$HOME/.config/cortexkit/magic-context.jsonc` | Magic Context historian model |

## config/opencode.jsonc

This is the main file. It is JSONC, so comments are allowed.

### Top-level runtime

| Key | Value | Meaning |
| --- | --- | --- |
| `model` | `venice/qwen-3-6-plus` | default model |
| `small_model` | `venice/olafangensan-glm-4.7-flash-heretic` | small/fast model |
| `default_agent` | `sisyphus` | agent the TUI starts on |
| `username` | `operator` | display name |
| `shell` | `/bin/bash` | shell for the bash tool |
| `enabled_providers` | `["venice"]` | only Venice is enabled |
| `autoupdate` | `false` | frozen distribution |
| `share` | `disabled` | no session sharing |
| `lsp` | `true` | language servers on |
| `formatter` | `true` | formatter on |
| `snapshot` | `true` | snapshots on |

### Plugins

```jsonc
"plugin": [
  "oh-my-openagent@5.0.0-beta.62",
  "@cortexkit/opencode-magic-context@0.43.1"
]
```

Keep exactly one `oh-my-openagent` entry. Magic Context owns compaction, so
`config/omo.jsonc` keeps OMO's `preemptive-compaction` hook disabled to avoid
two systems compacting at once.

### Permissions

Hoplon runs YOLO by default, with guards on destructive commands. The matcher
is a text denylist, not a containment boundary: it takes the last matching rule,
so specific rules sit after the `*` catch-all, and wrappers can bypass it.

| Tool | Setting |
| --- | --- |
| `read` | `allow`, except `*.env` and `*.env.*` ask, `*.env.example` allow |
| `edit`, `glob`, `grep`, `list`, `task`, `todowrite`, `question` | `allow` |
| `webfetch`, `websearch`, `lsp`, `doom_loop`, `external_directory` | `allow` |
| `bash` | `allow`, with `ask`/`deny` guards below |

Bash guards:

| Pattern | Action |
| --- | --- |
| `rm*` | ask |
| `rm -rf /` | deny |
| `dd*` | ask |
| `*shred*`, `*mkfs*`, `*mkswap*`, `*wipefs*`, `*fdisk*`, `*parted*` | ask |
| `*chmod *-R*`, `*chown *-R*` | ask |
| `*sudo *` | ask |
| `*:(){*` (fork bomb) | ask |
| `git push*--force*`, `git push*-f*` | ask |

These guards are broad but not exhaustive. `bash -c 'rm -rf /'` and other
wrappers bypass the match, and unusual flag orders slip through. Treat YOLO mode
as host-level authority; the QEMU guest (`HOPLON_ISOLATION=vm`) is the real
boundary. See [Security](security.md) and [QEMU guest](vm.md).

### Provider

```jsonc
"provider": {
  "venice": {
    "name": "Venice AI",
    "whitelist": [ ... seven model ids ... ],
    "options": {
      "baseURL": "https://api.venice.ai/api/v1",
      "apiKey": "{env:VENICE_API_KEY}",
      "timeout": 600000,
      "headerTimeout": 60000,
      "chunkTimeout": 60000
    },
    "models": { ... }
  }
}
```

Do not set `"npm"` under `provider.venice`. OpenCode ships a native venice
provider that lowers options into Venice's `venice_parameters` (snake_case).
Forcing `@ai-sdk/openai-compatible` bypasses that plugin and emits a camelCase
`veniceParameters` object the API ignores.

The `whitelist` restricts the selectable catalog to the seven declared models.
See [Models](models.md).

### Agents

The `agent` block defines the OpenCode-native roster. Each entry sets `mode`,
`model`, `steps`, `temperature`, `maxTokens`, and `permission`. See
[Models](models.md) for the routing table.

### Skills

```jsonc
"skills": {
  "paths": ["{env:HOPLON_HOME}/skills"],
  "urls": []
}
```

`HOPLON_HOME` is exported by the launcher and resolves to the repository root.

### MCP servers

The `mcp` block defines twelve servers. Only `venice` is enabled by default.
See [MCP servers](mcp-servers.md).

### Tool gating

```jsonc
"tools": {
  "nmap*": false, "pentest*": false, "nuclei*": false,
  "sqlmap*": false, "ffuf*": false, "burp*": false,
  "metasploit*": false, "bloodhound*": false, "ghidra*": false
}
```

Weapon tools are off for every agent unless an agent re-enables them in its own
`tools` map.

### Instructions

```jsonc
"instructions": ["{env:HOPLON_HOME}/AGENTS.md"]
```

This loads the operator persona and rules of engagement.

### Runtime and limits

| Key | Value |
| --- | --- |
| `logLevel` | `INFO` |
| `tool_output.max_lines` | `800` |
| `tool_output.max_bytes` | `512000` |
| `compaction.auto` | `false` |
| `compaction.prune` | `false` |
| `experimental.batch_tool` | `true` |
| `experimental.openTelemetry` | `false` |
| `experimental.continue_loop_on_deny` | `true` |
| `experimental.mcp_timeout` | `30000` |
| `experimental.primary_tools` | `["edit", "bash", "task", "write"]` |
| `attachment.image.auto_resize` | `true` |
| `attachment.image.max_width` / `max_height` | `2000` / `2000` |
| `attachment.image.max_base64_bytes` | `5242880` |
| `server.port` | `8080` |
| `server.hostname` | `127.0.0.1` |
| `server.mdns` | `false` |

Native compaction stays off (`auto` and `prune` false) because Magic Context
owns the context window. See [Magic Context](magic-context.md).

## config/omo.jsonc

This file configures the Oh My OpenAgent layer. OMO reads a user layer at
`$HOME/.omo/omo.jsonc` plus a project `.omo/omo.jsonc` walked upward. The
launcher copies this file to the user layer in the isolated home.

The `[opencode]` section holds `agents`, `categories`, `background_task`,
`disabled_hooks`, and `team_mode`; `telemetry` sits at the top level.

### Disabled hooks

```jsonc
"disabled_hooks": [
  "context-window-monitor",
  "preemptive-compaction",
  "anthropic-context-window-limit-recovery"
]
```

`preemptive-compaction` is disabled because Magic Context owns compaction.

### Team mode

```jsonc
"team_mode": {
  "enabled": true,
  "max_parallel_members": 4,
  "tmux_visualization": true
}
```

### Telemetry

```jsonc
"telemetry": false
```

Anonymous telemetry is off for a portable, opsec-conscious distribution.

## config/tui.json

```jsonc
{
  "theme": "hoplon",
  "plugin": [
    ["./plugins/hoplon-brand.tsx", { "enabled": true }],
    "@cortexkit/opencode-magic-context@0.43.1"
  ],
  "scroll_speed": 3,
  "scroll_acceleration": { "enabled": true },
  "diff_style": "auto",
  "mouse": true,
  "attention": { "enabled": true, "notifications": true, "sound": false }
}
```

Switch to the transparent variant by setting `"theme": "hoplon-ghost"`.

## config/magic-context.jsonc

The Magic Context engine config. The launcher seeds it to
`$HOME/.config/cortexkit/magic-context.jsonc` in the isolated home. It sets the
historian model to `venice/olafangensan-glm-4.7-flash-heretic`, because the
historian only summarizes older history. See [Magic Context](magic-context.md).

## Editing safely

1. Edit the file in `config/`.
2. Restart `./hoplon`. The launcher re-seeds on every launch.
3. Do not edit `./home/.config/opencode/opencode.jsonc` directly; it is
   overwritten.

To validate a JSONC edit before launching. This is the same normaliser the test
suite uses in `tests/test_config_jsonc.sh`: strip `//` and `/* */` comments and
trailing commas, then pipe strict JSON to `jq`.

```bash
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
```
