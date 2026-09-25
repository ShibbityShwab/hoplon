# Troubleshooting

Common failures and what to do about them. Start with `./hoplon doctor`.

## `bin/opencode not found`

The launcher checks for `bin/opencode` before it starts. Run the installer:

```bash
scripts/install.sh
```

If the download failed, check the URL the installer printed. The default is
`https://github.com/anomalyco/opencode/releases/download/v1.18.25/<asset>`.
Override with `HOPLON_OPENCODE_VERSION` and `HOPLON_OPENCODE_REPO`.

## `VENICE_API_KEY is not set`

The launcher warns when the key is missing. Copy the template and set it:

```bash
cp .env.example .env
# edit .env, set VENICE_API_KEY
```

The launcher sources `.env` on every run, so no shell export is needed.

## `config/opencode.jsonc is missing`

The launcher checks for the config before it starts. This means the repo tree is
incomplete. Re-clone or restore `config/opencode.jsonc`.

## Model calls fail with "Provider not found"

You are using a suffixed model id. Venice's feature suffixes
(`:enable_web_search=on`, `:include_venice_system_prompt=false`) do not resolve
through the built-in venice provider. Use the plain model id.

## Model calls fail or return filtered output

Check that the model is one of the seven allowlisted uncensored models. The
`whitelist` rejects any other Venice model id. See [Models](models.md).

## `HOPLON_SANDBOX=1` but bwrap is missing

The launcher prints a warning and runs unsandboxed. Install `bubblewrap`:

```bash
# Debian/Ubuntu
sudo apt install bubblewrap
# Fedora
sudo dnf install bubblewrap
```

Check `./hoplon doctor` for `bwrap (sandbox)`.

## Raw-socket tools fail in the sandbox

`nmap -sS`, ARP sweeps, and packet capture need `CAP_NET_RAW` and do not work
inside `bwrap`. Run those unsandboxed:

```bash
HOPLON_SANDBOX=0 ./hoplon
```

## Host user tools are missing in the sandbox

Tools in `~/.local/bin`, `~/.cargo/bin`, `~/go/bin`, or `~/.bun/bin` are not
mounted by default. Set `HOPLON_SANDBOX_BINS=1`.

## An MCP server does not start

Check the requirement for that server in [MCP servers](mcp-servers.md). The
common causes:

- The underlying binary is not on `PATH` (`npx`, `uvx`, `docker`).
- The API key is not set in `.env`.
- The server is still `"enabled": false` in `config/opencode.jsonc`.

Run `./hoplon doctor` to see which runtimes and weapon binaries exist.

## The Venice MCP server logs an argument error

The server's two prompts (`uncensored-research`, `image-style-explorer`) log a
harmless argument error at startup. The tools themselves work. This is a known
upstream quirk, not a Hoplon bug.

## My host OMO config was changed

The launcher takes over a host `~/.omo/omo.jsonc` that sits above the working
directory, then restores it on exit. If a run was killed with `SIGKILL`, the
next run from the same tree self-heals from the backup at
`<file>.hoplon-hostbak`. To disable the takeover entirely:

```bash
HOPLON_OMO_TAKEOVER=0 ./hoplon
```

Set `HOPLON_OMO_TAKEOVER=0` in `.env` to make it permanent.

## Config edits do not take effect

Edit the file in `config/`, not in `./home`. The launcher re-seeds on every
launch and overwrites the seeded copies.

## The TUI theme looks wrong

Check `config/tui.json`. The default theme is `hoplon`; the transparent variant
is `hoplon-ghost`. The TUI plugin `tui/hoplon-brand.tsx` replaces the stock logo
with the HOPLON banner.

## Everything is slow on first launch

The first launch downloads the OMO plugin, LSP servers, and any `npx`/`uvx` MCP
servers. `scripts/install.sh` pre-seeds these from the host when present. After
the first run they are cached in `./home`.

## Still stuck

Run `./hoplon doctor` and include its full output when you ask for help. It
reports the version, key status, sandbox availability, MCP runtimes, weapon
binaries, and Venice reachability.
