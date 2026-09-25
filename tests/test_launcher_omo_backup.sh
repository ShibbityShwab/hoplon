#!/usr/bin/env bash
# =============================================================================
# Launcher OMO takeover.
#
# Scenario A: an earlier session left a stale backup behind, the host then
# edited its OMO config, and a new launch cycle runs. The host edit has to
# survive, and the backup has to be gone once the session exits.
#
# Scenario B: a previous run crashed after taking the host file over, leaving
# Hoplon's marker in the conflict file and the real host content only in the
# backup. The crash self-heal path has to put the host content back.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
hoplon_make_repo "$repo"

work="$_tmp/work"
mkdir -p "$work/proj/.omo"
host="$work/proj/.omo/omo.jsonc"
bak="$host.hoplon-hostbak"

# A stale backup from an earlier session holds the host's *old* content.
printf '%s\n' '// stale host config from an earlier run' '{ "host": "old" }' > "$bak"
# The host has since edited its file.
printf '%s\n' '// host config edited after the stale backup was written' '{ "host": "new" }' > "$host"

# One full launch cycle from the conflicting project directory.
(cd "$work/proj" && HOPLON_OMO_TAKEOVER=1 "$repo/hoplon" > /dev/null 2>&1)

# The host edit must survive the cycle.
assert_file_contains "$host" '"host": "new"' "host edit was lost after the launch cycle"
assert_file_lacks "$host" "HOPLON - Oh My OpenAgent" "host config still holds Hoplon content after exit"
# The backup must be cleaned up on a clean exit.
assert_no_file "$bak" "backup was left behind after a clean exit"

# --- Scenario B: crash self-heal restores the host file ----------------------
work_b="$_tmp/work-b"
mkdir -p "$work_b/proj/.omo"
host_b="$work_b/proj/.omo/omo.jsonc"
bak_b="$host_b.hoplon-hostbak"

# The conflict still holds the Hoplon config a dead run left behind.
cp "$repo/config/omo.jsonc" "$host_b"
assert_file_contains "$host_b" "HOPLON - Oh My OpenAgent" "test setup: conflict must hold the Hoplon marker"
# Only the backup has the real host content.
printf '%s\n' '// real host config recovered from the backup' '{ "host": "recovered" }' > "$bak_b"

(cd "$work_b/proj" && HOPLON_OMO_TAKEOVER=1 "$repo/hoplon" > /dev/null 2>&1)

assert_file_contains "$host_b" '"host": "recovered"' "crash self-heal did not restore the host content"
assert_file_lacks "$host_b" "HOPLON - Oh My OpenAgent" "host config still holds Hoplon content after self-heal"
assert_no_file "$bak_b" "backup was left behind after the self-heal cycle"

printf 'launcher OMO backup and self-heal cycles ok\n'
