#!/usr/bin/env bash
# =============================================================================
# The cloud-init on-demand tool hook behaves as documented.
#
# The real hook is extracted from vm/cloud-init/user-data.yaml, so the test
# covers the shipped content. A stub hoplon-tool stands in for the installer,
# keeping the whole test offline: a known-but-missing command calls install and
# then re-execs, an unknown command only prints a hint, HOPLON_AUTO_INSTALL=0
# never installs, and a failed install returns instead of looping.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

yaml_file="$HOPLON_TEST_REPO/vm/cloud-init/user-data.yaml"
hook="$_tmp/hook.sh"

# Pull the /etc/profile.d hook out of the cloud-init template. Prefer PyYAML,
# which the repo already uses to validate the file, and fall back to a block
# scan so the test still runs where the module is absent.
extract_hook() {
  if python3 -c 'import yaml' > /dev/null 2>&1; then
    python3 - "$yaml_file" "$hook" << 'PY'
import sys

import yaml

doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for entry in doc["write_files"]:
    if entry["path"] == "/etc/profile.d/hoplon-autotool.sh":
        open(sys.argv[2], "w", encoding="utf-8").write(entry["content"])
        break
else:
    raise SystemExit("hook not found in cloud-init user-data")
PY
    return 0
  fi
  awk '
    /^  - path: \/etc\/profile\.d\/hoplon-autotool\.sh[[:space:]]*$/ { want = 1; next }
    want && /^    content: \|$/ { body = 1; next }
    body {
      if ($0 == "") { print ""; next }
      if ($0 ~ /^      /) { sub(/^      /, ""); print; next }
      exit
    }
  ' "$yaml_file" > "$hook"
}

make_stub() { # bindir
  local bindir="$1"
  mkdir -p "$bindir"
  cat > "$bindir/hoplon-tool" << 'STUB'
#!/usr/bin/env bash
log="${HOPLON_TEST_LOG:?}"
bindir="${HOPLON_TEST_BINDIR:?}"
cmd="${1:-}"
if [ "$#" -gt 0 ]; then shift; fi
case "$cmd" in
  known)
    printf 'known %s\n' "${1:-}" >> "$log"
    [ "${1:-}" = "knowncmd" ]
    ;;
  install)
    printf 'install %s\n' "${1:-}" >> "$log"
    if [ "${HOPLON_TEST_FAIL_INSTALL:-0}" = "1" ]; then
      exit 1
    fi
    {
      printf '#!/usr/bin/env bash\n'
      printf 'printf "REEXEC:%%s\\n" "%s"\n' "${1:-}"
    } > "$bindir/${1:-}"
    chmod +x "$bindir/${1:-}"
    ;;
  status)
    printf 'status\n' >> "$log"
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "$bindir/hoplon-tool"
}

# run_case bindir log outfile mode command...: run the hook in a non-interactive
# child bash with the stub first on PATH. mode picks the environment.
RUN_RC=0
run_case() {
  local bindir="$1" log="$2" outfile="$3" mode="$4"
  shift 4
  local -a envp=(
    "PATH=$bindir:$PATH"
    "HOPLON_TEST_LOG=$log"
    "HOPLON_TEST_BINDIR=$bindir"
  )
  case "$mode" in
    suggest) envp+=("HOPLON_AUTO_INSTALL=0") ;;
    fail) envp+=("HOPLON_TEST_FAIL_INSTALL=1") ;;
    busy) envp+=("HOPLON_AUTOTOOL_BUSY=1") ;;
  esac
  set +e
  env "${envp[@]}" bash -c '. "$1"; shift; "$@"' _ "$hook" "$@" > "$outfile" 2>&1
  RUN_RC=$?
  set -e
}

extract_hook
[ -s "$hook" ] || fail "the cloud-init hook extracted empty"

A="$_tmp/a"
make_stub "$A/bin"

# The function must reach a non-interactive child bash, not just the shell that
# sourced the hook.
set +e
env "PATH=$A/bin:$PATH" bash -c '. "$1"; bash -c "declare -F command_not_found_handle"' _ "$hook" > /dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "the hook was not exported to a non-interactive child bash"

# A known-but-missing command installs, then runs.
: > "$A/calls.log"
run_case "$A/bin" "$A/calls.log" "$A/out.txt" auto knowncmd alpha beta
[ "$RUN_RC" -eq 0 ] || fail "the auto-install path exited $RUN_RC: $(cat "$A/out.txt")"
assert_file_contains "$A/out.txt" 'REEXEC:knowncmd' "the freshly installed command did not run"
assert_file_contains "$A/out.txt" 'installing knowncmd on demand' "the install was not announced"
assert_file_contains "$A/calls.log" 'install knowncmd' "a known command did not trigger an install"

