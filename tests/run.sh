#!/usr/bin/env bash
# =============================================================================
# Hoplon test runner. Auto-discovers tests/test_*.sh, prints one PASS/FAIL line
# per file, and exits non-zero if any test fails.
# =============================================================================
set -u

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"

_failures=0
_total=0
for _t in "$_here"/test_*.sh; do
  [ -f "$_t" ] || continue
  _total=$((_total + 1))
  _name="$(basename "$_t")"
  if bash "$_t"; then
    printf 'PASS %s\n' "$_name"
  else
    printf 'FAIL %s\n' "$_name"
    _failures=$((_failures + 1))
  fi
done

if [ "$_total" -eq 0 ]; then
  printf 'no tests found in %s\n' "$_here" >&2
  exit 1
fi

printf '\n%s test(s) run, %s failed\n' "$_total" "$_failures"
[ "$_failures" -eq 0 ]
