# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Isolation tiers.** `HOPLON_ISOLATION=host|vm|nix` selects where the stack
  runs: the isolated home on this machine, a Debian QEMU/KVM guest, or a
  declarative NixOS guest. The launcher hands off to the matching backend.
- **Debian QEMU/KVM guest.** `scripts/vm.sh` creates, boots, and destroys a
  Debian cloud-image guest provisioned by cloud-init. `HOPLON_VM_TOOLS` and the
  VM knobs are documented in `docs/vm.md`.
- **NixOS guest.** `flake.nix` emits a bootable VM (`nix run .#vm`) and a qcow2
  image (`nix build .#qcow2`) from pinned Nix inputs; `scripts/nix-vm.sh` wraps
  both.
- **Shared toolchain installer.** `scripts/toolchain.sh` provisions the
  red-team toolbox on Debian and Ubuntu, used by the QEMU guest. The NixOS guest
  pins the same toolset in `nix/toolchain.nix`.

## [1.0.0] - 2026-09-25

First release. Hoplon is a portable, uncensored, red-team-focused OpenCode
distribution that runs on Venice AI and carries the Oh My OpenAgent (OMO)
harness.

### Added

- **Portable, isolated launcher.** `./hoplon` sets `HOME` to `./home` and
  points all four XDG variables inside it, unsets host `OPENCODE_*` selectors,
  disables autoupdate and OMO telemetry, and hands off to the bundled opencode
  binary. Hoplon never reads or writes the host's OpenCode or OMO state, except
  the OMO config takeover, which is restored on exit.
- **Venice-only uncensored whitelist.** Every model route points at Venice AI's
  uncensored family through the built-in venice provider. The provider whitelist
  restricts the catalog to the seven uncensored models, and any other id is
  rejected like a nonexistent model.
- **OMO harness, optional.** The Oh My OpenAgent plugin supplies agent and
  category routing, background tasks, and team mode. It is loaded as a plugin,
  not required by the launcher, so the distribution still runs without it.
- **Bubblewrap sandbox.** `HOPLON_SANDBOX=1` wraps opencode in `bubblewrap`,
  hiding the host filesystem except this repository and the target directory,
  keeping the network for the Venice API, and running in its own user, pid, ipc,
  and uts namespaces. `HOPLON_SANDBOX_BINS=1` mounts host user binaries.
- **`hoplon doctor`.** Reports the opencode version, whether `VENICE_API_KEY` is
  set, whether `bwrap` is available, which MCP runtimes exist, which weapon
  binaries are installed, and whether Venice is reachable.
- **Magic Context.** Long-session context management is handled by
  `@cortexkit/opencode-magic-context@0.43.1`, with OMO's own preemptive
  compaction hook disabled so two systems do not compact at once.
- **Red-team roster.** Six specialist subagents (recon, web-attacker,
  ad-attacker, exploit-dev, reverser, report-writer) and five offense skills,
  gated by a mandatory rules-of-engagement skill.
- **Venice-native tooling.** Venice's MCP server (31 tools) and the 20 official
  Venice API skills, vendored verbatim.
- **Hoplon identity.** A solid bronze-on-iron `hoplon` theme, a transparent
  `hoplon-ghost` variant, and a TUI plugin that replaces the stock OpenCode logo
  with the HOPLON home banner.
- **Installer.** `scripts/install.sh` fetches a pinned opencode binary, verifies
  an optional SHA-256 digest, and pre-seeds the OMO plugin cache and host caches
  for offline use.

### Fixed

- **Launcher data loss.** The OMO config takeover now backs up the host file at
  mode 600, writes atomically, and restores it on `EXIT`, `INT`, `TERM`, and
  `HUP`. A `SIGKILL` can still leave the host file swapped; the next run from
  the same tree self-heals from the backup.
- **macOS portability.** The installer selects the `darwin` asset and extracts
  with `unzip`, and the launcher avoids Linux-only assumptions, so the
  distribution runs on macOS on `x64` and `arm64`.

### Security

- Install-by-rename in `scripts/install.sh`, so an interrupted download or
  extract never leaves a truncated binary where the launcher would treat it as
  valid.
- Optional archive digest verification via `HOPLON_OPENCODE_SHA256`, which
  fails closed on a mismatch.
- Explicit XDG isolation, because xdg-basedir resolves those variables from the
  environment at import time and a host-exported variable would otherwise leak
  state out.

### Attribution

Hoplon bundles or depends on third-party components, each under its own
license. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provenance.

- **OpenCode** (<https://github.com/anomalyco/opencode>): the bundled binary,
  fetched by the installer and not committed.
- **Oh My OpenAgent** (<https://github.com/code-yeongyu/oh-my-openagent>):
  version `5.0.0-beta.62`, loaded as an OpenCode plugin.
- **Magic Context** (`@cortexkit/opencode-magic-context@0.43.1`): long-session
  context management.
- **Venice AI MCP server** (`@veniceai/mcp-server@0.2.0`, MIT,
  <https://github.com/veniceai/venice-mcp-server>): wired into
  `config/opencode.jsonc`.
- **Venice AI skills** (MIT, Copyright (c) 2026 Venice.ai,
  <https://github.com/veniceai/skills>): vendored verbatim into `skills/`.

Hoplon itself is licensed AGPL-3.0-or-later.

[Unreleased]: https://github.com/ShibbityShwab/hoplon/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ShibbityShwab/hoplon/releases/tag/v1.0.0
