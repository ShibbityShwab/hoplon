#!/usr/bin/env bash
# =============================================================================
# `hoplon vm` opens the console inside the guest, which means it delegates to
# `scripts/vm.sh console` with argv intact. The legacy HOPLON_ISOLATION=vm path
# still delegates a subcommand verbatim, and a missing backend fails clearly.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
hoplon_make_repo "$repo"
cat > "$repo/scripts/vm.sh" << 'STUB'
#!/usr/bin/env bash
printf 'vm-delegate:%s\n' "$*"
exit 0
STUB
chmod +x "$repo/scripts/vm.sh"

# `hoplon vm` lands on the console subcommand.
set +e
out_console="$(cd "$_tmp" && "$repo/hoplon" vm 2>&1)"
rc_console=$?
set -e
[ "$rc_console" -eq 0 ] || fail "hoplon vm exited $rc_console: $out_console"
printf '%s\n' "$out_console" | grep -q '^vm-delegate:console$' ||
  fail "hoplon vm did not delegate to scripts/vm.sh console: $out_console"

# Extra arguments pass through, spaces preserved.
set +e
out_args="$(cd "$_tmp" && "$repo/hoplon" vm --flag "arg with space" 2>&1)"
rc_args=$?
set -e
[ "$rc_args" -eq 0 ] || fail "hoplon vm with args exited $rc_args: $out_args"
printf '%s\n' "$out_args" | grep -q '^vm-delegate:console --flag arg with space$' ||
  fail "hoplon vm did not forward its arguments: $out_args"

# The legacy launcher path still delegates the subcommand verbatim.
set +e
out_iso="$(cd "$_tmp" && HOPLON_ISOLATION=vm "$repo/hoplon" run x 2>&1)"
rc_iso=$?
set -e
[ "$rc_iso" -eq 0 ] || fail "HOPLON_ISOLATION=vm run exited $rc_iso: $out_iso"
printf '%s\n' "$out_iso" | grep -q '^vm-delegate:run x$' ||
  fail "HOPLON_ISOLATION=vm no longer delegates the subcommand: $out_iso"

# A missing backend fails clearly instead of falling through to a host launch.
rm -f "$repo/scripts/vm.sh"
set +e
out_missing="$(cd "$_tmp" && "$repo/hoplon" vm 2>&1)"
rc_missing=$?
set -e
[ "$rc_missing" -ne 0 ] || fail "hoplon vm succeeded without scripts/vm.sh"
printf '%s\n' "$out_missing" | grep -q 'scripts/vm.sh is missing' ||
  fail "hoplon vm did not explain the missing backend: $out_missing"

printf 'hoplon vm guest console delegation ok\n'
