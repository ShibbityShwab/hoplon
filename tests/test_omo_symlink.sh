#!/usr/bin/env bash
# =============================================================================
# OMO takeover must not clobber a symlinked host config.
#
# The takeover writes with a temp-file plus rename, which would replace a
# symlink inode and sever it from its target; GNU `stat -c %a` without -L would
# also read the link's synthetic 0777. When the conflict is a symlink the
# launcher must skip the takeover, leave the link and its target untouched, and
# create no backup.
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

work="$_tmp/work"
mkdir -p "$work/proj/.omo"
target="$work/proj/real-omo.jsonc"
link="$work/proj/.omo/omo.jsonc"
printf '%s\n' '{ "host": "symlink-target" }' > "$target"
chmod 640 "$target"
ln -s "$target" "$link"

(cd "$work/proj" && "$repo/hoplon" > "$_tmp/launch.log" 2>&1)

[ -L "$link" ] || fail "the host OMO symlink was replaced by a regular file"
assert_file_contains "$target" '"host": "symlink-target"' "the symlink target was overwritten"
assert_file_contains "$_tmp/launch.log" "is a symlink; skipping the takeover" "the launcher did not report skipping the symlink"
assert_no_file "$link.hoplon-hostbak" "a backup was created for a symlinked conflict"
[ "$(stat -c '%a' "$target")" = "640" ] || fail "the target file mode changed"

printf 'OMO takeover skips symlinked host config ok\n'
