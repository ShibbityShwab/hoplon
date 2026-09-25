#!/usr/bin/env bash
# =============================================================================
# Host credential and agent env scrub.
#
# An isolated HOME hides credential files, but inherited env vars still carry
# access into the child: an SSH agent socket, cloud keys, or a docker endpoint
# that bypasses the sandbox. The launcher must clear that set and repoint the
# runtime dirs into the isolated home, while leaving ordinary vars intact.
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
: > "$HOME/evidence.txt"
for _v in SSH_AUTH_SOCK SSH_AGENT_PID SSH_ASKPASS GIT_ASKPASS GPG_AGENT_INFO \
  KRB5CCNAME KRB5_CONFIG GITHUB_TOKEN GH_TOKEN \
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
  AZURE_CLIENT_SECRET GOOGLE_APPLICATION_CREDENTIALS GCP_PROJECT \
  DOCKER_HOST DOCKER_TLS_VERIFY DOCKER_CERT_PATH DOCKER_CONTEXT; do
  printf '%s=%s\n' "$_v" "$(printenv "$_v" 2> /dev/null || printf UNSET)" >> "$HOME/evidence.txt"
done
{
  printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-UNSET}"
  printf 'TMPDIR=%s\n' "${TMPDIR:-UNSET}"
  printf 'PATH=%s\n' "${PATH:-UNSET}"
  printf 'HOME=%s\n' "${HOME:-UNSET}"
  printf 'LANG=%s\n' "${LANG:-UNSET}"
  printf 'TERM=%s\n' "${TERM:-UNSET}"
  printf 'VENICE_API_KEY=%s\n' "${VENICE_API_KEY:-UNSET}"
} >> "$HOME/evidence.txt"
exit 0
STUB
chmod +x "$repo/bin/opencode"

work="$_tmp/proj"
mkdir -p "$work"
(
  cd "$work" &&
    env \
      SSH_AUTH_SOCK=/tmp/host-agent.sock SSH_AGENT_PID=4242 SSH_ASKPASS=/tmp/askpass \
      GIT_ASKPASS=/tmp/gitaskpass GPG_AGENT_INFO=/tmp/gpg KRB5CCNAME=FILE:/tmp/cc \
      KRB5_CONFIG=/tmp/krb5.conf GITHUB_TOKEN=host-gh GH_TOKEN=host-gh2 \
      AWS_ACCESS_KEY_ID=host-aws-id AWS_SECRET_ACCESS_KEY=host-aws-secret AWS_SESSION_TOKEN=host-aws-session \
      AZURE_CLIENT_SECRET=host-azure GOOGLE_APPLICATION_CREDENTIALS=/tmp/gac.json GCP_PROJECT=host-gcp \
      DOCKER_HOST=tcp://127.0.0.1:2375 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/tmp/certs DOCKER_CONTEXT=hostctx \
      XDG_RUNTIME_DIR=/run/user/1000 TMPDIR=/host/tmp VENICE_API_KEY=scrub-test-key \
      HOPLON_ENABLE_OMO=0 "$repo/hoplon" > "$_tmp/launch.log" 2>&1
)

evidence="$repo/home/evidence.txt"
assert_file_exists "$evidence" "scrub probe did not run"
for _v in SSH_AUTH_SOCK SSH_AGENT_PID SSH_ASKPASS GIT_ASKPASS GPG_AGENT_INFO \
  KRB5CCNAME KRB5_CONFIG GITHUB_TOKEN GH_TOKEN \
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
  AZURE_CLIENT_SECRET GOOGLE_APPLICATION_CREDENTIALS GCP_PROJECT \
  DOCKER_HOST DOCKER_TLS_VERIFY DOCKER_CERT_PATH DOCKER_CONTEXT; do
  assert_file_contains "$evidence" "$_v=UNSET" "$_v leaked into the child"
done

assert_file_contains "$evidence" "XDG_RUNTIME_DIR=$repo/home/.run" "XDG_RUNTIME_DIR was not reset into the isolated home"
assert_file_contains "$evidence" "TMPDIR=$repo/home/tmp" "TMPDIR was not reset into the isolated home"
[ -d "$repo/home/.run" ] || fail "the isolated XDG runtime dir was not created"
[ -d "$repo/home/tmp" ] || fail "the isolated TMPDIR was not created"
assert_file_contains "$evidence" "VENICE_API_KEY=scrub-test-key" "VENICE_API_KEY did not survive the scrub"
assert_file_contains "$evidence" "HOME=$repo/home" "HOME is not the isolated home"
assert_file_contains "$evidence" "LANG=" "LANG was dropped"
assert_file_contains "$evidence" "TERM=" "TERM was dropped"
assert_file_contains "$evidence" "PATH=$repo/bin:" "the bundled bin dir is not first on PATH"

printf 'credential env scrub and runtime dir reset ok\n'
