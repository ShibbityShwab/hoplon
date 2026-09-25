# FAQ

## Is Hoplon open source?

Hoplon itself is licensed under AGPL-3.0-or-later. One component it loads, the
Oh My OpenAgent plugin, is source-available under the Sustainable Use License
(SUL-1.0), not OSI open source. It is loaded at runtime and not redistributed
here. See [OMO](omo.md).

## Does Hoplon send telemetry?

No. The launcher sets `OPENCODE_DISABLE_AUTOUPDATE=1`, `OMO_DISABLE_POSTHOG=1`,
and `OMO_SEND_ANONYMOUS_TELEMETRY=0`, and `config/omo.jsonc` sets
`"telemetry": false`. Venice is the only inference endpoint the models talk
to, and Hoplon sends no telemetry.

## Which models does it use?

Seven, all Venice uncensored models. See [Models](models.md) for the full table
with context and output limits.

## Can I use a different provider?

Not without editing `config/opencode.jsonc`. Hoplon is Venice-only by design:
`enabled_providers` is `["venice"]` and the model whitelist is Venice-only. If
you want provider freedom, use vanilla OpenCode.

## Can I add a model that is not in the whitelist?

The `whitelist` restricts the selectable catalog to the seven declared models.
Adding a model means editing both the `whitelist` and the `models` block, and
the model must be one Venice tags uncensored if you want the no-filter property.

## Why is the API key still readable by the agent?

Read prompts for `.env`, but bash is allowed, so the agent can reach the key with
`cat .env`. Inside the QEMU guest (`HOPLON_ISOLATION=vm`) the key lives only in
the guest, but the model can still read it there. Treat the key as exposed to the
model. Scope the key and run engagements on a disposable box. See
[Security](security.md).

## Why are the weapon MCP servers disabled?

They are present but off so they do not bloat context or run without intent. An
agent re-enables only what it owns. See [MCP servers](mcp-servers.md).

## Why are shodan and cve disabled?

They fail without API keys, so they are off to keep a keyless boot clean. Set
`SHODAN_API_KEY` (and optionally the NVD, VirusTotal, and GreyNoise keys) in
`.env`, then set `"enabled": true` on the server.

## Does it work offline?

Partly. The opencode binary is fetched by the installer. The OMO plugin, LSP
servers, and `npx`/`uvx` MCP servers are fetched on first use. `scripts/install.sh`
pre-seeds these from the host when present. For a fully offline copy, vendor all
of them.

## Does Hoplon touch my existing OpenCode or OMO install?

No. It isolates `HOME` and all four XDG variables into `./home`, unsets host
`OPENCODE_*` selectors, and drops host credential and agent variables. The one
exception is the OMO takeover: if a host `~/.omo/omo.jsonc` sits above the
working directory, the launcher swaps it for the session and restores it on
exit. See [Isolation](isolation.md).

## Can I run it without OMO?

Yes. Set `HOPLON_ENABLE_OMO=0`. You lose OMO routing, background tasks, and team
mode. See [OMO](omo.md).

## Is there a filesystem sandbox?

No. There is one isolation model: the QEMU virtual machine. The launcher isolates
state (`HOME`, XDG, credentials) but shares the host kernel, and the permission
rules are a text denylist, not a containment boundary. For a real boundary, run
the whole stack in the guest with `HOPLON_ISOLATION=vm`. See
[Isolation](isolation.md) and [QEMU guest](vm.md).

## Can the agent modify Hoplon or the repo?

On the host tier, yes: the agent can edit the launcher, `scripts/`, `config/`,
`bin/`, and `.env`. In the `vm` guest it can only edit the copy inside the
guest, and the host tree is not reachable. See [QEMU guest](vm.md).

## Can I run it in a VM?

Yes. `HOPLON_ISOLATION=vm` boots a Debian QEMU/KVM guest with its own kernel,
filesystem, and user. See [Isolation](isolation.md) and [QEMU guest](vm.md).

## Does `nmap -sS` work?

Yes. On the host tier the launcher runs with your account's privileges; give it
the capability it needs (`sudo` or a root shell). Inside the `vm` guest,
raw-socket work runs in the guest with the guest's privileges. See
[QEMU guest](vm.md).

## How do I update?

Re-run `scripts/install.sh` with a new `HOPLON_OPENCODE_VERSION`, or `git pull`
and re-run the installer. Autoupdate is disabled by design.

## How do I verify the claims in the README?

Every claim is checkable from the repo. The lint and validation commands are in
[CONTRIBUTING.md](https://github.com/ShibbityShwab/hoplon/blob/main/CONTRIBUTING.md),
and the shell tests in `tests/` cover config parsing, the whitelist count,
launcher behavior, and the no-dash rule.

## Where do I report a security issue?

See [SECURITY.md](https://github.com/ShibbityShwab/hoplon/blob/main/SECURITY.md). Do not open a public issue for a
vulnerability.

## Is this legal to use?

Only against systems you own or have explicit written authorization to test.
Unauthorized access, scanning, or exploitation is illegal in most jurisdictions.
The operator is solely responsible for staying inside scope. See
[Rules of engagement](rules-of-engagement.md).
