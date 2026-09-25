#!/usr/bin/env bash
# =============================================================================
# scripts/install.sh reads .env safely too.
#
# The installer also sourced .env to pick up HOPLON_OPENCODE_VERSION and the
# pinned digest. Drive it with a fake curl that records its arguments and fails,
# so the run stops at the download step: the injected command must not execute,
# and the version from .env must still be the one requested.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/security_lib.sh
. "$_here/security_lib.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
mkdir -p "$repo/scripts" "$repo/bin" "$repo/home"
cp "$HOPLON_TEST_REPO/scripts/install.sh" "$repo/scripts/install.sh"
chmod +x "$repo/scripts/install.sh"

marker="$_tmp/pwned"
cat > "$repo/.env" << ENV
HOPLON_OPENCODE_VERSION=9.9.9
HOPLON_DEMO=\$(touch $marker)
ENV

mkdir -p "$_tmp/fakebin"
cat > "$_tmp/fakebin/curl" << 'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_CURL_LOG"
exit 1
FAKE
chmod +x "$_tmp/fakebin/curl"

set +e
(cd "$repo" && PATH="$_tmp/fakebin:$PATH" FAKE_CURL_LOG="$_tmp/curl.log" bash "$repo/scripts/install.sh" > "$_tmp/install.log" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "installer should have failed at the fake download"

assert_no_file "$marker" "a command substitution in .env executed during install"
assert_file_exists "$_tmp/curl.log" "the fake curl was never called"
assert_file_contains "$_tmp/curl.log" "v9.9.9" "HOPLON_OPENCODE_VERSION from .env did not reach the download URL"
assert_file_contains "$_tmp/install.log" "download failed" "installer did not report the expected download failure"

printf 'scripts/install.sh .env safety ok\n'
