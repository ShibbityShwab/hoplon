#!/usr/bin/env bash
# =============================================================================
# `hoplon setup` is the one-command first run: it installs the runtime when it
# is missing, creates .env with mode 600, is safe to re-run, and never prints
# the API key. A non-TTY stdin makes the prompt path skip deterministically, and
# a stub installer keeps the run offline.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
hoplon_make_repo "$repo"
# setup must take the install path, so start with no runtime.
rm -f "$repo/bin/opencode"
cp "$HOPLON_TEST_REPO/.env.example" "$repo/.env.example"

cat > "$repo/scripts/install.sh" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
HOPLON_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)"
printf 'stub-install\n' >> "$HOPLON_HOME/installer.runs"
mkdir -p "$HOPLON_HOME/bin"
printf '#!/usr/bin/env bash\nprintf "stub-opencode 0.0.0\\n"\n' > "$HOPLON_HOME/bin/opencode"
chmod +x "$HOPLON_HOME/bin/opencode"
STUB
chmod +x "$repo/scripts/install.sh"

home="$_tmp/home"
mkdir -p "$home"

env_mode() {
  stat -c '%a' "$1" 2> /dev/null || stat -L -f '%Lp' "$1" 2> /dev/null
}

# First run: installs the runtime, creates .env, ends with the environment report.
set +e
out1="$(HOME="$home" bash "$repo/hoplon" setup < /dev/null 2>&1)"
rc1=$?
set -e
[ "$rc1" -eq 0 ] || fail "hoplon setup exited $rc1: $out1"
assert_file_exists "$repo/.env" "setup did not create .env"
[ "$(cat "$repo/.env")" = "$(cat "$HOPLON_TEST_REPO/.env.example")" ] ||
  fail "setup created .env that does not match .env.example"
assert_file_exists "$repo/installer.runs" "setup did not run scripts/install.sh"
[ "$(wc -l < "$repo/installer.runs")" -eq 1 ] || fail "the installer ran more than once"
printf '%s\n' "$out1" | grep -q 'hoplon doctor' || fail "setup did not end with the doctor report"
[ "$(env_mode "$repo/.env")" = "600" ] || fail ".env is not mode 600: $(env_mode "$repo/.env")"

# Second run: idempotent. The installer is skipped and .env mode is unchanged.
set +e
out2="$(HOME="$home" bash "$repo/hoplon" setup < /dev/null 2>&1)"
rc2=$?
set -e
[ "$rc2" -eq 0 ] || fail "second hoplon setup exited $rc2: $out2"
[ "$(wc -l < "$repo/installer.runs")" -eq 1 ] ||
  fail "setup re-ran the installer on an already-provisioned tree"
printf '%s\n' "$out2" | grep -q 'runtime present' ||
  fail "second setup did not report the runtime as present: $out2"
[ "$(env_mode "$repo/.env")" = "600" ] || fail ".env mode changed on the second run"

# A key that is already set is reported as set and never echoed in the output.
sed -i 's/^VENICE_API_KEY=.*/VENICE_API_KEY=supersecretvalue123/' "$repo/.env"
set +e
out3="$(HOME="$home" bash "$repo/hoplon" setup < /dev/null 2>&1)"
rc3=$?
set -e
[ "$rc3" -eq 0 ] || fail "third hoplon setup exited $rc3: $out3"
if printf '%s\n' "$out3" | grep -q 'supersecretvalue123'; then
  fail "setup printed the API key value"
fi
printf '%s\n' "$out3" | grep -q 'already set in .env' ||
  fail "setup did not report the key as already set: $out3"
[ "$(env_mode "$repo/.env")" = "600" ] || fail ".env mode changed after the key was set"

printf 'hoplon setup one-command path ok\n'
