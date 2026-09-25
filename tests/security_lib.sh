#!/usr/bin/env bash
# =============================================================================
# Shared helpers for the launcher security regression tests. Sourced, never
# executed (the name omits the test_ prefix so tests/run.sh does not pick it up).
# =============================================================================

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

# hoplon_secure_repo <dst>: like hoplon_make_repo, plus a VERSION file and the
# isolated state home. The caller overwrites bin/opencode with its probe stub.
hoplon_secure_repo() {
  hoplon_make_repo "$1"
  [ -f "$HOPLON_TEST_REPO/VERSION" ] && cp "$HOPLON_TEST_REPO/VERSION" "$1/VERSION"
  mkdir -p "$1/home"
}

# hoplon_skip <reason>: a prerequisite (bwrap, network) is unavailable here.
hoplon_skip() {
  printf 'SKIP: %s\n' "$1"
  exit 0
}

# hoplon_have_bwrap: true when bubblewrap can create a user namespace here.
hoplon_have_bwrap() {
  command -v bwrap > /dev/null 2>&1 &&
    bwrap --unshare-user --ro-bind / / /bin/true > /dev/null 2>&1
}
