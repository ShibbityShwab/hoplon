# Magic Context

Magic Context is Hoplon's context engine. It replaces OpenCode native
compaction with tiered context management and adds cross-session project
memory, so a long session keeps running without compaction pauses and keeps
what it learned after the session ends.

A background historian compresses older raw history into chronological
compartments and lifts durable knowledge (decisions, constraints, conventions,
config values) into project memory that is injected into future sessions.

## Shipped configuration

Hoplon pins the plugin in `config/opencode.jsonc` and lists it for the TUI
sidebar in `config/tui.json`:

```jsonc
"plugin": [
  "oh-my-openagent@5.0.0-beta.62",
  "@cortexkit/opencode-magic-context@0.43.1"
],
"compaction": { "auto": false, "prune": false }
```

Native compaction stays off because Magic Context owns the window. Leaving it
on makes the plugin detect a conflict and disable itself.

The engine config is `config/magic-context.jsonc`. It sets `$schema` and runs
the historian on the cheap uncensored Venice model
`venice/olafangensan-glm-4.7-flash-heretic`; the historian only summarizes, so
it does not need the primary model.

## Storage

The engine needs no API key. Its SQLite store and embedding cache live under
the isolated home at `home/.local/share/cortexkit/magic-context`. Set
`MAGIC_CONTEXT_STORAGE_DIR` to an absolute directory to persist the store
elsewhere. See `.env.example`.

## Driving it by hand

Context management runs in the background. Force it when you want the work
done now:

| Command | Effect |
| --- | --- |
| `/ctx-wrapup` | Compact older live history now, keeping the newest messages raw. |
| `/ctx-flush` | Run all queued operations immediately, bypassing the cache TTL. |

Queued work normally waits for the execute threshold, which defaults to 65% of
the usable context window. The runtime caps a configured threshold at 90% and
keeps a fixed 95% emergency wall.
