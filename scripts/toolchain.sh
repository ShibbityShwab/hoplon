#!/usr/bin/env bash
# =============================================================================
# Hoplon red-team toolchain installer.
#
# One idempotent installer that provisions the red-team toolbox on Debian or
# Ubuntu. It is shared by the Docker image (a Dockerfile RUNs it) and the QEMU
# VM cloud-init, so it must be safe to re-run and must never fail the whole run
# when a single optional tool is unavailable.
#
# Usage:
#   scripts/toolchain.sh [--core | --full | --tools=a,b,c | --list]
#
#   --core         install the modest base set (default)
#   --full         install the core set plus the full red-team toolset
#   --tools=a,b,c  install only the named tools (core package names or full
#                  tool names; see --list)
#   --list         print every known tool name and exit
#   -h, --help     show this help
#
# Flags may be combined; the selection is the union. With no flag the core set
# is installed. Each full-set tool is best-effort: a failure is reported with a
# reason and never aborts the run. Core packages are treated as required and a
# missing one makes the script exit non-zero.
#
# Environment:
#   HOPLON_GO_VERSION      Go toolchain to fetch when apt Go is too old
#                          (default 1.24.0)
#   HOPLON_MIN_GO_MINOR    minimum acceptable Go 1.x minor (default 21)
# =============================================================================
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
ORIG_ARGS=("$@")

# --- result tracking --------------------------------------------------------
declare -a RESULT_ORDER=()
declare -A RESULT_STATUS=()
declare -A RESULT_DETAIL=()

# --- core apt packages: "package:probe-binary" (empty probe means dpkg check) -
CORE_PKGS=(
  nmap:nmap
  netcat-openbsd:nc
  dnsutils:dig
  whois:whois
  curl:curl
  wget:wget
  git:git
  jq:jq
  ripgrep:rg
  python3:python3
  python3-venv:
  python3-pip:pip3
  pipx:pipx
  build-essential:gcc
  ca-certificates:
  tmux:tmux
  less:less
  file:file
  openssl:openssl
  socat:socat
  tcpdump:tcpdump
  iproute2:ip
  iputils-ping:ping
  procps:ps
  unzip:unzip
  xz-utils:xz
  zip:zip
)

# --- full-set tool names (order matters: golang first for `go install`) ------
FULL_TOOLS=(
  golang
  nuclei
  subfinder
  httpx
  ffuf
  gobuster
  amass
  kerbrute
  sqlmap
  impacket
  netexec
  bloodhound
  hydra
  john
  nikto
  whatweb
  masscan
  aircrack-ng
  dnsrecon
  smbclient
  ldap-utils
  binutils
  gdb
  strace
  ltrace
  rizin
  seclists
  rockyou
)

# --- selection state --------------------------------------------------------
SELECT_CORE=0
SELECT_FULL=0
LIST_ONLY=0
SELECTED_TOOLS=()
APT_UPDATED=0
ATTEMPT_LOG=""

# --- small output helpers ---------------------------------------------------
section() { printf '\n== %s ==\n' "$1"; }
warn() { printf 'toolchain: %s\n' "$*" >&2; }
usage() {
  cat << 'EOF'
usage: toolchain.sh [--core | --full | --tools=a,b,c | --list]

  --core         install the modest base set (default)
  --full         install the core set plus the full red-team toolset
  --tools=a,b,c  install only the named tools (core package names or full
                 tool names; see --list)
  --list         print every known tool name and exit
  -h, --help     show this help

Flags may be combined; the selection is the union. With no flag the core set
is installed. Each full-set tool is best-effort: a failure is reported with a
reason and never aborts the run.
EOF
}

record() { # name status detail
  local name="$1" status="$2" detail="${3:-}"
  if [ -z "${RESULT_STATUS[$name]+x}" ]; then
    RESULT_ORDER+=("$name")
  fi
  RESULT_STATUS[$name]="$status"
  RESULT_DETAIL[$name]="$detail"
  case "$status" in
    OK) printf '  [PASS] %s%s\n' "$name" "${detail:+ ($detail)}" ;;
    MISS) printf '  [FAIL] %s%s\n' "$name" "${detail:+ ($detail)}" ;;
    *) printf '  [SKIP] %s%s\n' "$name" "${detail:+ ($detail)}" ;;
  esac
}

