#!/usr/bin/env bash
# Guard: a tracked project-authored file must not contain U+2013 (en dash) or
# U+2014 (em dash). The vendored Venice skills are excluded because upstream
# uses those characters legitimately; they are marked linguist-vendored in
# .gitattributes.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)"
cd "$repo" || exit 1

if ! command -v git > /dev/null 2>&1; then
  printf 'SKIP: git not available\n' >&2
  exit 0
fi

# Raw UTF-8 byte sequences for U+2013 and U+2014, so no literal dash appears
# in this file. C locale makes grep match byte for byte on GNU and BSD alike.
en_dash=$'\xe2\x80\x93'
em_dash=$'\xe2\x80\x94'
fail=0

while IFS= read -r file; do
  case "$file" in
    skills/venice-*) continue ;;
  esac
  [ -f "$file" ] || continue
  # Skip binary files: grep -I reports them, grep -q . finds no matching line.
  if ! grep -Iq . "$file" 2> /dev/null; then
    continue
  fi
  if matches="$(LC_ALL=C grep -nE -- "$en_dash|$em_dash" "$file" 2> /dev/null)"; then
    printf 'dash found in %s:\n%s\n' "$file" "$matches" >&2
    fail=1
  fi
done < <(git ls-files)

if [ "$fail" -ne 0 ]; then
  printf 'FAIL: U+2013 or U+2014 present in a tracked project file\n' >&2
  exit 1
fi

printf 'OK: no U+2013 or U+2014 in tracked project files\n'
