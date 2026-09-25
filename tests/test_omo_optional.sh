#!/usr/bin/env bash
# =============================================================================
# HOPLON_ENABLE_OMO=0 runs pure OpenCode: the seeded opencode.jsonc drops the
# oh-my-openagent plugin line, no .omo/omo.jsonc is seeded, and the host OMO
# takeover is skipped entirely.
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
printf '%s\n' '// real host OMO config' '{ "host": true }' > "$host"

# One full launch cycle with OMO disabled, from a directory whose host .omo
# would otherwise trigger a takeover.
(cd "$work/proj" && HOPLON_ENABLE_OMO=0 "$repo/hoplon" > /dev/null 2>&1)

# The seeded config must lose the OMO plugin but keep MIT magic-context.
seeded="$repo/home/.config/opencode/opencode.jsonc"
assert_file_exists "$seeded" "seeded opencode.jsonc was not written"
assert_file_lacks "$seeded" "oh-my-openagent@" "OMO plugin still present in seeded config"
assert_file_contains "$seeded" "@cortexkit/opencode-magic-context" "magic-context plugin was dropped"

# default_agent must be repointed: sisyphus is registered only by OMO, so
# leaving it would make OpenCode fail to start with HOPLON_ENABLE_OMO=0.
assert_file_lacks "$seeded" '"default_agent": "sisyphus"' "default_agent still targets the OMO-only sisyphus"
assert_file_contains "$seeded" '"default_agent": "build"' "default_agent was not repointed to a built-in agent"

# No OMO user config may be seeded.
assert_no_file "$repo/home/.omo/omo.jsonc" "OMO config was seeded despite HOPLON_ENABLE_OMO=0"

# The takeover must be skipped: host config untouched, no backup created.
assert_file_contains "$host" '"host": true' "host OMO config was modified"
assert_file_lacks "$host" "HOPLON - Oh My OpenAgent" "host OMO config was taken over"
assert_no_file "$bak" "backup created despite HOPLON_ENABLE_OMO=0"

printf 'OMO optional mode ok\n'
