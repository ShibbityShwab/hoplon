#!/usr/bin/env bash
# =============================================================================
# Sandbox hardening regression.
#
# HOPLON_SANDBOX=1 must:
#   * leave /run/docker.sock, /run/dbus/system_bus_socket, and /run/user absent,
#     because the host /run exposes a container escape to host root;
#   * mount the repo read-only and only the isolated state home read-write, so a
#     sandboxed agent cannot poison .env or config for the next unsandboxed run;
#   * keep DNS working, because /etc/resolv.conf on systemd-resolved hosts is a
#     symlink into /run.
#
# The probe stub is the launcher's bin/opencode; it records what it can reach
# and writes the transcript into its (writable) isolated HOME.
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
cat > "$repo/bin/opencode" << 'STUB'
#!/usr/bin/env bash
{
  if [ -S /run/docker.sock ]; then echo "docker-sock=PRESENT"; else echo "docker-sock=ABSENT"; fi
  if [ -S /run/dbus/system_bus_socket ]; then echo "dbus-sock=PRESENT"; else echo "dbus-sock=ABSENT"; fi
  if [ -e /run/user ]; then echo "run-user=PRESENT"; else echo "run-user=ABSENT"; fi
  if touch "$HOPLON_HOME/config/PWNED_RO" 2> /dev/null; then echo "repo-config-write=SUCCESS"; else echo "repo-config-write=DENIED"; fi
  if printf 'x\n' >> "$HOPLON_HOME/.env" 2> /dev/null; then echo "repo-env-append=SUCCESS"; else echo "repo-env-append=DENIED"; fi
  if touch "$HOME/PWNED_RW" 2> /dev/null; then echo "home-write=SUCCESS"; else echo "home-write=DENIED"; fi
  printf 'dns-http=%s\n' "$(curl -s --max-time 10 https://api.venice.ai/api/v1/models -o /dev/null -w '%{http_code}' 2> /dev/null || echo ERR)"
} > "$HOME/evidence.txt" 2>&1
exit 0
STUB
chmod +x "$repo/bin/opencode"

work="$_tmp/proj"
hosthome="$_tmp/hosthome"
mkdir -p "$work" "$hosthome"

(
  cd "$work" &&
    HOPLON_SANDBOX=1 HOPLON_ENABLE_OMO=0 HOPLON_HOST_HOME="$hosthome" \
      "$repo/hoplon" > "$_tmp/launch.log" 2>&1
)

evidence="$repo/home/evidence.txt"
assert_file_exists "$evidence" "sandbox probe did not run"

assert_file_contains "$evidence" "docker-sock=ABSENT" "docker.sock is reachable inside the sandbox"
assert_file_contains "$evidence" "dbus-sock=ABSENT" "the dbus system bus socket is reachable inside the sandbox"
assert_file_contains "$evidence" "run-user=ABSENT" "/run/user is reachable inside the sandbox"
assert_file_contains "$evidence" "repo-config-write=DENIED" "the repo config directory is writable inside the sandbox"
assert_file_contains "$evidence" "repo-env-append=DENIED" "the repo .env is writable inside the sandbox"
assert_file_contains "$evidence" "home-write=SUCCESS" "the isolated home is not writable inside the sandbox"

# DNS: only meaningful when the host itself can reach the endpoint. When it can,
# require the sandbox to match; otherwise record a skip rather than a false fail.
if curl -fsS --max-time 8 https://api.venice.ai/api/v1/models > /dev/null 2>&1; then
  assert_file_contains "$evidence" "dns-http=200" "DNS broke inside the sandbox (expected HTTP 200 from the Venice API)"
  printf 'ok: DNS resolves inside the sandbox (HTTP 200)\n'
else
  printf 'SKIP: host has no network; DNS-through-sandbox not asserted\n'
fi

printf 'sandbox docker.sock, read-only repo, and DNS ok\n'