print_summary() {
  local name ok=0 miss=0
  printf '\n== toolchain summary ==\n'
  printf '%-16s %-6s %s\n' TOOL STATUS DETAIL
  for name in "${RESULT_ORDER[@]}"; do
    printf '%-16s %-6s %s\n' "$name" "${RESULT_STATUS[$name]}" "${RESULT_DETAIL[$name]}"
    case "${RESULT_STATUS[$name]}" in
      OK) ok=$((ok + 1)) ;;
      MISS) miss=$((miss + 1)) ;;
    esac
  done
  printf '\n%s passed, %s missing\n' "$ok" "$miss"
}

print_list() {
  local entry name
  printf 'core:\n'
  for entry in "${CORE_PKGS[@]}"; do
    printf '%s\n' "${entry%%:*}"
  done
  printf 'full:\n'
  for name in "${FULL_TOOLS[@]}"; do
    printf '%s\n' "$name"
  done
}

# --- membership helpers -----------------------------------------------------
is_core_pkg() {
  local entry
  for entry in "${CORE_PKGS[@]}"; do
    case "$entry" in
      "$1":*) return 0 ;;
    esac
  done
  return 1
}

core_bin_for() { # pkg -> probe binary or empty
  local entry
  for entry in "${CORE_PKGS[@]}"; do
    case "$entry" in
      "$1":*)
        printf '%s' "${entry#*:}"
        return 0
        ;;
    esac
  done
  printf ''
}

is_full_tool() {
  local name
  for name in "${FULL_TOOLS[@]}"; do
    if [ "$name" = "$1" ]; then return 0; fi
  done
  return 1
}

core_pkg_present() { # pkg
  local pkg="$1" bin
  bin="$(core_bin_for "$pkg")"
  if [ -n "$bin" ]; then
    command -v "$bin" > /dev/null 2>&1
    return
  fi
  dpkg -s "$pkg" > /dev/null 2>&1
}

tool_probes_present() { # probe...
  local probe
  for probe in "$@"; do
    if command -v "$probe" > /dev/null 2>&1; then return 0; fi
  done
  return 1
}

# --- apt plumbing -----------------------------------------------------------
run_logged() {
  : > "$ATTEMPT_LOG"
  if "$@" >> "$ATTEMPT_LOG" 2>&1; then
    return 0
  fi
  return 1
}

attempt_reason() {
  local line=""
  line="$({ grep -v '^[[:space:]]*$' "$ATTEMPT_LOG" 2> /dev/null || true; } | tail -n 1)"
  line="${line#E: }"
  line="${line#"${line%%[![:space:]]*}"}"
  printf '%s' "$line"
}

apt_update_once() {
  if [ "$APT_UPDATED" = 1 ]; then return 0; fi
  APT_UPDATED=1
  run_logged apt-get update
}

ensure_base() {
  if ! dpkg -s ca-certificates > /dev/null 2>&1; then
    apt_update_once || true
    run_logged apt-get install -y --no-install-recommends ca-certificates || true
  fi
}

# --- core set ---------------------------------------------------------------
install_core() {
  section "core packages"
  local entry pkg
  local -a missing=()
  for entry in "${CORE_PKGS[@]}"; do
    pkg="${entry%%:*}"
    core_pkg_present "$pkg" || missing+=("$pkg")
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    apt_update_once || warn "apt-get update failed; installs may fail"
    if ! run_logged apt-get install -y --no-install-recommends "${missing[@]}"; then
      warn "group install failed; retrying packages individually"
      local one
      for one in "${missing[@]}"; do
        if ! core_pkg_present "$one"; then
          run_logged apt-get install -y --no-install-recommends "$one" || true
        fi
      done
    fi
  else
    printf '  all core packages already present\n'
  fi

  for entry in "${CORE_PKGS[@]}"; do
    pkg="${entry%%:*}"
    if core_pkg_present "$pkg"; then
      record "$pkg" OK "present"
    else
      record "$pkg" MISS "apt install failed"
    fi
  done
}

install_core_pkg() { # pkg
  local pkg="$1"
  if core_pkg_present "$pkg"; then
    record "$pkg" OK "already present"
    return 0
  fi
  apt_update_once || true
  if run_logged apt-get install -y --no-install-recommends "$pkg"; then
    if core_pkg_present "$pkg"; then
      record "$pkg" OK "installed"
    else
      record "$pkg" MISS "installed but not detected"
    fi
  else
    record "$pkg" MISS "$(attempt_reason)"
  fi
}

