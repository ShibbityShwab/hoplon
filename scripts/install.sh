#!/usr/bin/env bash
# =============================================================================
# Hoplon installer.
#
# Fetches a pinned opencode binary into ./bin, links the `hoplon` command onto
# PATH, prepares the isolated home, and optionally pre-seeds plugin caches.
#
# Overridable via environment:
#   HOPLON_OPENCODE_VERSION   default 1.18.25 (the version this repo is tested
#                             on); "latest" tracks the newest release
#   HOPLON_OPENCODE_REPO      default anomalyco/opencode
#   HOPLON_OPENCODE_SHA256    archive digest; the pinned 1.18.25 linux-x64
#                             digest is built in, so verification is on by
#                             default. Set it for any other version/platform.
#   HOPLON_BIN_DIR            where the `hoplon` command is linked
#                             (default $HOME/.local/bin)
# =============================================================================
set -euo pipefail

HOPLON_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)"

# Pull optional settings (version, digest) from .env when present, so a pinned
# HOPLON_OPENCODE_SHA256 in .env actually takes effect. Read .env as data, never
# as code: only NAME=value lines at column 0 are honored, with optional
# surrounding quotes stripped. Sourcing it would let a value execute as shell.
_hoplon_load_env() {
  [ -f "$1" ] && [ -r "$1" ] || return 0
  set -a
  while IFS= read -r _hl_line || [ -n "$_hl_line" ]; do
    _hl_line="${_hl_line%$'\r'}"
    [[ "$_hl_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    _hl_name="${_hl_line%%=*}"
    _hl_value="${_hl_line#*=}"
    case "$_hl_value" in
      \'*\') _hl_value="${_hl_value#\'}" && _hl_value="${_hl_value%\'}" ;;
      \"*\") _hl_value="${_hl_value#\"}" && _hl_value="${_hl_value%\"}" ;;
    esac
    export "$_hl_name=$_hl_value"
  done < "$1"
  set +a
  unset _hl_line _hl_name _hl_value 2> /dev/null || true
}
_hoplon_load_env "$HOPLON_HOME/.env"

VERSION="${HOPLON_OPENCODE_VERSION:-1.18.25}"
REPO="${HOPLON_OPENCODE_REPO:-anomalyco/opencode}"
OMO_SPEC="oh-my-openagent@5.0.0-beta.62"
MC_SPEC="@cortexkit/opencode-magic-context@0.43.1"

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
    printf 'hoplon: unsupported OS: %s\n' "$os" >&2
    exit 1
    ;;
esac
if [ "$VERSION" = "latest" ]; then
  url="https://github.com/${REPO}/releases/latest/download/${asset}"
else
  url="https://github.com/${REPO}/releases/download/v${VERSION}/${asset}"
fi

# Integrity checking is on by default for the pinned release: the digest of the
# 1.18.25 linux-x64 archive is built in. Any other version or platform must set
# HOPLON_OPENCODE_SHA256 explicitly; otherwise the download is fetched but not
# verified, and a warning is printed below.
_default_sha256="58a3729a6f3432dd6d2917fcc4a949788891a035818646ad480e12c947f56e78"
if [ -z "${HOPLON_OPENCODE_SHA256:-}" ] &&
  [ "$VERSION" = "1.18.25" ] && [ "$os" = "linux" ] && [ "$arch" = "x64" ]; then
  HOPLON_OPENCODE_SHA256="$_default_sha256"
fi

mkdir -p "$HOPLON_HOME/bin" "$HOPLON_HOME/home"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'hoplon: downloading opencode %s (%s)\n' "$VERSION" "$asset"
if ! curl -fsSL "$url" -o "$tmp/$asset"; then
  printf 'hoplon: download failed: %s\n' "$url" >&2
  exit 1
fi

# Integrity check. The pinned release carries a built-in digest, so this runs by
# default; set HOPLON_OPENCODE_SHA256 for any other version or platform. A
# mismatch fails closed.
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
else
  printf 'hoplon: warning: no HOPLON_OPENCODE_SHA256 set; %s was not integrity-verified\n' "$asset" >&2
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
# Install the `hoplon` command onto PATH. A symlink back into this checkout
# means repository updates take effect without re-linking, and the launcher
# resolves the link to find its own repo.
# ---------------------------------------------------------------------------
HOPLON_BIN_DIR="${HOPLON_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$HOPLON_BIN_DIR"
HOPLON_BIN_DIR="$(cd "$HOPLON_BIN_DIR" > /dev/null 2>&1 && pwd -P)"
ln -sf "$HOPLON_HOME/hoplon" "$HOPLON_BIN_DIR/hoplon"
printf 'hoplon: linked %s -> %s\n' "$HOPLON_BIN_DIR/hoplon" "$HOPLON_HOME/hoplon"
case ":${PATH:-}:" in
  *":$HOPLON_BIN_DIR:"*) ;;
  *)
    printf 'hoplon: %s is not on PATH. Add this line to your shell rc:\n' "$HOPLON_BIN_DIR"
    printf '  export PATH="%s:$PATH"\n' "$HOPLON_BIN_DIR"
    ;;
esac

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
printf '  2. hoplon                 # or ./hoplon if %s is not on PATH\n' "$HOPLON_BIN_DIR"
