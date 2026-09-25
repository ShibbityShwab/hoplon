#!/usr/bin/env bash
# =============================================================================
# hoplon-tool resolves tools and delegates installs.
#
# The CLI must read the known set, answer known/suggest from it, map command
# aliases (nxc to netexec), resolve invoked names to the command that actually
# runs after install, and hand the canonical names to toolchain.sh as
# --tools=NAME,... without ever running apt itself. toolchain.sh is stubbed so
# the test stays offline, except for one run of the real toolchain.sh that
# checks HOPLON_TOOL_SUDO=0 refuses to self-elevate.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
mkdir -p "$repo/scripts"
cp "$HOPLON_TEST_REPO/scripts/hoplon-tool" "$repo/scripts/hoplon-tool"
chmod +x "$repo/scripts/hoplon-tool"

# Stub toolchain.sh: --list prints the catalog, anything else records its args.
rec="$_tmp/rec.log"
cat > "$repo/scripts/toolchain.sh" << 'STUB'
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
  *)
    printf '%s\n' "$*" >> "$REC"
    ;;
esac
STUB
chmod +x "$repo/scripts/toolchain.sh"

ht="$repo/scripts/hoplon-tool"
export REC="$rec"
export HOPLON_TOOL_SUDO=0

# list delegates to the toolchain catalog.
list_out="$(bash "$ht" list)"
printf '%s\n' "$list_out" | grep -qx 'netexec' || fail "list did not print netexec: $list_out"
printf '%s\n' "$list_out" | grep -qx 'nmap' || fail "list did not print nmap: $list_out"

# known: a full tool, a core package, and an alias are known; a stranger is not.
bash "$ht" known netexec || fail "known netexec should exit 0"
bash "$ht" known nmap || fail "known nmap should exit 0"
bash "$ht" known nxc || fail "known nxc (alias) should exit 0"
if bash "$ht" known definitely-not-a-tool > /dev/null 2>&1; then
  fail "known definitely-not-a-tool should exit 1"
fi

# suggest: alias maps to the canonical tool, known names echo themselves, an
# unknown name prints nothing.
[ "$(bash "$ht" suggest nxc)" = "netexec" ] || fail "suggest nxc should print netexec"
[ "$(bash "$ht" suggest nc)" = "netcat-openbsd" ] || fail "suggest nc should print netcat-openbsd"
[ "$(bash "$ht" suggest sqlmap)" = "sqlmap" ] || fail "suggest sqlmap should print sqlmap"
[ "$(bash "$ht" suggest ncat)" = "nmap" ] || fail "suggest ncat should print nmap"
[ -z "$(bash "$ht" suggest definitely-not-a-tool)" ] || fail "suggest of an unknown name should print nothing"

# resolve: the invoked name maps to the command that exists after install. A
# plain tool is itself, a tool whose binary differs uses the published name.
[ "$(bash "$ht" resolve nmap)" = "nmap" ] || fail "resolve nmap should print nmap"
[ "$(bash "$ht" resolve sqlmap)" = "sqlmap" ] || fail "resolve sqlmap should print sqlmap"
[ "$(bash "$ht" resolve netexec)" = "nxc" ] || fail "resolve netexec should print nxc"
[ "$(bash "$ht" resolve nxc)" = "nxc" ] || fail "resolve nxc should print nxc"
[ "$(bash "$ht" resolve radare2)" = "rizin" ] || fail "resolve radare2 should print rizin"
[ "$(bash "$ht" resolve theharvester)" = "theHarvester" ] ||
  fail "resolve theharvester should print theHarvester"
[ "$(bash "$ht" resolve ncat)" = "ncat" ] || fail "resolve ncat should print ncat"
[ "$(bash "$ht" resolve definitely-not-a-tool)" = "definitely-not-a-tool" ] ||
  fail "resolve of an unknown name should echo the name"

# install delegates exactly the canonical names as --tools=NAME,...
: > "$rec"
bash "$ht" install sqlmap netexec
assert_file_contains "$rec" '--tools=sqlmap,netexec' "install did not delegate the tool list"

# an alias installs its canonical tool.
: > "$rec"
bash "$ht" install nxc
assert_file_contains "$rec" '--tools=netexec' "install nxc did not resolve to netexec"

# duplicate aliases collapse to one canonical name.
: > "$rec"
bash "$ht" install nxc netexec
assert_file_contains "$rec" '--tools=netexec' "duplicate aliases were not collapsed"
assert_file_lacks "$rec" 'netexec,netexec' "duplicate aliases were sent twice"

# base and all select the preloaded sets.
: > "$rec"
bash "$ht" install base
assert_file_contains "$rec" '--core' "install base did not run the core set"
: > "$rec"
bash "$ht" install all
assert_file_contains "$rec" '--full' "install all did not run the full set"

# an unknown tool is a usage error and never reaches toolchain.sh.
: > "$rec"
if bash "$ht" install definitely-not-a-tool > /dev/null 2>&1; then
  fail "install of an unknown tool should exit non-zero"
fi
assert_file_lacks "$rec" 'definitely-not-a-tool' "an unknown tool reached toolchain.sh"

# status reports every known tool with a present or missing marker, without
# depending on what happens to be installed on the test host.
status_out="$(bash "$ht" status)"
printf '%s\n' "$status_out" | grep -qE '^(present|missing) +nmap$' ||
  fail "status did not report nmap: $status_out"
printf '%s\n' "$status_out" | grep -qE '^(present|missing) +sqlmap$' ||
  fail "status did not report sqlmap: $status_out"
printf '%s\n' "$status_out" | grep -q 'of 4 known tools present' ||
  fail "status did not summarize the catalog: $status_out"

# HOPLON_TOOL_SUDO=0 must stop the real toolchain.sh from re-elevating with
# sudo. Only meaningful as a non-root user, which is how CI runs.
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$_tmp/sudobin"
  cat > "$_tmp/sudobin/sudo" << 'SUDO'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "${HOPLON_TEST_SUDO_LOG:?}"
exit 0
SUDO
  chmod +x "$_tmp/sudobin/sudo"
  : > "$_tmp/sudo.log"
  set +e
  env PATH="$_tmp/sudobin:$PATH" HOPLON_TOOL_SUDO=0 HOPLON_TEST_SUDO_LOG="$_tmp/sudo.log" \
    bash "$HOPLON_TEST_REPO/scripts/toolchain.sh" --tools=nmap > "$_tmp/toolchain.log" 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "toolchain.sh should refuse to run unprivileged with HOPLON_TOOL_SUDO=0"
  assert_file_lacks "$_tmp/sudo.log" 'sudo' "HOPLON_TOOL_SUDO=0 still invoked sudo"
  assert_file_contains "$_tmp/toolchain.log" 'refusing to self-elevate' \
    "toolchain.sh did not explain the refusal"
fi

printf 'hoplon-tool resolution and delegation ok\n'