# --- Go toolchain -----------------------------------------------------------
go_bin_version() {
  if command -v go > /dev/null 2>&1; then
    go version 2> /dev/null || true
  fi
}

go_version_ok() { # raw "go version go1.24.0 linux/amd64"
  local raw="$1" rest minor
  case "$raw" in
    *"go1."*) rest="${raw##*go1.}" ;;
    *) return 1 ;;
  esac
  minor="${rest%%.*}"
  minor="${minor%% *}"
  case "$minor" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$minor" -ge "${HOPLON_MIN_GO_MINOR:-21}" ]
}

install_go_tarball() {
  local ver="${HOPLON_GO_VERSION:-1.24.0}" arch tarball url tmp
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    armv7l | armv6l) arch=armv6l ;;
    i386 | i686) arch=386 ;;
    *) return 1 ;;
  esac
  tarball="go${ver}.linux-${arch}.tar.gz"
  url="https://go.dev/dl/${tarball}"
  tmp="$(mktemp -d)"

  if ! command -v curl > /dev/null 2>&1 && ! command -v wget > /dev/null 2>&1; then
    apt_update_once || true
    run_logged apt-get install -y --no-install-recommends curl ca-certificates || true
  fi
  if command -v curl > /dev/null 2>&1; then
    run_logged curl -fsSL "$url" -o "$tmp/$tarball" || {
      rm -rf "$tmp"
      return 1
    }
  elif command -v wget > /dev/null 2>&1; then
    run_logged wget -q "$url" -O "$tmp/$tarball" || {
      rm -rf "$tmp"
      return 1
    }
  else
    rm -rf "$tmp"
    return 1
  fi

  rm -rf /usr/local/go
  if ! run_logged tar -C /usr/local -xzf "$tmp/$tarball"; then
    rm -rf "$tmp"
    return 1
  fi
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -rf "$tmp"
  export PATH="/usr/local/bin:${PATH}"
  return 0
}

ensure_go() {
  local gv
  export PATH="/usr/local/bin:${PATH}"
  gv="$(go_bin_version)"
  if [ -n "$gv" ] && go_version_ok "$gv"; then return 0; fi

  apt_update_once || true
  run_logged apt-get install -y --no-install-recommends golang-go || true
  gv="$(go_bin_version)"
  if [ -n "$gv" ] && go_version_ok "$gv"; then return 0; fi

  if install_go_tarball; then
    gv="$(go_bin_version)"
    if [ -n "$gv" ] && go_version_ok "$gv"; then return 0; fi
  fi
  return 1
}

go_tool() { # name module
  local name="$1" module="$2" detail
  if command -v "$name" > /dev/null 2>&1; then
    record "$name" OK "already present"
    return 0
  fi
  if ! ensure_go; then
    record "$name" MISS "no usable Go toolchain"
    return 0
  fi
  if run_logged env GOBIN=/usr/local/bin go install "$module"; then
    if command -v "$name" > /dev/null 2>&1; then
      record "$name" OK "installed"
    else
      record "$name" MISS "built but binary not on PATH"
    fi
  else
    detail="$(attempt_reason)"
    record "$name" MISS "${detail:-go install failed}"
  fi
}

install_golang() {
  local gv
  gv="$(go_bin_version)"
  if [ -n "$gv" ] && go_version_ok "$gv"; then
    record golang OK "present ($gv)"
    return 0
  fi
  if ensure_go; then
    record golang OK "$(go_bin_version)"
  else
    record golang MISS "Go toolchain unavailable"
  fi
}

# --- pipx tools -------------------------------------------------------------
ensure_pipx() {
  if ! command -v pipx > /dev/null 2>&1; then
    apt_update_once || true
    run_logged apt-get install -y --no-install-recommends pipx python3-venv || true
  fi
  if ! command -v pipx > /dev/null 2>&1; then return 1; fi
  run_logged pipx ensurepath || true
  export PATH="/usr/local/bin:${HOME:-/root}/.local/bin:${PATH}"
  return 0
}

pipx_tool() { # name package probe...
  local name="$1" pkg="$2" detail
  shift 2
  if tool_probes_present "$@"; then
    record "$name" OK "already present"
    return 0
  fi
  if ! ensure_pipx; then
    record "$name" MISS "pipx unavailable"
    return 0
  fi
  if run_logged pipx install "$pkg"; then
    if tool_probes_present "$@"; then
      record "$name" OK "installed"
    else
      record "$name" MISS "installed but not on PATH"
    fi
  else
    detail="$(attempt_reason)"
    record "$name" MISS "${detail:-pipx install failed}"
  fi
}

