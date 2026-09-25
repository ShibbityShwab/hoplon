#!/usr/bin/env bash
# =============================================================================
# Hoplon NixOS guest backend.
#
# Builds and boots the declarative NixOS guest described by flake.nix. Unlike
# scripts/vm.sh (a Debian cloud image provisioned with cloud-init), every byte
# of this guest is built from pinned Nix inputs: kernel, userspace, the
# red-team toolchain, and Hoplon itself.
#
# Usage:
#   nix-vm.sh build   build the qcow2 disk image (packages.<system>.qcow2)
#   nix-vm.sh run     boot the guest under QEMU/KVM (apps.<system>.vm)
#   nix-vm.sh help
#
# The launcher execs this script when HOPLON_ISOLATION=nix. With no subcommand
# the script defaults to `run`.
#
# Environment:
#   HOPLON_HOME        repo root (defaults to this script's parent)
#   HOPLON_NIX_FLAKE   flake ref or directory to build (default $HOPLON_HOME)
#   HOPLON_NIX_OUT     out-link for the built image
#                      (default $HOPLON_HOME/vm/nixos-qcow2)
# =============================================================================
set -euo pipefail

HOPLON_HOME="${HOPLON_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)}"
export HOPLON_HOME

# Optional local settings, matching the other scripts: values in .env win over
# the ambient environment.
if [ -f "$HOPLON_HOME/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$HOPLON_HOME/.env"
  set +a
fi

NIX_FLAKE="${HOPLON_NIX_FLAKE:-$HOPLON_HOME}"
NIX_OUT="${HOPLON_NIX_OUT:-$HOPLON_HOME/vm/nixos-qcow2}"

log() { printf 'nix-vm: %s\n' "$*"; }
warn() { printf 'nix-vm: %s\n' "$*" >&2; }
die() {
  printf 'nix-vm: %s\n' "$*" >&2
  exit 1
}

# Print the official install commands and exit non-zero. Nix is the one hard
# prerequisite; everything else is built from the flake.
need_nix() {
  if command -v nix > /dev/null 2>&1; then
    return 0
  fi
  cat >&2 << 'EOF'
nix-vm: `nix` was not found on PATH.

Install Nix from https://nixos.org/download, then re-run. Two supported forms:

  # Multi-user (recommended on a systemd host; prompts for sudo):
  sh <(curl -L https://nixos.org/nix/install) --daemon

  # Single-user, no daemon (does not need root):
  sh <(curl -L https://nixos.org/nix/install) --no-daemon

Open a new shell afterwards so the Nix profile is on PATH, then enable flakes:

  mkdir -p ~/.config/nix
  echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
EOF
  exit 1
}

# Resolve the directory that actually holds flake.nix. HOPLON_HOME points at a
# host checkout; the packaged guest payload has no flake, so fall back to the
# current directory.
resolve_flake() {
  if [ -n "${HOPLON_NIX_FLAKE:-}" ]; then
    printf '%s' "$NIX_FLAKE"
    return 0
  fi
  if [ -f "$HOPLON_HOME/flake.nix" ]; then
    printf '%s' "$HOPLON_HOME"
    return 0
  fi
  if [ -f "$PWD/flake.nix" ]; then
    printf '%s' "$PWD"
    return 0
  fi
  die "no flake.nix found in $HOPLON_HOME or $PWD (set HOPLON_NIX_FLAKE)"
}

# Turn a local directory into a `path:` ref so untracked files are visible (a
# bare path inside a git repo only sees tracked files). Remote refs pass through.
flake_target() {
  local ref="${1:?flake_target needs a ref}"
  local attr="${2:?flake_target needs an attribute}"
  if [ -d "$ref" ]; then
    printf 'path:%s#%s' "$ref" "$attr"
  else
    printf '%s#%s' "$ref" "$attr"
  fi
}

cmd_build() {
  need_nix
  local ref target image
  ref="$(resolve_flake)"
  target="$(flake_target "$ref" qcow2)"
  mkdir -p "$(dirname "$NIX_OUT")"
  log "building qcow2 image: $target"
  log "the first build compiles the whole guest and can take a long time"
  nix build "$target" --print-build-logs -o "$NIX_OUT"
  image="$(find -L "$NIX_OUT" -maxdepth 2 -name '*.qcow2' -print -quit 2> /dev/null || true)"
  printf '\nnix-vm: build complete\n'
  printf '  image  %s\n' "${image:-$NIX_OUT}"
  printf '  boot   %s run\n' "$0"
}

cmd_run() {
  need_nix
  local ref target
  ref="$(resolve_flake)"
  target="$(flake_target "$ref" vm)"
  log "booting the NixOS guest under QEMU/KVM: $target"
  log "serial console and guest ssh on 127.0.0.1:2222 are wired up"
  exec nix run "$target" -- "$@"
}

cmd_help() {
  cat << 'EOF'
Hoplon NixOS guest backend.

Usage:
  nix-vm.sh build   build the qcow2 disk image (packages.<system>.qcow2)
  nix-vm.sh run     boot the guest under QEMU/KVM (apps.<system>.vm)
  nix-vm.sh help

With no subcommand the script defaults to `run`, which is what the launcher
does for HOPLON_ISOLATION=nix.

Requirements: nix with flakes enabled, and /dev/kvm for acceleration (QEMU
falls back to emulation without it, which is very slow).

See docs/nixos-vm.md for login details, the shipped toolchain, and tradeoffs
against the Debian QEMU guest.
EOF
}

main() {
  local cmd="${1:-run}"
  if [ "$#" -gt 0 ]; then
    shift
  fi
  case "$cmd" in
    build) cmd_build "$@" ;;
    run) cmd_run "$@" ;;
    help | -h | --help) cmd_help ;;
    *)
      warn "unknown subcommand: $cmd"
      cmd_help >&2
      exit 2
      ;;
  esac
}

main "$@"
