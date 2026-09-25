#!/usr/bin/env bash
# =============================================================================
# toolchain.sh install_go_tarball is crash safe and integrity checked.
#
# The real function is extracted from scripts/toolchain.sh and run against a
# temp install root with a stubbed download. A checksum mismatch or a bad
# archive must leave the existing Go tree untouched, and a good archive must
# replace it. The bash 4 guard must sit before the first associative array.
# =============================================================================
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)"
# shellcheck source=tests/lib.sh
. "$_here/lib.sh"

if ! command -v tar > /dev/null 2>&1 || ! command -v sha256sum > /dev/null 2>&1; then
  printf 'SKIP: tar or sha256sum not available\n' >&2
  exit 0
fi

toolchain="$HOPLON_TEST_REPO/scripts/toolchain.sh"

_tmp="$(mktemp -d)"
trap 'rm -rf "$_tmp"' EXIT

# --- static guards ----------------------------------------------------------
bash -n "$toolchain" || fail "toolchain.sh does not parse"
guard_line="$(grep -n 'bash_major" -lt 4' "$toolchain" | head -n 1 | cut -d: -f1 || true)"
assoc_line="$(grep -nE '^declare -A ' "$toolchain" | head -n 1 | cut -d: -f1 || true)"
[ -n "$guard_line" ] || fail "toolchain.sh has no bash 4 guard"
[ -n "$assoc_line" ] || fail "toolchain.sh no longer uses associative arrays"
[ "$guard_line" -lt "$assoc_line" ] ||
  fail "the bash 4 guard (line $guard_line) must precede declare -A (line $assoc_line)"
assert_file_lacks "$toolchain" 'rm -rf /usr/local/go' "install_go_tarball still clobbers the old Go tree first"
assert_file_contains "$toolchain" 'tar -C "$extract_dir"' "install_go_tarball does not extract to a temp dir"
assert_file_contains "$toolchain" 'mode=json' "install_go_tarball does not fetch go.dev's checksum index"

# --- build a fake Go archive and a stubbed curl -----------------------------
payload="$_tmp/payload"
mkdir -p "$payload/go/bin"
printf '#!/bin/sh\nprintf "go version go1.24.0 fake\\n"\n' > "$payload/go/bin/go"
chmod +x "$payload/go/bin/go"
printf '#!/bin/sh\nprintf "gofmt fake\\n"\n' > "$payload/go/bin/gofmt"
chmod +x "$payload/go/bin/gofmt"
fake_tar="$_tmp/fake-go.tar.gz"
tar -C "$payload" -czf "$fake_tar" go

fakebin="$_tmp/fakebin"
state="$_tmp/state"
mkdir -p "$fakebin" "$state"
cat > "$fakebin/curl" << 'FAKECURL'
#!/usr/bin/env bash
dest=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      dest="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
[ -n "$dest" ] || exit 1
case "$url" in
  *mode=json*)
    name="$(cat "${FAKE_STATE:?}/tarball_name" 2> /dev/null || basename "$FAKE_TAR")"
    if [ "${FAKE_SHA_MODE:-good}" = "bad" ]; then
      hash="$(printf '%064d' 0)"
    else
      src="$(cat "${FAKE_STATE:?}/tarball_path" 2> /dev/null || printf '%s' "$FAKE_TAR")"
      hash="$(sha256sum "$src" | awk '{print $1}')"
    fi
    printf '[\n {\n  "version": "go1.24.0",\n  "files": [\n   {\n    "filename": "%s",\n    "os": "linux",\n    "arch": "amd64",\n    "version": "go1.24.0",\n    "sha256": "%s",\n    "size": 1,\n    "kind": "archive"\n   }\n  ]\n }\n]\n' \
      "$name" "$hash" > "$dest"
    ;;
  *)
    printf '%s\n' "$dest" > "${FAKE_STATE:?}/tarball_path"
    basename "$dest" > "${FAKE_STATE:?}/tarball_name"
    if [ "${FAKE_TARBALL_MODE:-good}" = "corrupt" ]; then
      printf 'not a tarball\n' > "$dest"
    else
      cp "$FAKE_TAR" "$dest"
    fi
    ;;
