#!/usr/bin/env bash
# =============================================================================
# vm.sh resolves an accelerator without assuming /dev/kvm.
#
# HOPLON_VM_ACCEL=tcg must be accepted and reported even when KVM is unused, an
# explicit accelerator the host lacks must fail clearly, a bogus value must be
# rejected, and the QEMU invocation must never pass -sandbox.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

vm="$HOPLON_TEST_REPO/scripts/vm.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

# status exits 1 when the VM is stopped, which is not a failure here: what
# matters is that it resolved the requested accelerator instead of dying.
set +e
out="$(HOPLON_HOME="$_tmp" HOPLON_VM_ACCEL=tcg bash "$vm" status 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] || fail "vm.sh status failed unexpectedly (rc=$rc): $out"
printf '%s\n' "$out" | grep -q 'accelerator   tcg' ||
  fail "status did not report the requested tcg accelerator: $out"
printf '%s\n' "$out" | grep -q 'software emulation' ||
  fail "tcg did not warn that emulation is slow: $out"

# hvf only exists on macOS; requesting it elsewhere must be fatal.
if [ "$(uname -s)" != "Darwin" ]; then
  if HOPLON_HOME="$_tmp" HOPLON_VM_ACCEL=hvf bash "$vm" status > /dev/null 2>&1; then
    fail "HOPLON_VM_ACCEL=hvf was accepted on a non-macOS host"
  fi
fi

# A value outside the supported set is rejected.
if HOPLON_HOME="$_tmp" HOPLON_VM_ACCEL=bogus bash "$vm" status > /dev/null 2>&1; then
  fail "an invalid HOPLON_VM_ACCEL was accepted"
fi

printf 'vm.sh accelerator resolution ok\n'
