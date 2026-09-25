#!/usr/bin/env bash
# =============================================================================
# Hoplon updater.
#
# Updates Hoplon in place. When this directory is a git checkout it pulls the
# latest revision with --ff-only, then re-runs scripts/install.sh to re-fetch
# the requested opencode binary and re-seed the caches. A dirty tree aborts
# before any pull unless --force is given, so local work is never discarded.
#
# Usage:
#   hoplon update [--force]
#
# Environment (passed through to scripts/install.sh):
#   HOPLON_OPENCODE_VERSION   opencode release to fetch; "latest" tracks the
#                             newest release (default: the installer's pin)
#   HOPLON_BIN_DIR            where the `hoplon` command is linked
# =============================================================================
set -euo pipefail

HOPLON_HOME="${HOPLON_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)}"
export HOPLON_HOME

_force=0
for _arg in "$@"; do
  case "$_arg" in
    --force | -f) _force=1 ;;
    -h | --help)
      printf 'usage: hoplon update [--force]\n'
      printf '  --force  attempt the pull even when the tree has local changes\n'
      exit 0
      ;;
    *)
      printf 'hoplon update: unknown argument: %s\n' "$_arg" >&2
      exit 2
      ;;
  esac
done

_hoplon_version() {
  if [ -f "$HOPLON_HOME/VERSION" ]; then
    tr -d '[:space:]' < "$HOPLON_HOME/VERSION"
  else
    printf 'unknown'
  fi
}

_hoplon_opencode_version() {
  if [ -x "$HOPLON_HOME/bin/opencode" ]; then
    "$HOPLON_HOME/bin/opencode" --version 2> /dev/null || printf 'unknown'
  else
    printf 'missing'
  fi
}

printf 'hoplon: before  hoplon %s  opencode %s\n' "$(_hoplon_version)" "$(_hoplon_opencode_version)"

# Pull only when this is a git checkout. A dirty tree is a hard stop so an
# update never merges over or discards uncommitted work behind the operator's
# back; --force is the explicit override.
if command -v git > /dev/null 2>&1 && git -C "$HOPLON_HOME" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  if [ "$_force" != "1" ] && [ -n "$(git -C "$HOPLON_HOME" status --porcelain)" ]; then
    printf 'hoplon update: %s has local changes. Commit or stash them, or re-run with --force.\n' "$HOPLON_HOME" >&2
    exit 1
  fi
  printf 'hoplon: pulling %s\n' "$HOPLON_HOME"
  git -C "$HOPLON_HOME" pull --ff-only
else
  printf 'hoplon: %s is not a git checkout; skipping pull\n' "$HOPLON_HOME" >&2
fi

printf 'hoplon: re-running scripts/install.sh\n'
"$HOPLON_HOME/scripts/install.sh"

printf 'hoplon: after   hoplon %s  opencode %s\n' "$(_hoplon_version)" "$(_hoplon_opencode_version)"