# --- apt full-set tools -----------------------------------------------------
apt_tool() { # name package probe
  local name="$1" pkg="$2" probe="$3" detail
  if command -v "$probe" > /dev/null 2>&1; then
    record "$name" OK "already present"
    return 0
  fi
  apt_update_once || true
  if run_logged apt-get install -y --no-install-recommends "$pkg"; then
    if command -v "$probe" > /dev/null 2>&1; then
      record "$name" OK "installed"
    else
      record "$name" MISS "installed but '$probe' not found"
    fi
  else
    detail="$(attempt_reason)"
    record "$name" MISS "${detail:-apt install failed}"
  fi
}

install_rizin() {
  if command -v rizin > /dev/null 2>&1 || command -v radare2 > /dev/null 2>&1; then
    record rizin OK "already present"
    return 0
  fi
  apt_update_once || true
  if run_logged apt-get install -y --no-install-recommends rizin; then
    record rizin OK "installed (rizin)"
    return 0
  fi
  if run_logged apt-get install -y --no-install-recommends radare2; then
    record rizin OK "installed (radare2 fallback)"
    return 0
  fi
  record rizin MISS "neither rizin nor radare2 packaged"
}

# --- wordlists --------------------------------------------------------------
install_seclists() {
  local entry
  if [ -d /usr/share/seclists ] && [ -n "$(ls -A /usr/share/seclists 2> /dev/null || true)" ]; then
    record seclists OK "already present"
    return 0
  fi
  apt_update_once || true
  if dpkg -s seclists > /dev/null 2>&1 || apt-cache show seclists > /dev/null 2>&1; then
    if run_logged apt-get install -y --no-install-recommends seclists; then
      record seclists OK "installed (apt)"
      return 0
    fi
  fi
  if ! command -v git > /dev/null 2>&1; then
    run_logged apt-get install -y --no-install-recommends git || true
  fi
  if command -v git > /dev/null 2>&1 && run_logged git clone --depth 1 https://github.com/danielmiessler/SecLists.git /usr/share/seclists; then
    record seclists OK "cloned to /usr/share/seclists"
  else
    record seclists MISS "$(attempt_reason)"
  fi
}

rockyou_path() {
  local p
  for p in \
    /usr/share/wordlists/rockyou.txt \
    /usr/share/wordlists/rockyou.txt.gz \
    /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt \
    /usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt.tar.gz; do
    if [ -e "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  printf ''
}

install_rockyou() {
  local p
  p="$(rockyou_path)"
  if [ -n "$p" ]; then
    record rockyou OK "present ($p)"
    return 0
  fi
  apt_update_once || true
  if apt-cache show wordlists > /dev/null 2>&1; then
    run_logged apt-get install -y --no-install-recommends wordlists || true
  fi
  if dpkg -s seclists > /dev/null 2>&1; then
    run_logged apt-get install -y --no-install-recommends seclists || true
  fi
  p="$(rockyou_path)"
  if [ -n "$p" ]; then
    record rockyou OK "present ($p)"
    return 0
  fi
  record rockyou MISS "no wordlists/seclists rockyou package on this distro"
}

# --- full-set dispatch ------------------------------------------------------
install_full_tool() {
  case "$1" in
    golang) install_golang ;;
    nuclei) go_tool nuclei "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest" ;;
    subfinder) go_tool subfinder "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest" ;;
    httpx) go_tool httpx "github.com/projectdiscovery/httpx/cmd/httpx@latest" ;;
    ffuf) go_tool ffuf "github.com/ffuf/ffuf/v2@latest" ;;
    gobuster) go_tool gobuster "github.com/OJ/gobuster/v3@latest" ;;
    amass) go_tool amass "github.com/owasp-amass/amass/v4/...@master" ;;
    kerbrute) go_tool kerbrute "github.com/ropnop/kerbrute@latest" ;;
    sqlmap) pipx_tool sqlmap sqlmap sqlmap ;;
    impacket) pipx_tool impacket impacket impacket-smbserver ;;
    netexec) pipx_tool netexec netexec nxc netexec ;;
    bloodhound) pipx_tool bloodhound bloodhound bloodhound-python ;;
    hydra) apt_tool hydra hydra hydra ;;
    john) apt_tool john john john ;;
    nikto) apt_tool nikto nikto nikto ;;
    whatweb) apt_tool whatweb whatweb whatweb ;;
    masscan) apt_tool masscan masscan masscan ;;
    aircrack-ng) apt_tool aircrack-ng aircrack-ng aircrack-ng ;;
    dnsrecon) apt_tool dnsrecon dnsrecon dnsrecon ;;
    smbclient) apt_tool smbclient smbclient smbclient ;;
    ldap-utils) apt_tool ldap-utils ldap-utils ldapsearch ;;
    binutils) apt_tool binutils binutils objdump ;;
    gdb) apt_tool gdb gdb gdb ;;
    strace) apt_tool strace strace strace ;;
    ltrace) apt_tool ltrace ltrace ltrace ;;
    rizin) install_rizin ;;
    seclists) install_seclists ;;
    rockyou) install_rockyou ;;
    *) record "$1" MISS "unknown tool" ;;
  esac
}

