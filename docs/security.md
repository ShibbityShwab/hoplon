# Security

Hoplon runs with YOLO permissions by default and removes the platform content
filter. That is a deliberate trade for red-team speed. Containment comes from
the QEMU virtual machine, not from the permission rules. This page states the
threat model and the mitigations honestly.

## Threat model

| Threat | Reality |
| --- | --- |
| Destructive command | Bash is allowed; the guards are a text denylist, not a containment boundary |
| API key exposure | The key is readable by the agent through `cat .env` |
| Prompt injection | Web fetch and search are allowed; untrusted content reaches the model |
| Host state leakage | Isolated by default; passthroughs are opt-in |
| Host OMO config clobber | Taken over and restored, with a self-heal path |
| Kernel-level escape | The `host` tier shares the host kernel; `vm` and `nix` guests have their own |
| Supply chain | Plugins and MCP servers are fetched at runtime and version-pinned |

## Permissions

Hoplon runs YOLO. Read prompts for `.env`, but bash is allowed, so the agent can
still reach the key with `cat .env`. Treat the key as exposed to the model.

The bash rules cover `rm`, `dd`, disk tools, recursive chown/chmod, `sudo`,
fork bombs, and forced pushes. They are a text denylist, not a containment
boundary: `bash -c 'rm -rf /'` and other wrappers bypass the match, and unusual
flag orders slip through. Treat YOLO mode as host-level authority. The real
boundary is the guest tier (`HOPLON_ISOLATION=vm|nix`), with the QEMU virtual
machine as the cross-platform default.

## The VM is the containment boundary

`HOPLON_ISOLATION=vm` hands the whole stack to a Debian guest under QEMU with
its own kernel, filesystem, and user. The host filesystem is not visible to the
guest at all, so the agent cannot reach the launcher, `scripts/`, `config/`,
`.env`, or any host credential. The guest gets the network the Venice API needs
and can share one directory you choose read-only with `HOPLON_VM_SHARE`. QEMU
provides the same boundary on Linux (KVM), macOS (HVF), and Windows (WHPX or
TCG), so there is no per-OS sandbox to configure. See [QEMU guest](vm.md).

## Provider integrity

Venice runs through OpenCode's built-in venice provider, not a generic adapter.
Do not add `"npm"` to `provider.venice`: the override bypasses the
`venice_parameters` lowering and sends a camelCase object the API ignores. The
built-in provider is what makes reasoning and Venice options work correctly.

## Prompt injection

With web fetch and search allowed, untrusted content can reach the model. Keep
the API key scoped and prefer a proxy or a disposable host when working against
hostile targets. The `vm` and `nix` tiers limit injected instructions to the
guest.

## Install integrity

`scripts/install.sh` installs by rename, so a killed download never leaves a
truncated binary. The digest of the pinned 1.18.25 linux-x64 archive is built
in and verified by default; a mismatch fails closed. Any other version or
platform needs `HOPLON_OPENCODE_SHA256` set explicitly, and the installer warns
when it is missing. `.env` is read as data, so a digest there cannot execute.

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
host `OPENCODE_*` selectors, drops host credential and agent variables (SSH
agent, cloud keys, Docker endpoints), resets `XDG_RUNTIME_DIR` and `TMPDIR` into
the isolated home, and seeds config by copy. Host credential files are absent by
design; `HOPLON_SHARE_SSH` and `HOPLON_SHARE_GH` are opt-in. That is the `host`
tier. For a kernel boundary, `HOPLON_ISOLATION=vm` and `nix` run the whole stack
in a guest with its own kernel. See [Isolation](isolation.md),
[QEMU guest](vm.md), and [NixOS guest](nixos-vm.md).

## Reporting a vulnerability

See [SECURITY.md](https://github.com/ShibbityShwab/hoplon/blob/main/SECURITY.md). Do not open a public issue for a
vulnerability.

## Operator responsibility

Use Hoplon only against systems you own or have explicit written authorization
to test. Unauthorized access, scanning, or exploitation is illegal in most
jurisdictions and can carry criminal and civil liability. The operator is solely
responsible for staying inside scope and for complying with all applicable laws.
See [Rules of engagement](rules-of-engagement.md).
