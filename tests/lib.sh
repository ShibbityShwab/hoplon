#!/usr/bin/env bash
# =============================================================================
# Shared helpers for the Hoplon launcher test suite. Sourced, never executed.
# =============================================================================

# Resolve the repository root from this file's location.
HOPLON_TEST_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)"
export HOPLON_TEST_REPO

# Build a disposable copy of the launcher plus the config it reads, with a stub
# bin/opencode that exits 0. This lets a test drive a full launch cycle without
# the real opencode binary or the network. $1 is the destination root.
hoplon_make_repo() {
  _dst="$1"
  mkdir -p "$_dst/config" "$_dst/bin" "$_dst/scripts"
  cp "$HOPLON_TEST_REPO/hoplon" "$_dst/hoplon"
  cp "$HOPLON_TEST_REPO/config/opencode.jsonc" "$_dst/config/opencode.jsonc"
  cp "$HOPLON_TEST_REPO/config/omo.jsonc" "$_dst/config/omo.jsonc"
  if [ -f "$HOPLON_TEST_REPO/scripts/env.sh" ]; then
    cp "$HOPLON_TEST_REPO/scripts/env.sh" "$_dst/scripts/env.sh"
  fi
  if [ -f "$HOPLON_TEST_REPO/config/tui.json" ]; then
    cp "$HOPLON_TEST_REPO/config/tui.json" "$_dst/config/tui.json"
  fi
  chmod +x "$_dst/hoplon"
  cat > "$_dst/bin/opencode" << 'STUB'
#!/usr/bin/env bash
# Test stub: a launch is a no-op success.
exit 0
STUB
  chmod +x "$_dst/bin/opencode"
}

# Assertion helpers. Each exits non-zero with a readable message on failure.
fail() {
  printf 'ASSERT FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  grep -q -- "$2" "$1" 2> /dev/null || fail "${3:-expected to find [$2] in $1}"
}

assert_file_lacks() {
  if grep -q -- "$2" "$1" 2> /dev/null; then
    fail "${3:-did not expect [$2] in $1}"
  fi
}

assert_no_file() {
  [ ! -e "$1" ] || fail "${2:-expected no file at $1}"
}

assert_file_exists() {
  [ -f "$1" ] || fail "${2:-expected a file at $1}"
}
