#!/usr/bin/env bash
# =============================================================================
# One isolation model, no sandbox code.
#
# The launcher and the VM backend must carry no references to the removed host
# sandbox. The forbidden names are assembled from fragments so this guard file
# itself does not contain them. HOPLON_ISOLATION=vm must hand off to
# scripts/vm.sh with the original arguments; the default host tier must not
# delegate, and an unknown tier must still fail closed.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

_sandbox_var="HOPLON_""SANDBOX"
_sandbox_bin="b""wrap"

assert_file_lacks "$HOPLON_TEST_REPO/hoplon" "$_sandbox_var" "the launcher still references the removed sandbox variable"
assert_file_lacks "$HOPLON_TEST_REPO/hoplon" "$_sandbox_bin" "the launcher still references the removed sandbox binary"
assert_file_lacks "$HOPLON_TEST_REPO/scripts/vm.sh" "$_sandbox_var" "vm.sh still references the removed sandbox variable"
assert_file_lacks "$HOPLON_TEST_REPO/scripts/vm.sh" "-sandbox" "vm.sh must not pass -sandbox (it broke the guest boot)"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
hoplon_make_repo "$repo"
mkdir -p "$repo/scripts"
cat > "$repo/scripts/vm.sh" << 'STUB'
#!/usr/bin/env bash
printf 'vm-delegate:%s\n' "$*"
exit 0
STUB
chmod +x "$repo/scripts/vm.sh"

# HOPLON_ISOLATION=vm forwards to the backend with argv intact.
out="$(cd "$_tmp" && HOPLON_ISOLATION=vm "$repo/hoplon" run --flag "arg with space" 2>&1)"
printf '%s\n' "$out" | grep -q '^vm-delegate:run --flag arg with space$' ||
  fail "HOPLON_ISOLATION=vm did not delegate to scripts/vm.sh with args: $out"

# The default host tier runs opencode and never reaches the VM backend.
out_host="$(cd "$_tmp" && HOPLON_ENABLE_OMO=0 "$repo/hoplon" 2>&1 || true)"
if printf '%s\n' "$out_host" | grep -q 'vm-delegate'; then
  fail "the default host tier delegated to the VM backend"
fi

# An unknown tier exits non-zero with a clear message.
if (cd "$_tmp" && HOPLON_ISOLATION=bogus "$repo/hoplon" > /dev/null 2>&1); then
  fail "an invalid HOPLON_ISOLATION was accepted"
fi

printf 'no sandbox code and vm delegation ok\n'
