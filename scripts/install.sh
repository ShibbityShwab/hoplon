#!/usr/bin/env bash
# =============================================================================
# Hoplon installer.
#
# Fetches a pinned opencode binary into ./bin, prepares the isolated home, and
# optionally pre-seeds the OMO plugin cache for offline use.
#
# Overridable via environment:
#   HOPLON_OPENCODE_VERSION   default 1.18.25 (the version this repo is tested on)
#   HOPLON_OPENCODE_REPO      default anomalyco/opencode
# =============================================================================
set -euo pipefail

HOPLON_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
VERSION="${HOPLON_OPENCODE_VERSION:-1.18.25}"
REPO="${HOPLON_OPENCODE_REPO:-anomalyco/opencode}"
OMO_SPEC="oh-my-openagent@5.0.0-beta.62"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="x64" ;;
  aarch64|arm64) arch="arm64" ;;
esac
case "$os" in
  linux)  asset="opencode-linux-${arch}.tar.gz" ;;
  darwin) asset="opencode-darwin-${arch}.zip" ;;
  *) printf 'hoplon: unsupported OS: %s\n' "$os" >&2; exit 1 ;;
esac
url="https://github.com/${REPO}/releases/download/v${VERSION}/${asset}"

mkdir -p "$HOPLON_HOME/bin" "$HOPLON_HOME/home"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'hoplon: downloading opencode %s (%s)\n' "$VERSION" "$asset"
if ! curl -fsSL "$url" -o "$tmp/$asset"; then
  printf 'hoplon: download failed: %s\n' "$url" >&2
  exit 1
fi

case "$asset" in
  *.tar.gz) tar -xzf "$tmp/$asset" -C "$tmp" ;;
  *.zip)    unzip -q  "$tmp/$asset" -d "$tmp" ;;
esac

bin="$(find "$tmp" -type f -name opencode | head -1)"
if [ -z "$bin" ]; then
  printf 'hoplon: could not find the opencode binary in the archive\n' >&2
  exit 1
fi
install -m 0755 "$bin" "$HOPLON_HOME/bin/opencode"
printf 'hoplon: installed %s\n' "$HOPLON_HOME/bin/opencode"
"$HOPLON_HOME/bin/opencode" --version || true

# ---------------------------------------------------------------------------
# Offline convenience: pre-seed the OMO plugin cache from the host, if present.
# The cache dir name must match the plugin spec string in config exactly.
# ---------------------------------------------------------------------------
src_cache="${HOME:-}/.cache/opencode/packages/${OMO_SPEC}"
if [ -d "$src_cache" ]; then
  dst_dir="$HOPLON_HOME/home/.cache/opencode/packages"
  mkdir -p "$dst_dir"
  cp -a "$src_cache" "$dst_dir/" 2>/dev/null || true
  printf 'hoplon: pre-seeded OMO plugin cache from host\n'
fi

printf '\nNext steps:\n'
printf '  1. cp .env.example .env   # then set VENICE_API_KEY\n'
printf '  2. ./hoplon\n'
