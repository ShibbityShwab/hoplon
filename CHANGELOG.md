# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Expanded offensive toolkit.** The Debian guest ships a broad red-team and
  software-exploitation toolset across recon, web, credentials, Active
  Directory, exploit development, fuzzing, reversing, forensics, network
  interception, cloud, and post-exploitation, plus cross-compile toolchains.
  See `docs/tooling.md` and `scripts/toolchain.sh`.
- **Isolation tiers.** `HOPLON_ISOLATION=host|vm` selects where the stack runs:
  the isolated home on this machine or a Debian QEMU/KVM guest. The launcher
  hands off to the matching backend.
- **Debian QEMU guest.** `scripts/vm.sh` creates, boots, and destroys a Debian
  cloud-image guest provisioned by cloud-init, on Linux (KVM), macOS (HVF), and
  Windows (WHPX or TCG). `HOPLON_VM_TOOLS`, `HOPLON_VM_ACCEL`, and the VM knobs
  are documented in `docs/vm.md`.
- **Shared toolchain installer.** `scripts/toolchain.sh` provisions the
  red-team toolbox on Debian and Ubuntu, used by the QEMU guest.

### Changed

- **On-demand guest tooling.** `HOPLON_VM_TOOLS` now defaults to `base`: the VM
  guest installs a minimal package set plus Hoplon and `hoplon-tool`, and fetches
  a red-team tool only when it is needed. `hoplon-tool install NAME` provisions
  one tool, and `/etc/profile.d/hoplon-autotool.sh` installs a known missing
  command on demand (set `HOPLON_AUTO_INSTALL=0` to only suggest it). `core` and
  `full` remain available to preload the arsenal on first boot. See `docs/vm.md`
  and `docs/tooling.md`.

### Removed

- **The host sandbox.** The optional per-OS host sandbox and its knobs are gone.
  Hoplon now ships one cross-platform isolation model: the QEMU virtual machine,
  selected with `HOPLON_ISOLATION=vm`, which runs on Linux (KVM), macOS (HVF),
  and Windows (WHPX or TCG). Host-tier isolation is unchanged: the launcher
  still isolates `HOME`, all four XDG variables, credentials, and config.
- **The NixOS guest and flake.** The declarative NixOS guest and its `flake.nix`, `nix/`, and `scripts/nix-vm.sh` wrapper are removed, and `HOPLON_ISOLATION=nix` is no longer accepted. The Debian QEMU guest (`HOPLON_ISOLATION=vm`) is the single guest.

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
- **`hoplon doctor`.** Reports the opencode version, whether `VENICE_API_KEY` is
  set, which MCP runtimes exist, which weapon binaries are installed, and
  whether Venice is reachable.
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