B="$_tmp/b"
make_stub "$B/bin"

# An unknown command only hints; nothing is installed.
: > "$B/calls.log"
run_case "$B/bin" "$B/calls.log" "$B/out.txt" auto unknowncmd
[ "$RUN_RC" -eq 127 ] || fail "an unknown command should exit 127 (got $RUN_RC)"
assert_file_contains "$B/out.txt" 'not a known tool' "an unknown command got no hint"
assert_file_lacks "$B/calls.log" 'install' "an unknown command triggered an install"

# HOPLON_AUTO_INSTALL=0 only suggests, it never installs.
: > "$B/calls.log"
run_case "$B/bin" "$B/calls.log" "$B/off.txt" suggest knowncmd
[ "$RUN_RC" -eq 127 ] || fail "HOPLON_AUTO_INSTALL=0 should exit 127 (got $RUN_RC)"
assert_file_contains "$B/off.txt" 'is not installed' "HOPLON_AUTO_INSTALL=0 gave no hint"
assert_file_lacks "$B/calls.log" 'install' "HOPLON_AUTO_INSTALL=0 triggered an install"

# A failed install returns instead of looping when the command stays missing.
: > "$B/calls.log"
run_case "$B/bin" "$B/calls.log" "$B/fail.txt" fail knowncmd
[ "$RUN_RC" -eq 127 ] || fail "a failed install should exit 127 (got $RUN_RC)"
assert_file_contains "$B/fail.txt" 'could not install knowncmd' "a failed install gave no message"
assert_file_contains "$B/calls.log" 'install knowncmd' "a failed install was never attempted"

# The re-entry flag short-circuits the handler before it calls hoplon-tool.
: > "$B/calls.log"
run_case "$B/bin" "$B/calls.log" "$B/busy.txt" busy knowncmd
[ "$RUN_RC" -eq 127 ] || fail "the re-entry guard should exit 127 (got $RUN_RC)"
assert_file_contains "$B/busy.txt" 'command not found: knowncmd' "the re-entry guard did not short-circuit"
assert_file_lacks "$B/calls.log" 'known' "the re-entry guard still called hoplon-tool"

# End to end: the shipped hook calls the real hoplon-tool, which resolves the
# alias and hands the canonical name to a stubbed toolchain. The stub provides
# the command, and the hook re-execs it. Only apt is stubbed out.
C="$_tmp/c"
mkdir -p "$C/repo/scripts" "$C/bin"
cp "$HOPLON_TEST_REPO/scripts/hoplon-tool" "$C/repo/scripts/hoplon-tool"
chmod +x "$C/repo/scripts/hoplon-tool"
cat > "$C/repo/scripts/toolchain.sh" << 'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --list)
    printf 'core:\n'
    printf 'nmap\n'
    printf 'curl\n'
    printf 'full:\n'
    printf 'netexec\n'
    printf 'sqlmap\n'
    ;;
  --tools=*)
    printf '%s\n' "$*" >> "$HOPLON_TEST_LOG"
    IFS=',' read -r -a names <<< "${1#--tools=}"
    for n in "${names[@]}"; do
      case "$n" in
        netexec) bin=nxc ;;
        *) bin="$n" ;;
      esac
      {
        printf '#!/usr/bin/env bash\n'
        printf 'printf "RUNNING:%%s\\n" "%s"\n' "$bin"
      } > "$HOPLON_TEST_BINDIR/$bin"
      chmod +x "$HOPLON_TEST_BINDIR/$bin"
    done
    ;;
esac
STUB
chmod +x "$C/repo/scripts/toolchain.sh"
: > "$C/args.log"
set +e
env "PATH=$C/bin:$C/repo/scripts:$PATH" \
  HOPLON_TOOL_SUDO=0 \
  HOPLON_TEST_LOG="$C/args.log" \
  HOPLON_TEST_BINDIR="$C/bin" \
  bash -c '. "$1"; nxc' _ "$hook" > "$C/out.txt" 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "the end-to-end on-demand path exited $rc: $(cat "$C/out.txt")"
assert_file_contains "$C/args.log" '--tools=netexec' "the real hoplon-tool did not delegate --tools=netexec"
assert_file_contains "$C/out.txt" 'RUNNING:nxc' "the hook did not re-exec the installed command"

printf 'cloud-init on-demand tool hook ok\n'
