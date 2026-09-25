# Installation

This page covers getting Hoplon from a clone to a running TUI. It matches
`scripts/install.sh` and the `hoplon` launcher exactly.

## Requirements

- `bash`
- `curl`
- `tar` on Linux, `unzip` on macOS
- Linux or macOS on `x64` or `arm64`

The installer maps `uname -m` values `x86_64`/`amd64` to `x64` and
`aarch64`/`arm64` to `arm64`. Any other OS exits with an error.

Optional, for the MCP servers that need them:

- `node` and `npx` for the `venice`, `shodan`, `nmap`, and `pentest` servers
- `uvx` for the `cve` server
- `docker` for the `nuclei`, `sqlmap`, `ffuf`, and `ghidra` servers
- `bwrap` for the sandbox (`HOPLON_SANDBOX=1`)

## Clone and install

```bash
git clone https://github.com/ShibbityShwab/hoplon.git hoplon
cd hoplon
scripts/install.sh
```

`scripts/install.sh` does the following:

1. Reads `.env` if present, so a pinned `HOPLON_OPENCODE_SHA256` takes effect.
2. Resolves the platform asset: `opencode-linux-<arch>.tar.gz` or
   `opencode-darwin-<arch>.zip`.
3. Downloads it from
   `https://github.com/<repo>/releases/download/v<version>/<asset>`.
4. Verifies the archive with `sha256sum` when `HOPLON_OPENCODE_SHA256` is set,
   falling back to `shasum -a 256` on macOS where `sha256sum` is absent, and
   fails closed on a mismatch.
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
| `HOPLON_OPENCODE_SHA256` | unset | archive digest; verified and fails closed |

Set them in the environment or in `.env`. The installer sources `.env`, so a
pinned digest there works.

## Configure the API key

```bash
cp .env.example .env
```

Edit `.env` and set:

```dotenv
VENICE_API_KEY=your-key-here
```

Get a key at <https://venice.ai>. The launcher sources `.env` on every run.

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

This reports the opencode version, whether `VENICE_API_KEY` is set, whether
`bwrap` is available, which MCP runtimes exist, which weapon binaries are
installed, and whether Venice is reachable. It does not seed or launch.

## Updating

Hoplon is frozen by design: the launcher sets `OPENCODE_DISABLE_AUTOUPDATE=1`.
To update, re-run `scripts/install.sh` with a new `HOPLON_OPENCODE_VERSION`, or
`git pull` and re-run the installer.

## Uninstalling

Delete the directory. Hoplon writes only inside its own tree (`./home` and
`./bin`), so there is nothing to clean up elsewhere. The one exception is the
OMO takeover, which temporarily swaps a host `~/.omo/omo.jsonc` and restores it
on exit; see [Isolation](isolation.md).
