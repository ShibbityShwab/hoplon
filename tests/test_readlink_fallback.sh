#!/usr/bin/env bash
# =============================================================================
# readlink fallback on BSD/macOS.
#
# GNU `readlink -f` is missing on older BSD/macOS, so the launcher walks the
# symlink chain with plain `readlink`. The old fallback passed `--`, which BSD
# readlink rejects as `illegal option -- --`, aborting under set -e. Simulate a
# readlink that rejects both `-f` and `--` and invoke the launcher through a
# symlink: it must still resolve its repo and exit 0.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/security_lib.sh
. "$_here/security_lib.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
hoplon_secure_repo "$repo"
printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/bin/opencode"
chmod +x "$repo/bin/opencode"

mkdir -p "$_tmp/fakebin" "$_tmp/linkdir"
cat > "$_tmp/fakebin/readlink" << 'FAKE'
#!/usr/bin/env bash
# Emulate an older BSD readlink: no -f, no --.
case "${1:-}" in
  -f | --)
    printf 'readlink: illegal option -- %s\n' "$1" >&2
    exit 1
    ;;
  -*) exit 1 ;;
esac
exec /usr/bin/readlink "$@"
FAKE
chmod +x "$_tmp/fakebin/readlink"

ln -sf "$repo/hoplon" "$_tmp/linkdir/hoplon"

set +e
out="$(PATH="$_tmp/fakebin:$PATH" "$_tmp/linkdir/hoplon" version 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] || {
  printf 'output:\n%s\n' "$out" >&2
  fail "launcher aborted when readlink rejected -f and -- (rc=$rc)"
}
printf '%s\n' "$out" | grep -q '^hoplon ' || fail "launcher did not resolve its repo through the symlink: $out"

printf 'readlink fallback through a symlink ok\n'
