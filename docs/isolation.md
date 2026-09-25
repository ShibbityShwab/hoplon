# Isolation

Hoplon is portable and isolated. The launcher (`./hoplon`) is the state
boundary: it never reads or writes the host's OpenCode or OMO state, with the
temporary OMO takeover as the one exception. It isolates state, not the kernel.
The containment boundary is the QEMU virtual machine (`HOPLON_ISOLATION=vm`),
which runs on every supported host. This page describes what the launcher
isolates and how.

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

## `.env` is read as data

The launcher reads `.env` as data, never as shell. Only `NAME=value` lines at
column 0 are honored; surrounding single or double quotes are stripped and the
value is exported verbatim. Command substitution, backticks, and arithmetic in
the file never run, so a tampered `.env` cannot execute code on the next launch.
`scripts/install.sh` uses the same reader.

## Host credential and agent variables are dropped

The isolated HOME hides credential files, but an inherited environment variable
would carry the same access into the child. Before opencode starts, the launcher
unsets:

```text
SSH_AUTH_SOCK  SSH_AGENT_PID  SSH_ASKPASS  GIT_ASKPASS  GPG_AGENT_INFO
KRB5CCNAME  KRB5_CONFIG  GITHUB_TOKEN  GH_TOKEN
AWS_ACCESS_KEY_ID  AWS_SECRET_ACCESS_KEY  AWS_SESSION_TOKEN
DOCKER_HOST  DOCKER_TLS_VERIFY  DOCKER_CERT_PATH  DOCKER_CONTEXT
```

It also unsets every exported `AZURE_*`, `GOOGLE_*`, or `GCP_*` name, then
resets `XDG_RUNTIME_DIR` to `$HOME/.run` and `TMPDIR` to `$HOME/tmp` inside the
isolated home. This runs on every launch.

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
| `config/magic-context.jsonc` | `$HOME/.config/cortexkit/magic-context.jsonc` |
| `themes/*.json` | `$XDG_CONFIG_HOME/opencode/themes/` |
| `agents/*.md` | `$XDG_CONFIG_HOME/opencode/agents/` |
| `tui/*.tsx` | `$XDG_CONFIG_HOME/opencode/plugins/` |

When `HOPLON_ENABLE_OMO=0`, the launcher skips the `config/omo.jsonc` seed and
strips the OMO plugin line from the seeded OpenCode config.

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

An isolated home has no host credentials, and the host credential variables
above are dropped from the environment. Two opt-in passthroughs exist:

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

## Isolation tiers

`HOPLON_ISOLATION` chooses the boundary:

| Value | Boundary | Kernel | Page |
| --- | --- | --- | --- |
| `host` (default) | isolated HOME, XDG, and credentials; shares the host kernel | host | this page |
| `vm` | full Debian guest under QEMU, on Linux, macOS, and Windows | own | [QEMU guest](vm.md) |
| `nix` | declarative NixOS guest under QEMU | own | [NixOS guest](nixos-vm.md) |

`host` isolates state but shares the host kernel, so a kernel-level defect or a
determined process can still reach the host. `vm` and `nix` give the guest its
own kernel, filesystem, and user, so nothing it does reaches the host OS. The VM
is the cross-platform choice: QEMU runs on Linux (KVM), macOS (HVF), and Windows
(WHPX or TCG). Both guests are self-contained and provision their own toolchain.

## What is not isolated

- The network. The agent can reach the internet, which the Venice API requires.
- The target directory you pass on the command line. The launcher uses it as the
  working directory.
- The repository itself on the host tier. The agent can edit the launcher,
  `scripts/`, `config/`, and `.env`. Inside the `vm` or `nix` guest it can only
  edit the copy that lives in the guest.
- Anything you explicitly pass through with `HOPLON_SHARE_SSH` or
  `HOPLON_SHARE_GH`.

For a real boundary, use the QEMU guest: `HOPLON_ISOLATION=vm` runs the whole
stack inside a virtual machine with its own kernel, on any supported host. The
`nix` tier does the same with a pinned, declarative NixOS guest. See
[QEMU guest](vm.md) and [NixOS guest](nixos-vm.md).