esac
FAKECURL
chmod +x "$fakebin/curl"

# --- extract the real functions into a runnable harness ---------------------
harness="$_tmp/harness.sh"
cat > "$harness" << 'PRE'
#!/usr/bin/env bash
set -euo pipefail
run_logged() { "$@"; }
warn() { printf 'toolchain: %s\n' "$*" >&2; }
apt_update_once() { return 0; }
PRE
awk '
  /^fetch_url\(\) \{/ { p = 1 }
  /^install_go_tarball\(\) \{/ { q = 1 }
  p { print }
  p && /^\}$/ { p = 0 }
  q { print }
  q && /^\}$/ { q = 0 }
' "$toolchain" >> "$harness"
cat >> "$harness" << 'POST'
rc=0
install_go_tarball || rc=$?
printf 'RC=%s\n' "$rc"
exit "$rc"
POST
bash -n "$harness" || fail "the extracted install_go_tarball does not parse"

RUN_RC=0
run_install() { # root sha_mode tarball_mode
  local root="$1" sha="$2" mode="$3"
  : > "$state/tarball_path"
  set +e
  env PATH="$fakebin:$PATH" \
    HOPLON_GO_ROOT="$root" \
    HOPLON_GO_BIN_DIR="$root/bin" \
    FAKE_TAR="$fake_tar" \
    FAKE_STATE="$state" \
    FAKE_SHA_MODE="$sha" \
    FAKE_TARBALL_MODE="$mode" \
    bash "$harness" > "$_tmp/run.log" 2>&1
  RUN_RC=$?
  set -e
}

# A good archive replaces an existing Go tree and links the binaries.
root="$_tmp/root-good"
mkdir -p "$root/go/bin"
printf 'OLD\n' > "$root/go/bin/go"
run_install "$root" good good
[ "$RUN_RC" -eq 0 ] || fail "a good archive failed (rc=$RUN_RC): $(cat "$_tmp/run.log")"
assert_file_contains "$root/go/bin/go" 'go version go1.24.0 fake' "the new Go tree was not installed"
[ -L "$root/bin/go" ] || fail "go was not linked into the bin dir"
[ -x "$root/go/bin/gofmt" ] || fail "gofmt was not installed"

# A checksum mismatch must fail closed and leave the old tree intact.
root="$_tmp/root-badsha"
mkdir -p "$root/go/bin"
printf 'OLD\n' > "$root/go/bin/go"
run_install "$root" bad good
[ "$RUN_RC" -ne 0 ] || fail "a checksum mismatch was accepted (rc=$RUN_RC)"
assert_file_contains "$_tmp/run.log" 'checksum mismatch' "a checksum mismatch was not reported"
assert_file_contains "$root/go/bin/go" 'OLD' "a checksum mismatch overwrote the existing Go tree"

# A bad archive that passes checksum must fail at extract and leave the old
# tree intact: the new tree only moves into place after a good extract.
root="$_tmp/root-corrupt"
mkdir -p "$root/go/bin"
printf 'OLD\n' > "$root/go/bin/go"
run_install "$root" good corrupt
[ "$RUN_RC" -ne 0 ] || fail "a corrupt archive was accepted (rc=$RUN_RC)"
assert_file_contains "$_tmp/run.log" 'could not extract' "a corrupt archive was not reported"
assert_file_contains "$root/go/bin/go" 'OLD' "a corrupt archive overwrote the existing Go tree"
[ ! -e "$root/go/bin/gofmt" ] || fail "a corrupt archive still placed new files in the Go tree"

printf 'toolchain.sh Go tarball safety and bash 4 guard ok\n'
