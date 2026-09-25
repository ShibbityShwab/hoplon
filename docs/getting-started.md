# Getting started

This is the first-session walkthrough. It assumes you finished
[Installation](installation.md) and have `VENICE_API_KEY` set in `.env`.

## 1. Check the box

```bash
./hoplon doctor
```

Read the output before you start. It tells you what will and will not work:

```text
hoplon doctor
  repo                /path/to/hoplon
  opencode            1.18.25
  VENICE_API_KEY      set
  bwrap (sandbox)     yes
  node / npx          yes / yes
  uvx (python MCP)    yes
  docker (docker MCP) yes
  weapons             nmap:yes nuclei:NO sqlmap:NO ffuf:NO msfconsole:NO ghidra:NO
  venice reachable    yes
```

`MISSING` on `VENICE_API_KEY` means the launcher will warn and the model calls
will fail. `NO` on a weapon binary means the matching MCP server cannot run even
if you enable it.

## 2. Start the TUI

```bash
./hoplon
```

The launcher:

1. Reads `.env` as data, never as shell.
2. Sets `HOME` to `./home` and all four XDG variables inside it.
3. Unsets host `OPENCODE_*` selectors and host credential and agent variables.
4. Seeds `config/`, `themes/`, `agents/`, and `tui/` into the isolated home.
5. Starts the bundled opencode binary.

You should see the HOPLON wordmark and `offensive security console` on the home
screen, on the iron background of the `hoplon` theme.

## 3. Pick an agent

The default agent is `sisyphus`, routed to `venice/qwen-3-6-plus`. For a coding
task, `build` is the general primary. For red-team work, route to the specialist
that owns the toolset: `recon`, `web-attacker`, `ad-attacker`, `exploit-dev`,
`reverser`, or `report-writer`.

## 4. Run a one-shot prompt

```bash
./hoplon run "summarize the files in this directory"
```

This is useful for scripting and for a quick check that the provider is wired up.

## 5. Run against a project

```bash
./hoplon /path/to/project
```

The TUI starts with that directory as the working directory. The launcher binds
the target directory into the sandbox when `HOPLON_SANDBOX=1`.

## 6. Start an engagement

Before any active testing, load the rules-of-engagement skill. The `redteam-roe`
skill gates every other offense skill. Confirm written authorization and exact
scope first. See [Rules of engagement](rules-of-engagement.md).

## 7. Handle untrusted content in the sandbox

When you are about to run risky code or process untrusted content, restart under
the sandbox:

```bash
HOPLON_SANDBOX=1 ./hoplon
```

The host filesystem is hidden. The repo is read-only, so the agent cannot edit
the launcher, `scripts/`, `config/`, or `.env`; only the isolated home and the
target directory are writable. Host credentials and container sockets are not
visible. Network stays up for the Venice API. Raw-socket tooling does not work
inside; run that unsandboxed. See [Sandbox](sandbox.md).

## 8. Step up to a guest tier

The host tier isolates state but shares the host kernel. When the engagement
needs a full boundary, run the whole stack inside a guest:

```bash
HOPLON_ISOLATION=vm ./hoplon    # Debian QEMU/KVM guest
HOPLON_ISOLATION=nix ./hoplon   # declarative NixOS guest
```

Each guest has its own kernel, filesystem, and user, so nothing it does reaches
the host OS. See [Isolation](isolation.md), [QEMU guest](vm.md), and
[NixOS guest](nixos-vm.md).

## Next steps

- [Configuration](configuration.md) to tune agents, permissions, and MCP servers.
- [Models](models.md) for the model roster and limits.
- [MCP servers](mcp-servers.md) to enable recon and weapon servers.
- [Isolation](isolation.md) for the three tiers and what each one isolates.
- [Troubleshooting](troubleshooting.md) when something does not start.
