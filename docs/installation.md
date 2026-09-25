# Installation

This page covers getting Hoplon from a clone to a running TUI. It matches
`scripts/install.sh` and the `hoplon` launcher exactly.

## Requirements

- `bash`
- `curl`
- `tar` on Linux, `unzip` on macOS
- Linux or macOS on `x64` or `arm64`

The installer maps `uname -m` values `x86_64`/`amd64` to `x64` and
`aarch64`/`arm64` to `arm64`. Any other OS exits with an error, so the host tier
is Linux and macOS. On Windows, use WSL2 (which reports Linux and runs the full
installer) or run the launcher from Git Bash/MSYS2 with the `vm` tier, where the
guest installs Hoplon itself and no host opencode binary is needed.

Optional, for the MCP servers that need them:

- `node` and `npx` for the `venice`, `shodan`, `nmap`, and `pentest` servers
- `uvx` for the `cve` server
- `docker` for the `nuclei`, `sqlmap`, `ffuf`, and `ghidra` servers
- `qemu-system-x86_64` (or `qemu-system-aarch64` on arm64 hosts), `qemu-img`,
  `xorriso`, and `ssh-keygen` for the `vm` tier

## Clone and install

```bash
git clone https://github.com/ShibbityShwab/hoplon.git hoplon
cd hoplon
scripts/install.sh
```

`./hoplon setup` is the one-command path: it runs `scripts/install.sh` when the
runtime is missing, creates `.env` (mode 600), prompts once for
`VENICE_API_KEY` with hidden input, optionally pre-builds the guest, and ends
with the environment report. It is safe to re-run, and it is the recommended
first command.

`scripts/install.sh` does the following:

1. Reads `.env` as data, never as shell, so a pinned `HOPLON_OPENCODE_SHA256`
   takes effect without executing the file.
2. Resolves the platform asset: `opencode-linux-<arch>.tar.gz` or
   `opencode-darwin-<arch>.zip`.
3. Downloads it from
   `https://github.com/<repo>/releases/download/v<version>/<asset>`.
4. Verifies the archive digest. The pinned 1.18.25 linux-x64 archive has a
   built-in SHA-256 and is verified by default with `sha256sum`, falling back to
   `shasum -a 256` on macOS where `sha256sum` is absent; a mismatch fails closed.
   Any other version or platform needs `HOPLON_OPENCODE_SHA256` set explicitly,
   and the installer warns when it is missing.
5. Extracts the archive and installs the `opencode` binary into `bin/` by
   rename, so an interrupted download never leaves a truncated binary.
6. Prints the installed version.
7. Pre-seeds the OMO and Magic Context plugin caches from the host if present.
8. Vendors host LSP binaries, the models.dev cache, and OMO's ast-grep runtime
   when present, so first use does not need network.

The binary is roughly 180 MB and is gitignored, which is why it is fetched
rather than committed.

## Installer environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOPLON_OPENCODE_VERSION` | `1.18.25` | opencode release to fetch |
| `HOPLON_OPENCODE_REPO` | `anomalyco/opencode` | GitHub repo to fetch from |
| `HOPLON_OPENCODE_SHA256` | built-in for 1.18.25 linux-x64 | archive digest; verified and fails closed. Any other version or platform must set it or the installer warns |

Set them in the environment or in `.env`. The installer reads `.env` as data, so
a pinned digest there works.

## Configure the API key

`./hoplon setup` does this for you: it creates `.env` from `.env.example` with
mode 600 and, on a terminal, prompts once for the key with hidden input. To do
it by hand instead:

```bash
cp .env.example .env
```

Edit `.env` and set:

```dotenv
VENICE_API_KEY=your-key-here
```

Get a key at <https://venice.ai>. The launcher reads `.env` as data on every
run, so values are never executed as shell.

Optional keys, only needed when you enable the matching MCP server:

| Variable | Used by |
| --- | --- |
| `SHODAN_API_KEY` | `shodan` MCP server |
| `NVD_API_KEY` | `cve` MCP server |
| `VIRUSTOTAL_KEY` | `cve` MCP server |
| `GREYNOISE_API_KEY` | `cve` MCP server |
| `NEO4J_PASSWORD` | `bloodhound` MCP server |
| `MSF_PASSWORD` | `metasploit` MCP server |

## First run

```bash
./hoplon
```

The launcher seeds config into `./home`, then starts the TUI in the current
directory. See [Getting started](getting-started.md) for the first-session
walkthrough.

## Verify the install

```bash
./hoplon doctor
```

This reports the opencode version, whether `VENICE_API_KEY` is set, which MCP
runtimes exist, which weapon binaries are installed, and whether Venice is
reachable. It does not seed or launch.

## Isolation tiers

`HOPLON_ISOLATION` chooses where the stack runs. `host` is the default and
everything above. `vm` hands the whole distribution to a guest with its own
kernel, filesystem, and user. The one-word shortcut `hoplon vm` runs the guest
path and lands in the console inside it:

| Value | What it runs | Requirements | Page |
| --- | --- | --- | --- |
| `host` (default) | isolated HOME on this machine, sharing the host kernel | none | [Isolation](isolation.md) |
| `vm` | Debian QEMU guest provisioned by cloud-init | QEMU, `xorriso`, a working accelerator | [QEMU guest](vm.md) |

QEMU selects its accelerator per host: KVM on Linux, HVF on macOS, WHPX or TCG
on Windows. Override it with `HOPLON_VM_ACCEL` (see [QEMU guest](vm.md)).

The `vm` tier provisions itself: the default `base` guest installs Hoplon and
`hoplon-tool` and then fetches tools on demand, so the host needs only the tools
above to build and boot it. Set `HOPLON_VM_TOOLS=core` or `full` to preload the
arsenal on first boot instead.

## Updating

Hoplon is frozen by design: the launcher sets `OPENCODE_DISABLE_AUTOUPDATE=1`.
To update, re-run `scripts/install.sh` with a new `HOPLON_OPENCODE_VERSION`, or
`git pull` and re-run the installer.

## Uninstalling

Delete the directory. Runtime state lives in `./home`, VM state in `./vm`, and
the opencode binary in `./bin`, all inside the tree. Two things live outside it:

- The `hoplon` symlink the installer created in `HOPLON_BIN_DIR` (default
  `$HOME/.local/bin`). Delete it.
- A host `~/.omo/omo.jsonc` that the launcher temporarily swaps and restores on
  exit; see [Isolation](isolation.md).
