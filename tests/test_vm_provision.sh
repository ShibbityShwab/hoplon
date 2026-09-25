#!/usr/bin/env bash
# =============================================================================
# cloud-init provisioning hands /opt/hoplon to the hoplon user before it runs
# install.sh, verifies the hoplon command is on PATH, and skips the 9p share for
# a bare (HOPLON_VM_TOOLS=none) guest.
#
# The bootstrap is extracted from vm/cloud-init/user-data.yaml so the test reads
# the shipped template. The ownership failure is reproduced with an unwritable
# temp prefix: the install prefix cannot be created, then restoring write
# permission (the effect of the chown) makes the same install succeed.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

_tmp="$(mktemp -d)"
trap 'chmod -R u+rwX "$_tmp" 2> /dev/null || true; rm -rf "$_tmp"' EXIT

yaml_file="$HOPLON_TEST_REPO/vm/cloud-init/user-data.yaml"
bootstrap="$_tmp/bootstrap.sh"

python3 - "$yaml_file" "$bootstrap" << 'PY'
import sys

import yaml

doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for entry in doc["write_files"]:
    if entry["path"] == "/usr/local/sbin/hoplon-vm-bootstrap":
        open(sys.argv[2], "w", encoding="utf-8").write(entry["content"])
        break
else:
    raise SystemExit("bootstrap not found in cloud-init user-data")
PY
[ -s "$bootstrap" ] || fail "the cloud-init bootstrap extracted empty"

# 1. Ownership handoff must run before install.sh, or install.sh fails as hoplon.
chown_line="$(grep -n 'chown -R hoplon:hoplon' "$bootstrap" | head -n 1 | cut -d: -f1 || true)"
install_line="$(grep -n 'runuser -u hoplon' "$bootstrap" | head -n 1 | cut -d: -f1 || true)"
[ -n "$chown_line" ] || fail "the bootstrap never chowns the checkout to hoplon"
[ -n "$install_line" ] || fail "the bootstrap never runs install.sh as hoplon"
[ "$chown_line" -lt "$install_line" ] ||
  fail "chown (line $chown_line) must precede the hoplon install (line $install_line)"

# 2. The bootstrap verifies the hoplon command resolves on the user's PATH.
grep -q 'command -v hoplon' "$bootstrap" ||
  fail "the bootstrap does not verify the hoplon command is on PATH"

# 3. A bare guest skips the 9p share: the mount is gated on the tools level.
mount_cond="$(grep -n 'mountpoint -q /mnt/engagements' "$bootstrap" | head -n 1 | cut -d: -f1 || true)"
[ -n "$mount_cond" ] || fail "the bootstrap never checks the engagements mount"
guard="$(sed -n "$((mount_cond - 1))p" "$bootstrap")"
printf '%s\n' "$guard" | grep -q 'HOPLON_VM_TOOLS' ||
  fail "the 9p mount is not gated on HOPLON_VM_TOOLS: $guard"
printf '%s\n' "$guard" | grep -q 'none' ||
  fail "the 9p mount does not skip HOPLON_VM_TOOLS=none: $guard"

# 4. Reproduce the unwritable-HOPLON_HOME failure and show the fix. install.sh
# writes bin/ and home/ at the checkout root; before the chown those live on a
# root-owned tree and mkdir fails.
sim="$_tmp/opt/hoplon"
mkdir -p "$sim/scripts"
cat > "$sim/scripts/install.sh" << 'SIM'
#!/usr/bin/env bash
set -euo pipefail
HOPLON_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)"
mkdir -p "$HOPLON_HOME/bin" "$HOPLON_HOME/home"
printf 'installed\n'
SIM
chmod +x "$sim/scripts/install.sh"
chmod -R a-w "$sim"
set +e
bash "$sim/scripts/install.sh" > "$_tmp/before.log" 2>&1
rc_before=$?
set -e
[ "$rc_before" -ne 0 ] || fail "an unwritable prefix unexpectedly accepted the install"
grep -qi 'permission denied' "$_tmp/before.log" ||
  fail "the unwritable prefix did not fail with a permission error: $(cat "$_tmp/before.log")"

# chmod u+w is what the chown grants the hoplon user; the same prefix now works.
chmod -R u+rwX "$sim"
bash "$sim/scripts/install.sh" > /dev/null 2>&1 ||
  fail "the install still failed after the prefix became writable"

printf 'cloud-init provisioning ownership and share gating ok\n'