install_selected() { # name
  local name="$1"
  if is_core_pkg "$name"; then
    install_core_pkg "$name"
  elif is_full_tool "$name"; then
    install_full_tool "$name"
  else
    record "$name" MISS "unknown tool (see --list)"
  fi
}

# --- argument parsing -------------------------------------------------------
add_tool_spec() {
  local spec="$1" item
  local -a parts=()
  IFS=',' read -r -a parts <<< "$spec"
  for item in "${parts[@]}"; do
    item="${item//[[:space:]]/}"
    if [ -n "$item" ]; then
      SELECTED_TOOLS+=("$item")
    fi
  done
}

while [ $# -gt 0 ]; do
  case "$1" in
    --core) SELECT_CORE=1 ;;
    --full) SELECT_FULL=1 ;;
    --list) LIST_ONLY=1 ;;
    --tools)
      shift
      if [ $# -eq 0 ]; then
        warn "--tools requires a comma-separated value"
        exit 2
      fi
      add_tool_spec "$1"
      ;;
    --tools=*) add_tool_spec "${1#*=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      warn "unknown argument: $1"
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$LIST_ONLY" = 1 ]; then
  print_list
  exit 0
fi

# --- privilege and platform guards ------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo > /dev/null 2>&1; then
    printf 'toolchain: not root; re-executing with sudo\n'
    exec sudo -E bash "$SCRIPT_PATH" "${ORIG_ARGS[@]}"
  fi
  warn "must run as root (no sudo found)"
  exit 1
fi

if ! command -v apt-get > /dev/null 2>&1 || ! command -v dpkg > /dev/null 2>&1; then
  warn "this installer requires Debian or Ubuntu (apt-get not found)"
  exit 1
fi

# --- run --------------------------------------------------------------------
ATTEMPT_LOG="$(mktemp)"
trap 'rm -f "$ATTEMPT_LOG"' EXIT

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/bin:${HOME:-/root}/.local/bin:/usr/sbin:/sbin:${PATH}"
export PIPX_HOME="${PIPX_HOME:-/opt/pipx}"
export PIPX_BIN_DIR="${PIPX_BIN_DIR:-/usr/local/bin}"

if [ "$SELECT_FULL" = 1 ]; then SELECT_CORE=1; fi
if [ "$SELECT_CORE" = 0 ] && [ "$SELECT_FULL" = 0 ] && [ "${#SELECTED_TOOLS[@]}" -eq 0 ]; then
  SELECT_CORE=1
fi

printf 'toolchain: core=%s full=%s tools=%s\n' \
  "$SELECT_CORE" "$SELECT_FULL" "${SELECTED_TOOLS[*]:-none}"

ensure_base

if [ "$SELECT_CORE" = 1 ]; then install_core; fi

if [ "$SELECT_FULL" = 1 ]; then
  section "full toolset"
  for _tool in "${FULL_TOOLS[@]}"; do
    install_full_tool "$_tool"
  done
fi

if [ "${#SELECTED_TOOLS[@]}" -gt 0 ]; then
  section "selected tools"
  for _tool in "${SELECTED_TOOLS[@]}"; do
    install_selected "$_tool"
  done
fi

print_summary

# Core packages are required; a full-set tool or unknown name only warns. An
# unknown requested tool is a usage error and does make the run fail.
final_status=0
for name in "${RESULT_ORDER[@]}"; do
  if [ "${RESULT_STATUS[$name]}" = MISS ]; then
    if is_core_pkg "$name" || ! is_full_tool "$name"; then
      final_status=1
    fi
  fi
done
exit "$final_status"
