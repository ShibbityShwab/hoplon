# Hoplon

![Hoplon banner](assets/banner.png)

An uncensored, red-team-focused OpenCode distribution that runs on Venice AI and
carries the Oh My OpenAgent harness. Clone the repo, install the binary, set one
API key, and you have a portable security console that keeps all of its state
inside its own tree.

## Quickstart

```bash
git clone https://github.com/ShibbityShwab/hoplon.git hoplon
cd hoplon
scripts/install.sh
cp .env.example .env     # then set VENICE_API_KEY
./hoplon doctor
./hoplon
```

## What you get

- **Venice AI only.** Every route points at Venice's uncensored model family, with no platform-level content filter.
- **Isolated by default.** The launcher keeps `HOME` and every XDG directory inside `./home`. The one exception is a conflicting host `~/.omo/omo.jsonc`, which is taken over for the session and restored on exit.
- **Optional sandbox.** `HOPLON_SANDBOX=1` wraps the runtime in bubblewrap with the network up for Venice, the repo read-only, and host credentials and container sockets hidden.
- **Three isolation tiers.** `HOPLON_ISOLATION=host` (the default) keeps the isolated home on this machine; `vm` boots a Debian QEMU/KVM guest; `nix` boots a declarative NixOS guest. Both guests have their own kernel.
- **Red-team roster.** Six specialist agents and five offense skills, gated by a mandatory rules-of-engagement skill.
- **Venice-native tools.** A 31-tool MCP server plus 20 official Venice API skills for embeddings, image, video, audio, music, and characters.
- **No telemetry.** Autoupdate and PostHog telemetry are disabled, so a portable copy stays frozen and quiet.

## Explore the docs

- [Installation](installation.md) for the full setup walkthrough.
- [Getting started](getting-started.md) for the first-session tour.
- [Configuration](configuration.md) for agents, permissions, and MCP servers.
- [Models](models.md) for the allowlisted roster and limits.
- [MCP servers](mcp-servers.md) to enable recon and weapon servers.
- [Sandbox](sandbox.md) and [Isolation](isolation.md) for the security model.
- [QEMU guest](vm.md) and [NixOS guest](nixos-vm.md) for the full-kernel tiers.
- [Rules of engagement](rules-of-engagement.md) before any active testing.
- [OMO](omo.md) for the harness that routes agents and categories.
- [Magic Context](magic-context.md) for long-session context management.
- [Architecture](architecture.md) for how the pieces fit together.
- [Security](security.md) for the threat model and hardening notes.
- [Troubleshooting](troubleshooting.md) when something does not start.
- [FAQ](faq.md) for common questions.

## License

Hoplon is released under the
[GNU Affero General Public License v3.0 or later](https://github.com/ShibbityShwab/hoplon/blob/main/LICENSE)
(AGPL-3.0-or-later).
