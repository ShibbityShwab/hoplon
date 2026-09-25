#!/usr/bin/env bash
# =============================================================================
# .env is data, not code.
#
# The launcher previously sourced .env, so a sandboxed agent that appended
# HOPLON_X=$(...) to it got host code execution on the next unsandboxed launch.
# The safe reader must honor NAME=value lines, strip surrounding quotes, and
# never execute the value; a value that looks like a command substitution must
# reach the child as literal text, and the process substitution must not run.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/security_lib.sh
. "$_here/security_lib.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

repo="$_tmp/repo"
hoplon_secure_repo "$repo"
cat > "$repo/bin/opencode" << 'STUB'
#!/usr/bin/env bash
{
  printf 'VENICE_API_KEY=%s\n' "${VENICE_API_KEY:-UNSET}"
  printf 'HOPLON_DEMO=%s\n' "${HOPLON_DEMO:-UNSET}"
  printf 'QUOTED=%s\n' "${QUOTED:-UNSET}"
  printf 'SINGLE=%s\n' "${SINGLE:-UNSET}"
  printf 'BACKTICK=%s\n' "${BACKTICK:-UNSET}"
  printf 'INJECTED=%s\n' "${INJECTED:-UNSET}"
} > "$HOME/evidence.txt" 2>&1
exit 0
STUB
chmod +x "$repo/bin/opencode"

marker="$_tmp/pwned"
cat > "$repo/.env" << ENV
# comment line
VENICE_API_KEY=test-key-123
QUOTED="quoted value"
SINGLE='single value'
HOPLON_DEMO=\$(touch $marker)
BACKTICK=\`touch $marker\`
export INJECTED=evil
ENV

work="$_tmp/proj"
mkdir -p "$work"
(cd "$work" && HOPLON_ENABLE_OMO=0 "$repo/hoplon" > "$_tmp/launch.log" 2>&1)

assert_no_file "$marker" "a command substitution in .env executed on launch"

evidence="$repo/home/evidence.txt"
assert_file_exists "$evidence" "launch probe did not run"
assert_file_contains "$evidence" "VENICE_API_KEY=test-key-123" "VENICE_API_KEY from .env did not reach the child"
assert_file_contains "$evidence" "QUOTED=quoted value" "double quotes were not stripped"
assert_file_contains "$evidence" "SINGLE=single value" "single quotes were not stripped"
assert_file_contains "$evidence" "HOPLON_DEMO=\$(touch $marker)" "the command-substitution value was not kept literal"
assert_file_contains "$evidence" "BACKTICK=\`touch $marker\`" "the backtick value was not kept literal"
assert_file_contains "$evidence" "INJECTED=UNSET" "an export-prefixed line was honored instead of ignored"

printf '.env not executed and values exported verbatim ok\n'
