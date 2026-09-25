#!/usr/bin/env bash
# =============================================================================
# One isolation model, no sandbox code.
#
# The launcher and the VM backend must carry no references to the removed host
# sandbox or the removed secondary guest tier. The forbidden names are
# assembled from fragments so this guard file itself does not contain them.
# HOPLON_ISOLATION=host and =vm must be accepted; an unknown tier, including
# the removed secondary guest, must fail closed with a clear message.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

_sandbox_var="HOPLON_""SANDBOX"
_sandbox_bin="b""wrap"
_removed_tier="n""ix"
_removed_script="n""ix-vm.sh"

assert_file_lacks "$HOPLON_TEST_REPO/hoplon" "$_sandbox_var" "the launcher still references the removed sandbox variable"
assert_file_lacks "$HOPLON_TEST_REPO/hoplon" "$_sandbox_bin" "the launcher still references the removed sandbox binary"
assert_file_lacks "$HOPLON_TEST_REPO/hoplon" "$_removed_tier" "the launcher still references the removed guest tier"
assert_file_lacks "$HOPLON_TEST_REPO/hoplon" "$_removed_script" "the launcher still references the removed guest backend"
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

# HOPLON_ISOLATION=vm is accepted and forwards to the backend with argv intact.
set +e
out_vm="$(cd "$_tmp" && HOPLON_ISOLATION=vm "$repo/hoplon" run --flag "arg with space" 2>&1)"
rc_vm=$?
set -e
[ "$rc_vm" -eq 0 ] || fail "HOPLON_ISOLATION=vm exited $rc_vm: $out_vm"
printf '%s\n' "$out_vm" | grep -q '^vm-delegate:run --flag arg with space$' ||
  fail "HOPLON_ISOLATION=vm did not delegate to scripts/vm.sh with args: $out_vm"

# HOPLON_ISOLATION=host is accepted and never reaches the VM backend.
set +e
out_host="$(cd "$_tmp" && HOPLON_ISOLATION=host HOPLON_ENABLE_OMO=0 "$repo/hoplon" 2>&1)"
rc_host=$?
set -e
[ "$rc_host" -eq 0 ] || fail "HOPLON_ISOLATION=host exited $rc_host: $out_host"
if printf '%s\n' "$out_host" | grep -q 'vm-delegate'; then
  fail "HOPLON_ISOLATION=host delegated to the VM backend"
fi

# The default (no variable) is the host tier and does not delegate either.
out_default="$(cd "$_tmp" && HOPLON_ENABLE_OMO=0 "$repo/hoplon" 2>&1 || true)"
if printf '%s\n' "$out_default" | grep -q 'vm-delegate'; then
  fail "the default host tier delegated to the VM backend"
fi

# The removed secondary guest tier is rejected: non-zero, clear message, and
# the rejected value is named.
set +e
out_removed="$(cd "$_tmp" && HOPLON_ISOLATION="$_removed_tier" "$repo/hoplon" 2>&1)"
rc_removed=$?
set -e
[ "$rc_removed" -ne 0 ] || fail "the removed [$_removed_tier] tier was accepted"
printf '%s\n' "$out_removed" | grep -q 'invalid HOPLON_ISOLATION' ||
  fail "the removed tier did not print a clear message: $out_removed"
printf '%s\n' "$out_removed" | grep -q -- "$_removed_tier" ||
  fail "the invalid-tier message did not name the rejected value: $out_removed"

# An unknown tier exits non-zero with a clear message.
if (cd "$_tmp" && HOPLON_ISOLATION=bogus "$repo/hoplon" > /dev/null 2>&1); then
  fail "an invalid HOPLON_ISOLATION was accepted"
fi

printf 'no sandbox code and isolation tiers ok\n'
