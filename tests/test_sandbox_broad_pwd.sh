#!/usr/bin/env bash
# =============================================================================
# Broad launch-directory guard.
#
# Binding --bind "$PWD" "$PWD" from /, the host home, or an ancestor of the host
# home would expose every file under that root read-write. The launcher must
# refuse unless HOPLON_SANDBOX_ALLOW_BROAD=1 is set, in which case it warns and
# proceeds. A genuine project directory must still launch.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/security_lib.sh
. "$_here/security_lib.sh"

hoplon_have_bwrap || hoplon_skip "bwrap cannot create a user namespace here"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
hoplon_secure_repo "$repo"
printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/bin/opencode"
chmod +x "$repo/bin/opencode"

hosthome="$_tmp/hosthome"
mkdir -p "$hosthome/.ssh" "$_tmp/proj"

_run() {
  # $1 = cwd, remaining = extra env assignments (KEY=VALUE) before the command.
  _cwd="$1"
  shift
  (cd "$_cwd" && env HOPLON_SANDBOX=1 HOPLON_ENABLE_OMO=0 HOPLON_HOST_HOME="$hosthome" "$@" "$repo/hoplon")
}

# Launching from the host home itself is refused.
if _run "$hosthome" > "$_tmp/home.log" 2>&1; then
  fail "sandbox launch from the host home was allowed"
fi
assert_file_contains "$_tmp/home.log" "refusing to sandbox" "no refusal notice for the host home"

# Launching from an ancestor of the host home is refused.
if _run "$_tmp" > "$_tmp/anc.log" 2>&1; then
  fail "sandbox launch from an ancestor of the host home was allowed"
fi
assert_file_contains "$_tmp/anc.log" "refusing to sandbox" "no refusal notice for the ancestor directory"

# A genuine project directory still launches.
if ! _run "$_tmp/proj" > "$_tmp/proj.log" 2>&1; then
  printf 'project launch log:\n' >&2
  cat "$_tmp/proj.log" >&2
  fail "sandbox launch from a normal project directory failed"
fi

# The override warns loudly and proceeds.
if ! _run "$hosthome" HOPLON_SANDBOX_ALLOW_BROAD=1 > "$_tmp/broad.log" 2>&1; then
  fail "HOPLON_SANDBOX_ALLOW_BROAD=1 did not bypass the guard"
fi
assert_file_contains "$_tmp/broad.log" "WARNING" "override did not warn"

printf 'broad launch-directory guard ok\n'
