# Isolation

Hoplon is portable and isolated. The launcher (`./hoplon`) is the security
boundary: it never reads or writes the host's OpenCode or OMO state. This page
describes exactly what it isolates and how.

## The isolated home

On every launch the launcher sets:

```bash
export HOME="$HOPLON_HOME/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"
```

All four XDG variables are set explicitly because xdg-basedir resolves them from
the environment at import time. A host-exported XDG variable would otherwise
override the HOME-derived default and leak state out.

`HOPLON_HOME` is resolved from the script location, so it points at the
repository no matter where it is copied.

## Host selectors are dropped

The launcher unsets host `OPENCODE_*` selectors that would override or redirect
the install:

```text
OPENCODE_CONFIG  OPENCODE_CONFIG_DIR  OPENCODE_CONFIG_CONTENT
OPENCODE_TUI_CONFIG  OPENCODE_PERMISSION  OPENCODE_DB
OPENCODE_MODELS_PATH  OPENCODE_MODELS_URL
```

## Autoupdate and telemetry are off

```bash
export OPENCODE_DISABLE_AUTOUPDATE=1
export OMO_DISABLE_POSTHOG=1
export OMO_SEND_ANONYMOUS_TELEMETRY=0
```

Hoplon is a frozen distribution. It does not self-update, and it sends no OMO
telemetry.

## The seed phase

On every launch the launcher copies config into the isolated home:

| Source | Destination |
| --- | --- |
| `config/opencode.jsonc` | `$XDG_CONFIG_HOME/opencode/opencode.jsonc` |
| `config/tui.json` | `$XDG_CONFIG_HOME/opencode/tui.json` |
| `config/omo.jsonc` | `$HOME/.omo/omo.jsonc` |
| `themes/*.json` | `$XDG_CONFIG_HOME/opencode/themes/` |
| `agents/*.md` | `$XDG_CONFIG_HOME/opencode/agents/` |
| `tui/*.tsx` | `$XDG_CONFIG_HOME/opencode/plugins/` |

It copies rather than symlinks, because OMO rewrites its config with a
temp-file plus rename replace, which would sever a symlink inode. Copies go
through a temp file and rename, so a concurrent launch never reads a
half-written config.

## Git identity and login shell

The launcher seeds a git identity if none exists:

```text
user.name  = Hoplon Operator
user.email = operator@hoplon.local
safe.directory = *
```

`safe.directory=*` avoids dubious-ownership failures when the repo is copied
across machines or users. It also seeds a login-shell profile that restores the
bundled binary on `PATH`, because opencode's bash tool spawns login shells and
`/etc/profile` can rebuild `PATH`.

## Host credentials are absent by design

An isolated home has no host credentials. Two opt-in passthroughs exist:

| Variable | Effect |
| --- | --- |
| `HOPLON_SHARE_SSH=1` | symlink host `~/.ssh` into the isolated home |
| `HOPLON_SHARE_GH=1` | symlink host `~/.config/gh` into the isolated home |
| `HOPLON_HOST_HOME` | override the real account home captured at launch |

Enable these only when a session needs them.

## OMO conflict handling

OMO discovers its config by walking `.omo/omo.jsonc` from the working directory
upward (project layer) plus a user layer at `$HOME/.omo`. Because the isolated
`HOME` is not an ancestor of the working directory, a host `~/.omo/omo.jsonc`
that sits above the working directory is read as a **project** layer and would
override Hoplon's Venice routing.

The launcher detects that case and:

1. Backs the host file up to `<file>.hoplon-hostbak` at mode 600.
2. Writes Hoplon's config over the host file atomically.
3. Restores the host file on `EXIT`, `INT`, `TERM`, and `HUP`.
4. Self-heals on the next run if a prior run died before restoring.

On a clean machine nothing on the host is touched. On a machine that already
uses OMO, the host file is temporarily swapped and restored.

Set `HOPLON_OMO_TAKEOVER=0` to disable the takeover and let the host config win.

## What is not isolated

- The network. The agent can reach the internet, which the Venice API requires.
- The target directory you pass on the command line. The launcher binds it in
  the sandbox and uses it as the working directory.
- Anything you explicitly pass through with `HOPLON_SHARE_SSH` or
  `HOPLON_SHARE_GH`.

For filesystem isolation beyond the home directory, use the sandbox. See
[Sandbox](sandbox.md).
