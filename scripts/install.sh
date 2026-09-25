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
#   HOPLON_OPENCODE_SHA256    optional archive digest; verified with sha256sum
# =============================================================================
set -euo pipefail

HOPLON_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)"

# Pull optional settings (version, digest) from .env when present, so a pinned
# HOPLON_OPENCODE_SHA256 in .env actually takes effect.
if [ -f "$HOPLON_HOME/.env" ]; then
  set -a
  . "$HOPLON_HOME/.env"
  set +a
fi

VERSION="${HOPLON_OPENCODE_VERSION:-1.18.25}"
REPO="${HOPLON_OPENCODE_REPO:-anomalyco/opencode}"
OMO_SPEC="oh-my-openagent@5.0.0-beta.62"
MC_SPEC="@cortexkit/opencode-magic-context@0.42.2"

# OMO harness toggle. When 0, the oh-my-openagent cache is not pre-seeded.
HOPLON_ENABLE_OMO="${HOPLON_ENABLE_OMO:-1}"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64) arch="x64" ;;
  aarch64 | arm64) arch="arm64" ;;
esac
case "$os" in
  linux) asset="opencode-linux-${arch}.tar.gz" ;;
  darwin) asset="opencode-darwin-${arch}.zip" ;;
  *)
    printf 'hoplon: unsupported OS: %s\n' "$os" >&2; exit 1
    ;;
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

# Optional integrity check. Pin the digest in .env or the environment to make
# a tampered or partial download fail closed.
if [ -n "${HOPLON_OPENCODE_SHA256:-}" ]; then
  if command -v sha256sum > /dev/null 2>&1; then
    _sha=(sha256sum -c -)
  elif command -v shasum > /dev/null 2>&1; then
    _sha=(shasum -a 256 -c -)
  else
    printf 'hoplon: no sha256 tool found (need sha256sum or shasum)\n' >&2
    exit 1
  fi
  printf '%s  %s\n' "$HOPLON_OPENCODE_SHA256" "$tmp/$asset" | "${_sha[@]}" > /dev/null 2>&1 || {
    printf 'hoplon: checksum mismatch for %s\n' "$asset" >&2
    exit 1
  }
  printf 'hoplon: checksum verified\n'
fi

case "$asset" in
  *.tar.gz) tar --no-same-owner --no-same-permissions -xzf "$tmp/$asset" -C "$tmp" ;;
  *.zip) unzip -q "$tmp/$asset" -d "$tmp" ;;
esac

# POSIX-safe lookup: `find -print -quit` is a GNU extension (BSD find lacks
# -quit). List matches to a file and take the first, which also avoids a
# find | head pipe whose SIGPIPE would trip pipefail.
bin=""
find "$tmp" -type f -name opencode 2> /dev/null > "$tmp/.hoplon-bin-list"
while IFS= read -r _cand; do
  if [ -n "$_cand" ] && [ -f "$_cand" ]; then
    bin="$_cand"
    break
  fi
done < "$tmp/.hoplon-bin-list"
if [ -z "$bin" ]; then
  printf 'hoplon: could not find the opencode binary in the archive\n' >&2
  exit 1
fi
# Install by rename so an interrupted download or extract never leaves a
# truncated binary where the launcher would treat it as valid.
install -m 0755 "$bin" "$HOPLON_HOME/bin/.opencode.new.$$"
mv -f "$HOPLON_HOME/bin/.opencode.new.$$" "$HOPLON_HOME/bin/opencode"
printf 'hoplon: installed %s\n' "$HOPLON_HOME/bin/opencode"
"$HOPLON_HOME/bin/opencode" --version || true

# ---------------------------------------------------------------------------
# Offline convenience: pre-seed the OMO plugin cache from the host, if present.
# The cache dir name must match the plugin spec string in config exactly.
# ---------------------------------------------------------------------------
dst_dir="$HOPLON_HOME/home/.cache/opencode/packages"
mkdir -p "$dst_dir"
for _spec in "$OMO_SPEC" "$MC_SPEC"; do
  # The MIT-licensed magic-context cache is always worth seeding; the OMO cache
  # is skipped when the harness is disabled.
  if [ "$_spec" = "$OMO_SPEC" ] && [ "$HOPLON_ENABLE_OMO" = "0" ]; then
    continue
  fi
  src_cache="${HOME:-}/.cache/opencode/packages/${_spec}"
  if [ -d "$src_cache" ]; then
    cp -a "$src_cache" "$dst_dir/" 2> /dev/null || true
    printf 'hoplon: pre-seeded plugin cache %s\n' "$_spec"
  fi
done

# ---------------------------------------------------------------------------
# Offline convenience: vendor the LSP binaries, the models.dev cache, and OMO's
# ast-grep runtime from the host when present, so first use does not need network.
# ---------------------------------------------------------------------------
_host_home="${HOME:-}"
_home="$HOPLON_HOME/home"
mkdir -p "$_home/.cache/opencode" "$_home/.omo"
if [ -d "$_host_home/.cache/opencode/bin" ]; then
  cp -a "$_host_home/.cache/opencode/bin" "$_home/.cache/opencode/" 2> /dev/null || true
fi
if [ -f "$_host_home/.cache/opencode/models.json" ]; then
  cp -f "$_host_home/.cache/opencode/models.json" "$_home/.cache/opencode/" 2> /dev/null || true
fi
if [ -d "$_host_home/.omo/runtime" ]; then
  cp -a "$_host_home/.omo/runtime" "$_home/.omo/" 2> /dev/null || true
fi
printf 'hoplon: vendored host caches (LSP bin, models.dev, OMO runtime) when present\n'

printf '\nNext steps:\n'
printf '  1. cp .env.example .env   # then set VENICE_API_KEY\n'
printf '  2. ./hoplon\n'
