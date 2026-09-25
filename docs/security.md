# Security

Hoplon runs with YOLO permissions by default and removes the platform content
filter. That is a deliberate trade for red-team speed, and it moves the security
boundary to the operator and the sandbox. This page states the threat model and
the mitigations honestly.

## Threat model

| Threat | Reality |
| --- | --- |
| Destructive command | Bash is allowed; guards cover common cases but not all |
| API key exposure | The key is readable by the agent through `cat .env` |
| Prompt injection | Web fetch and search are allowed; untrusted content reaches the model |
| Host state leakage | Isolated by default; passthroughs are opt-in |
| Host OMO config clobber | Taken over and restored, with a self-heal path |
| Supply chain | Plugins and MCP servers are fetched at runtime and version-pinned |

## Permissions

Hoplon runs YOLO. Read prompts for `.env`, but bash is allowed, so the agent can
still reach the key with `cat .env`. Treat the key as exposed to the model.

The bash guards cover `rm`, `dd`, disk tools, recursive chown/chmod, `sudo`,
fork bombs, and forced pushes. They are broad but not exhaustive: wrappers
(`sudo rm`, `bash -c '...'`) and unusual flag orders can slip through. Treat YOLO
mode as host-level authority and run engagements on a disposable box.

## The sandbox is the real mitigation

`HOPLON_SANDBOX=1` hides the host filesystem behind bubblewrap while keeping the
network for the API. This is the mitigation for the YOLO and prompt-injection
risks. Raw-socket tools must run outside it. See [Sandbox](sandbox.md).

## Provider integrity

Venice runs through OpenCode's built-in venice provider, not a generic adapter.
Do not add `"npm"` to `provider.venice`: the override bypasses the
`venice_parameters` lowering and sends a camelCase object the API ignores. The
built-in provider is what makes reasoning and Venice options work correctly.

## Prompt injection

With web fetch and search allowed, untrusted content can reach the model. Keep
the API key scoped and prefer a proxy or container when working against hostile
targets. The sandbox limits what injected instructions can reach on disk.

## Install integrity

`scripts/install.sh` installs by rename, so a killed download never leaves a
truncated binary. Set `HOPLON_OPENCODE_SHA256` in `.env` to verify the archive
digest; the installer fails closed on a mismatch.

## Launcher integrity

The OMO takeover backs up the host file at mode 600, writes atomically, and
restores on `EXIT`, `INT`, `TERM`, and `HUP`. A `SIGKILL` can still leave the
host file swapped; the next run from the same tree self-heals from the backup.

## Supply chain

Plugins and MCP servers are fetched at runtime. Every `npx` and `uvx` server is
version-pinned. The four Docker images are locally built and tagged `:latest`;
pin them by digest. The `metasploit` and `bloodhound` servers run local checkouts
under `/opt`; pin those by git commit. See [MCP servers](mcp-servers.md).

## Isolation

The launcher isolates `HOME` and all four XDG variables into `./home`, unsets
host `OPENCODE_*` selectors, and seeds config by copy. Host credentials are
absent by design; `HOPLON_SHARE_SSH` and `HOPLON_SHARE_GH` are opt-in. See
[Isolation](isolation.md).

## Reporting a vulnerability

See [SECURITY.md](../SECURITY.md). Do not open a public issue for a
vulnerability.

## Operator responsibility

Use Hoplon only against systems you own or have explicit written authorization
to test. Unauthorized access, scanning, or exploitation is illegal in most
jurisdictions and can carry criminal and civil liability. The operator is solely
responsible for staying inside scope and for complying with all applicable laws.
See [Rules of engagement](rules-of-engagement.md).
