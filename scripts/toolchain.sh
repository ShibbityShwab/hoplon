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
#   HOPLON_GHIDRA_VERSION  NSA Ghidra release to fetch (default 12.1.4)
#   HOPLON_SLIVER_VERSION  BishopFox Sliver release to fetch (default 1.7.7)
#   HOPLON_FEROXBUSTER_VERSION  feroxbuster release to fetch (default 2.13.1)
#   HOPLON_TRIVY_VERSION   Aqua Trivy release to fetch (default 0.74.0)
#   HOPLON_KUBECTL_VERSION kubectl release to fetch (default 1.31.0)
#   HOPLON_UPX_VERSION     UPX release to fetch (default 5.2.1)
#   HOPLON_JADX_VERSION    jadx release to fetch (default 1.5.6)
#
# Version-pinned GitHub release downloads are best-effort: if the tag or asset
# is missing the tool is recorded MISS and the run continues. Every release
# tool can be redirected by setting its HOPLON_*_VERSION before running.
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
  # recon and OSINT
  dnsx
  naabu
  katana
  theharvester
  # web
  feroxbuster
  dirsearch
  dalfox
  arjun
  commix
  wpscan
  zaproxy
  gospider
  # credentials
  hashcat
  hashcat-utils
  medusa
  patator
  crunch
  cewl
  ncrack
  # active directory and windows
  certipy-ad
  mitm6
  responder
  ldapdomaindump
  smbmap
  enum4linux-ng
  evil-winrm
  pypykatz
  coercer
  # exploit development and pwn
  pwntools
  pwndbg
  gef
  ROPgadget
  ropper
  checksec
  one_gadget
  capstone
  keystone-engine
  unicorn
  angr
  valgrind
  qemu-user
  nasm
  # fuzzing
  afl++
  honggfuzz
  radamsa
  boofuzz
  clang
  llvm
  # reversing and forensics
  ghidra
  jadx
  apktool
  frida-tools
  binwalk
  exiftool
  yara
  sleuthkit
  foremost
  testdisk
  steghide
  upx
  volatility3
  # network and MITM
  tshark
  bettercap
  ettercap
  scapy
  hping3
  arp-scan
  # cloud and containers
  awscli
  azure-cli
  kubectl
  trivy
  docker
  kube-hunter
  # post-exploitation and C2
  sliver
  chisel
  ligolo-ng
  peass
  # cross-compilation
  mingw-w64
  rust
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
    run_logged apt-get install -y --no-install-recommends pipx python3-venv python3-dev || true
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
apt_probe_present() { # pkg probe
  if [ -n "$2" ]; then
    command -v "$2" > /dev/null 2>&1
  else
    dpkg -s "$1" > /dev/null 2>&1
  fi
}

apt_tool() { # name package [probe]
  local name="$1" pkg="$2" probe="${3:-}" detail
  if apt_probe_present "$pkg" "$probe"; then
    record "$name" OK "already present"
    return 0
  fi
  apt_update_once || true
  if run_logged apt-get install -y --no-install-recommends "$pkg"; then
    if apt_probe_present "$pkg" "$probe"; then
      record "$name" OK "installed"
    else
      record "$name" MISS "installed but not detected"
    fi
  else
    detail="$(attempt_reason)"
    record "$name" MISS "${detail:-apt install failed}"
  fi
}

apt_py_tool() { # name package import-module
  local name="$1" pkg="$2" module="$3" detail
  if python3 -c "import $module" > /dev/null 2>&1; then
    record "$name" OK "already present (python3 -c import $module)"
    return 0
  fi
  apt_update_once || true
  if run_logged apt-get install -y --no-install-recommends "$pkg"; then
    if python3 -c "import $module" > /dev/null 2>&1; then
      record "$name" OK "installed (apt $pkg)"
    else
      record "$name" MISS "installed but import $module failed"
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

# --- gem tools --------------------------------------------------------------
ensure_gem() {
  if ! command -v gem > /dev/null 2>&1; then
    apt_update_once || true
    run_logged apt-get install -y --no-install-recommends ruby ruby-dev libreadline-dev build-essential || true
  fi
  command -v gem > /dev/null 2>&1
}

gem_tool() { # name gem [probe]
  local name="$1" pkg="$2" probe="${3:-$1}" detail
  if command -v "$probe" > /dev/null 2>&1; then
    record "$name" OK "already present"
    return 0
  fi
  if ! ensure_gem; then
    record "$name" MISS "ruby/gem unavailable"
    return 0
  fi
  if run_logged gem install --no-document "$pkg"; then
    if command -v "$probe" > /dev/null 2>&1; then
      record "$name" OK "installed (gem)"
    else
      record "$name" MISS "installed but '$probe' not on PATH"
    fi
  else
    detail="$(attempt_reason)"
    record "$name" MISS "${detail:-gem install failed}"
  fi
}

# --- cargo tools ------------------------------------------------------------
ensure_cargo() {
  export PATH="${HOME:-/root}/.cargo/bin:${PATH}"
  if command -v cargo > /dev/null 2>&1; then return 0; fi
  apt_update_once || true
  run_logged apt-get install -y --no-install-recommends rustc cargo || true
  if command -v cargo > /dev/null 2>&1; then return 0; fi
  if command -v curl > /dev/null 2>&1 || command -v wget > /dev/null 2>&1; then
    if run_logged bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal'; then
      export PATH="${HOME:-/root}/.cargo/bin:${PATH}"
      if command -v cargo > /dev/null 2>&1; then return 0; fi
    fi
  fi
  return 1
}

cargo_tool() { # name crate [probe]
  local name="$1" crate="$2" probe="${3:-$1}" detail
  if command -v "$probe" > /dev/null 2>&1; then
    record "$name" OK "already present"
    return 0
  fi
  if ! ensure_cargo; then
    record "$name" MISS "cargo unavailable"
    return 0
  fi
  if run_logged cargo install --root /usr/local "$crate"; then
    if command -v "$probe" > /dev/null 2>&1; then
      record "$name" OK "installed (cargo)"
    else
      record "$name" MISS "installed but '$probe' not on PATH"
    fi
  else
    detail="$(attempt_reason)"
    record "$name" MISS "${detail:-cargo install failed}"
  fi
}

# --- git tools --------------------------------------------------------------
git_tool() { # name repo dir [probe] [link]
  local name="$1" repo="$2" dir="$3" probe="${4:-}" link="${5:-}" detail
  if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2> /dev/null || true)" ]; then
    if [ -z "$probe" ] || [ -e "$dir/$probe" ]; then
      record "$name" OK "already present ($dir)"
      return 0
    fi
  fi
  if ! command -v git > /dev/null 2>&1; then
    apt_update_once || true
    run_logged apt-get install -y --no-install-recommends git || true
  fi
  if ! command -v git > /dev/null 2>&1; then
    record "$name" MISS "git unavailable"
    return 0
  fi
  rm -rf "$dir"
  if ! run_logged git clone --depth 1 "$repo" "$dir"; then
    detail="$(attempt_reason)"
    record "$name" MISS "${detail:-git clone failed}"
    return 0
  fi
  if [ -n "$link" ] && [ -e "$dir/$link" ]; then
    chmod +x "$dir/$link"
    ln -sf "$dir/$link" "/usr/local/bin/$name"
  fi
  record "$name" OK "cloned to $dir"
}

# --- GitHub release downloads ----------------------------------------------
download_file() { # url dest
  if command -v curl > /dev/null 2>&1; then
    run_logged curl -fsSL "$1" -o "$2"
  elif command -v wget > /dev/null 2>&1; then
    run_logged wget -q "$1" -O "$2"
  else
    return 1
  fi
}

ensure_download() {
  if ! command -v curl > /dev/null 2>&1 && ! command -v wget > /dev/null 2>&1; then
    apt_update_once || true
    run_logged apt-get install -y --no-install-recommends curl ca-certificates || true
  fi
  if ! command -v tar > /dev/null 2>&1 || ! command -v unzip > /dev/null 2>&1; then
    apt_update_once || true
    run_logged apt-get install -y --no-install-recommends tar xz-utils unzip || true
  fi
  if command -v curl > /dev/null 2>&1 || command -v wget > /dev/null 2>&1; then
    return 0
  fi
  return 1
}

install_found_bin() { # dir bin
  local dir="$1" bin="$2" found
  found="$(find "$dir" -type f -name "$bin" -print -quit 2> /dev/null || true)"
  if [ -z "$found" ]; then return 1; fi
  install -m 0755 "$found" "/usr/local/bin/$bin"
}

fetch_release() { # url kind bin
  local url="$1" kind="$2" bin="$3" tmp rc=0
  ensure_download || return 1
  tmp="$(mktemp -d)"
  case "$kind" in
    bin)
      download_file "$url" "$tmp/$bin" && install -m 0755 "$tmp/$bin" "/usr/local/bin/$bin" || rc=1
      ;;
    tar.gz | tgz)
      { download_file "$url" "$tmp/a.tgz" && run_logged tar -C "$tmp" -xzf "$tmp/a.tgz" && install_found_bin "$tmp" "$bin"; } || rc=1
      ;;
    tar.xz)
      { download_file "$url" "$tmp/a.txz" && run_logged tar -C "$tmp" -xJf "$tmp/a.txz" && install_found_bin "$tmp" "$bin"; } || rc=1
      ;;
    zip)
      { download_file "$url" "$tmp/a.zip" && run_logged unzip -q -o "$tmp/a.zip" -d "$tmp" && install_found_bin "$tmp" "$bin"; } || rc=1
      ;;
    *)
      rc=1
      ;;
  esac
  rm -rf "$tmp"
  return "$rc"
}

release_tool() { # name url kind bin [probe]
  local name="$1" url="$2" kind="$3" bin="$4" probe="${5:-$4}"
  if command -v "$probe" > /dev/null 2>&1; then
    record "$name" OK "already present"
    return 0
  fi
  if fetch_release "$url" "$kind" "$bin"; then
    if command -v "$bin" > /dev/null 2>&1; then
      record "$name" OK "installed (release)"
    else
      record "$name" OK "installed to /usr/local/bin/$bin"
    fi
    return 0
  fi
  record "$name" MISS "$(attempt_reason)"
}

ensure_java() {
  if command -v java > /dev/null 2>&1; then return 0; fi
  apt_update_once || true
  run_logged apt-get install -y --no-install-recommends default-jre-headless || true
  command -v java > /dev/null 2>&1
}

try_cmd() { # probe cmd...
  local probe="$1"
  shift
  if run_logged "$@"; then
    if [ -z "$probe" ]; then return 0; fi
    if command -v "$probe" > /dev/null 2>&1; then return 0; fi
  fi
  return 1
}

# --- multi-method installers ------------------------------------------------
install_theharvester() {
  local name=theharvester probe=theHarvester
  if command -v "$probe" > /dev/null 2>&1; then
    record "$name" OK "already present"
    return 0
  fi
  apt_update_once || true
  if try_cmd "$probe" apt-get install -y --no-install-recommends theharvester; then
    record "$name" OK "installed (apt)"
    return 0
  fi
  if ensure_pipx && try_cmd "$probe" pipx install theHarvester; then
    record "$name" OK "installed (pipx)"
    return 0
  fi
  record "$name" MISS "$(attempt_reason)"
}

install_feroxbuster() {
  local ver url kind
  if command -v feroxbuster > /dev/null 2>&1; then
    record feroxbuster OK "already present"
    return 0
  fi
  ver="${HOPLON_FEROXBUSTER_VERSION:-2.13.1}"
  case "$(uname -m)" in
    x86_64 | amd64)
      url="https://github.com/epi052/feroxbuster/releases/download/v${ver}/x86_64-linux-feroxbuster.tar.gz"
      kind=tar.gz
      ;;
    aarch64 | arm64)
      url="https://github.com/epi052/feroxbuster/releases/download/v${ver}/aarch64-linux-feroxbuster.zip"
      kind=zip
      ;;
    *) url="" ;;
  esac
  if [ -n "$url" ] && fetch_release "$url" "$kind" feroxbuster; then
    record feroxbuster OK "installed (release v${ver})"
    return 0
  fi
  cargo_tool feroxbuster feroxbuster feroxbuster
}

install_patator() {
  if command -v patator > /dev/null 2>&1; then
    record patator OK "already present"
    return 0
  fi
  if ensure_pipx && try_cmd patator pipx install patator; then
    record patator OK "installed (pipx)"
    return 0
  fi
  apt_update_once || true
  if try_cmd patator apt-get install -y --no-install-recommends patator; then
    record patator OK "installed (apt)"
    return 0
  fi
  record patator MISS "$(attempt_reason)"
}

install_enum4linux_ng() {
  if command -v enum4linux-ng > /dev/null 2>&1; then
    record enum4linux-ng OK "already present"
    return 0
  fi
  if [ -e /opt/enum4linux-ng/enum4linux-ng.py ]; then
    record enum4linux-ng OK "already present (/opt/enum4linux-ng)"
    return 0
  fi
  if ensure_pipx && try_cmd enum4linux-ng pipx install enum4linux-ng; then
    record enum4linux-ng OK "installed (pipx)"
    return 0
  fi
  git_tool enum4linux-ng https://github.com/cddmp/enum4linux-ng /opt/enum4linux-ng enum4linux-ng.py enum4linux-ng.py
}

install_gef() {
  if command -v gef > /dev/null 2>&1; then
    record gef OK "already present"
    return 0
  fi
  if ensure_pipx && try_cmd gef pipx install gef; then
    record gef OK "installed (pipx)"
    return 0
  fi
  git_tool gef https://github.com/hugsy/gef /opt/gef gef.py gef.py
}

install_hashcat_utils() {
  if dpkg -s hashcat-utils > /dev/null 2>&1 || [ -d /usr/lib/hashcat-utils ] || [ -d /opt/hashcat-utils ]; then
    record hashcat-utils OK "already present"
    return 0
  fi
  apt_update_once || true
  if apt-cache show hashcat-utils > /dev/null 2>&1; then
    if run_logged apt-get install -y --no-install-recommends hashcat-utils; then
      record hashcat-utils OK "installed (apt)"
      return 0
    fi
  fi
  if ! command -v git > /dev/null 2>&1; then
    run_logged apt-get install -y --no-install-recommends git || true
  fi
  if ! command -v make > /dev/null 2>&1; then
    run_logged apt-get install -y --no-install-recommends build-essential || true
  fi
  if command -v git > /dev/null 2>&1 && command -v make > /dev/null 2>&1; then
    if run_logged git clone --depth 1 https://github.com/hashcat/hashcat-utils.git /opt/hashcat-utils && run_logged make -C /opt/hashcat-utils; then
      record hashcat-utils OK "built from git to /opt/hashcat-utils"
      return 0
    fi
  fi
  record hashcat-utils MISS "$(attempt_reason)"
}

install_aflpp() {
  local p
  if command -v afl-fuzz > /dev/null 2>&1; then
    record "afl++" OK "already present"
    return 0
  fi
  apt_update_once || true
  for p in afl++ aflplusplus; do
    if apt-cache show "$p" > /dev/null 2>&1; then
      if run_logged apt-get install -y --no-install-recommends "$p" && command -v afl-fuzz > /dev/null 2>&1; then
        record "afl++" OK "installed (apt $p)"
        return 0
      fi
    fi
  done
  record "afl++" MISS "no afl++ package on this distro"
}

install_radamsa() {
  if command -v radamsa > /dev/null 2>&1; then
    record radamsa OK "already present"
    return 0
  fi
  apt_update_once || true
  if apt-cache show radamsa > /dev/null 2>&1; then
    if run_logged apt-get install -y --no-install-recommends radamsa && command -v radamsa > /dev/null 2>&1; then
      record radamsa OK "installed (apt)"
      return 0
    fi
  fi
  if ! command -v git > /dev/null 2>&1; then
    run_logged apt-get install -y --no-install-recommends git || true
  fi
  if command -v git > /dev/null 2>&1 && command -v make > /dev/null 2>&1; then
    if run_logged git clone --depth 1 https://gitlab.com/akihe/radamsa.git /opt/radamsa && run_logged make -C /opt/radamsa; then
      if [ -e /opt/radamsa/bin/radamsa ]; then
        printf '#!/usr/bin/env sh\nexec /opt/radamsa/bin/radamsa "$@"\n' > /usr/local/bin/radamsa
        chmod +x /usr/local/bin/radamsa
      fi
      record radamsa OK "built from git to /opt/radamsa"
      return 0
    fi
  fi
  record radamsa MISS "$(attempt_reason)"
}

install_ghidra() {
  local ver tag api json url tmp run
  if [ -x /usr/local/bin/ghidra ] || command -v ghidra > /dev/null 2>&1; then
    record ghidra OK "already present"
    return 0
  fi
  ver="${HOPLON_GHIDRA_VERSION:-12.1.4}"
  tag="Ghidra_${ver}_build"
  api="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/tags/${tag}"
  ensure_download || {
    record ghidra MISS "no downloader"
    return 0
  }
  ensure_java || true
  json=""
  if command -v curl > /dev/null 2>&1; then
    json="$(curl -fsSL "$api" 2> /dev/null || true)"
  fi
  if [ -z "$json" ] && command -v wget > /dev/null 2>&1; then
    json="$(wget -qO- "$api" 2> /dev/null || true)"
  fi
  url="$(printf '%s' "$json" | jq -r '.assets[]?.browser_download_url' 2> /dev/null | grep -m1 '\.zip$' || true)"
  if [ -z "$url" ]; then
    record ghidra MISS "no release asset for tag $tag"
    return 0
  fi
  tmp="$(mktemp -d)"
  if ! download_file "$url" "$tmp/ghidra.zip" || ! run_logged unzip -q -o "$tmp/ghidra.zip" -d /opt/ghidra; then
    rm -rf "$tmp"
    record ghidra MISS "$(attempt_reason)"
    return 0
  fi
  rm -rf "$tmp"
  run="$(find /opt/ghidra -type f -name ghidraRun -print -quit 2> /dev/null || true)"
  if [ -z "$run" ]; then
    record ghidra MISS "ghidraRun not found in archive"
    return 0
  fi
  chmod +x "$run"
  printf '#!/usr/bin/env sh\nexec %s "$@"\n' "$run" > /usr/local/bin/ghidra
  chmod +x /usr/local/bin/ghidra
  record ghidra OK "installed (Ghidra $ver to /opt/ghidra)"
}

install_jadx() {
  local ver url tmp run
  if command -v jadx > /dev/null 2>&1; then
    record jadx OK "already present"
    return 0
  fi
  apt_update_once || true
  if apt-cache show jadx > /dev/null 2>&1; then
    if run_logged apt-get install -y --no-install-recommends jadx && command -v jadx > /dev/null 2>&1; then
      record jadx OK "installed (apt)"
      return 0
    fi
  fi
  ver="${HOPLON_JADX_VERSION:-1.5.6}"
  ensure_download || {
    record jadx MISS "no downloader"
    return 0
  }
  ensure_java || true
  url="https://github.com/skylot/jadx/releases/download/v${ver}/jadx-${ver}.zip"
  tmp="$(mktemp -d)"
  if ! download_file "$url" "$tmp/jadx.zip" || ! run_logged unzip -q -o "$tmp/jadx.zip" -d /opt/jadx; then
    rm -rf "$tmp"
    record jadx MISS "$(attempt_reason)"
    return 0
  fi
  rm -rf "$tmp"
  run="$(find /opt/jadx -type f -path '*/bin/jadx' -print -quit 2> /dev/null || true)"
  if [ -z "$run" ]; then
    record jadx MISS "jadx launcher not found in archive"
    return 0
  fi
  chmod +x "$run"
  printf '#!/usr/bin/env sh\nexec %s "$@"\n' "$run" > /usr/local/bin/jadx
  chmod +x /usr/local/bin/jadx
  record jadx OK "installed (jadx $ver to /opt/jadx)"
}

install_upx() {
  local ver url
  if command -v upx > /dev/null 2>&1; then
    record upx OK "already present"
    return 0
  fi
  apt_update_once || true
  if apt-cache show upx-ucl > /dev/null 2>&1; then
    if run_logged apt-get install -y --no-install-recommends upx-ucl && command -v upx > /dev/null 2>&1; then
      record upx OK "installed (apt upx-ucl)"
      return 0
    fi
  fi
  if apt-cache show upx > /dev/null 2>&1; then
    if run_logged apt-get install -y --no-install-recommends upx && command -v upx > /dev/null 2>&1; then
      record upx OK "installed (apt upx)"
      return 0
    fi
  fi
  ver="${HOPLON_UPX_VERSION:-5.2.1}"
  case "$(uname -m)" in
    x86_64 | amd64) url="https://github.com/upx/upx/releases/download/v${ver}/upx-${ver}-amd64_linux.tar.xz" ;;
    aarch64 | arm64) url="https://github.com/upx/upx/releases/download/v${ver}/upx-${ver}-arm64_linux.tar.xz" ;;
    *) url="" ;;
  esac
  if [ -n "$url" ] && fetch_release "$url" tar.xz upx; then
    record upx OK "installed (release v${ver})"
    return 0
  fi
  record upx MISS "$(attempt_reason)"
}

install_kubectl() {
  local ver arch
  ver="${HOPLON_KUBECTL_VERSION:-1.31.0}"
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) arch="" ;;
  esac
  if [ -z "$arch" ]; then
    record kubectl MISS "unsupported arch"
    return 0
  fi
  release_tool kubectl "https://dl.k8s.io/release/v${ver}/bin/linux/${arch}/kubectl" bin kubectl kubectl
}

install_trivy() {
  local ver arch
  ver="${HOPLON_TRIVY_VERSION:-0.74.0}"
  case "$(uname -m)" in
    x86_64 | amd64) arch=64bit ;;
    aarch64 | arm64) arch=ARM64 ;;
    *) arch="" ;;
  esac
  if [ -z "$arch" ]; then
    record trivy MISS "unsupported arch"
    return 0
  fi
  release_tool trivy "https://github.com/aquasecurity/trivy/releases/download/v${ver}/trivy_${ver}_Linux-${arch}.tar.gz" tar.gz trivy trivy
}

install_sliver() {
  local ver arch
  ver="${HOPLON_SLIVER_VERSION:-1.7.7}"
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) arch="" ;;
  esac
  if [ -z "$arch" ]; then
    record sliver MISS "unsupported arch"
    return 0
  fi
  release_tool sliver "https://github.com/BishopFox/sliver/releases/download/v${ver}/sliver-server_linux-${arch}" bin sliver-server sliver-server
}

install_ligolo_ng() {
  local name=ligolo-ng tmp built=0
  if command -v ligolo-proxy > /dev/null 2>&1 || command -v ligolo-ng > /dev/null 2>&1; then
    record "$name" OK "already present"
    return 0
  fi
  if ! ensure_go; then
    record "$name" MISS "no usable Go toolchain"
    return 0
  fi
  tmp="$(mktemp -d)"
  if run_logged env GOBIN="$tmp" go install github.com/nicocha30/ligolo-ng/cmd/proxy@latest; then
    install -m 0755 "$tmp/proxy" /usr/local/bin/ligolo-proxy
    built=1
  fi
  if run_logged env GOBIN="$tmp" go install github.com/nicocha30/ligolo-ng/cmd/agent@latest; then
    install -m 0755 "$tmp/agent" /usr/local/bin/ligolo-agent
    built=1
  fi
  rm -rf "$tmp"
  if [ "$built" = 1 ]; then
    record "$name" OK "installed (ligolo-proxy, ligolo-agent)"
  else
    record "$name" MISS "$(attempt_reason)"
  fi
}

install_peass() {
  git_tool peass https://github.com/peass-ng/PEASS-ng /opt/peass "" ""
}

install_rust() {
  if command -v cargo > /dev/null 2>&1 && command -v rustc > /dev/null 2>&1; then
    record rust OK "already present"
    return 0
  fi
  apt_update_once || true
  if run_logged apt-get install -y --no-install-recommends rustc cargo && command -v cargo > /dev/null 2>&1; then
    record rust OK "installed (apt)"
    return 0
  fi
  if command -v curl > /dev/null 2>&1 || command -v wget > /dev/null 2>&1; then
    if run_logged bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal'; then
      export PATH="${HOME:-/root}/.cargo/bin:${PATH}"
      if command -v cargo > /dev/null 2>&1; then
        record rust OK "installed (rustup)"
        return 0
      fi
    fi
  fi
  record rust MISS "apt and rustup both failed"
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
    dnsx) go_tool dnsx "github.com/projectdiscovery/dnsx/cmd/dnsx@latest" ;;
    naabu) go_tool naabu "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest" ;;
    katana) go_tool katana "github.com/projectdiscovery/katana/cmd/katana@latest" ;;
    theharvester) install_theharvester ;;
    feroxbuster) install_feroxbuster ;;
    dirsearch) pipx_tool dirsearch dirsearch dirsearch ;;
    dalfox) go_tool dalfox "github.com/hahwul/dalfox/v2@latest" ;;
    arjun) pipx_tool arjun arjun arjun ;;
    commix) pipx_tool commix commix commix ;;
    wpscan) gem_tool wpscan wpscan wpscan ;;
    zaproxy) apt_tool zaproxy zaproxy zaproxy ;;
    gospider) go_tool gospider "github.com/jaeles-project/gospider@latest" ;;
    hashcat) apt_tool hashcat hashcat hashcat ;;
    hashcat-utils) install_hashcat_utils ;;
    medusa) apt_tool medusa medusa medusa ;;
    patator) install_patator ;;
    crunch) apt_tool crunch crunch crunch ;;
    cewl) apt_tool cewl cewl cewl ;;
    ncrack) apt_tool ncrack ncrack ncrack ;;
    certipy-ad) pipx_tool certipy-ad certipy-ad certipy ;;
    mitm6) pipx_tool mitm6 mitm6 mitm6 ;;
    responder) git_tool responder https://github.com/lgandx/Responder /opt/responder Responder.py Responder.py ;;
    ldapdomaindump) pipx_tool ldapdomaindump ldapdomaindump ldapdomaindump ;;
    smbmap) pipx_tool smbmap smbmap smbmap ;;
    enum4linux-ng) install_enum4linux_ng ;;
    evil-winrm) gem_tool evil-winrm evil-winrm evil-winrm ;;
    pypykatz) pipx_tool pypykatz pypykatz pypykatz ;;
    coercer) pipx_tool coercer coercer coercer ;;
    pwntools) pipx_tool pwntools pwntools pwn ;;
    pwndbg) git_tool pwndbg https://github.com/pwndbg/pwndbg /opt/pwndbg pwndbg.py ;;
    gef) install_gef ;;
    ROPgadget) pipx_tool ROPgadget ROPgadget ROPgadget ;;
    ropper) pipx_tool ropper ropper ropper ;;
    checksec) apt_tool checksec checksec checksec ;;
    one_gadget) gem_tool one_gadget one_gadget one_gadget ;;
    capstone) apt_py_tool capstone python3-capstone capstone ;;
    keystone-engine) apt_py_tool keystone-engine python3-keystone keystone ;;
    unicorn) apt_py_tool unicorn python3-unicorn unicorn ;;
    angr) pipx_tool angr angr angr ;;
    valgrind) apt_tool valgrind valgrind valgrind ;;
    qemu-user) apt_tool qemu-user qemu-user qemu-x86_64 ;;
    nasm) apt_tool nasm nasm nasm ;;
    afl++) install_aflpp ;;
    honggfuzz) apt_tool honggfuzz honggfuzz honggfuzz ;;
    radamsa) install_radamsa ;;
    boofuzz) pipx_tool boofuzz boofuzz boo ;;
    clang) apt_tool clang clang clang ;;
    llvm) apt_tool llvm llvm "" ;;
    ghidra) install_ghidra ;;
    jadx) install_jadx ;;
    apktool) apt_tool apktool apktool apktool ;;
    frida-tools) pipx_tool frida-tools frida-tools frida ;;
    binwalk) apt_tool binwalk binwalk binwalk ;;
    exiftool) apt_tool exiftool libimage-exiftool-perl exiftool ;;
    yara) apt_tool yara yara yara ;;
    sleuthkit) apt_tool sleuthkit sleuthkit fls ;;
    foremost) apt_tool foremost foremost foremost ;;
    testdisk) apt_tool testdisk testdisk testdisk ;;
    steghide) apt_tool steghide steghide steghide ;;
    upx) install_upx ;;
    volatility3) pipx_tool volatility3 volatility3 vol ;;
    tshark) apt_tool tshark tshark tshark ;;
    bettercap) apt_tool bettercap bettercap bettercap ;;
    ettercap) apt_tool ettercap ettercap-text-only ettercap ;;
    scapy) apt_tool scapy python3-scapy "" ;;
    hping3) apt_tool hping3 hping3 hping3 ;;
    arp-scan) apt_tool arp-scan arp-scan arp-scan ;;
    awscli) pipx_tool awscli awscli aws ;;
    azure-cli) pipx_tool azure-cli azure-cli az ;;
    kubectl) install_kubectl ;;
    trivy) install_trivy ;;
    docker) apt_tool docker docker.io docker ;;
    kube-hunter) pipx_tool kube-hunter kube-hunter kube-hunter ;;
    sliver) install_sliver ;;
    chisel) go_tool chisel "github.com/jpillora/chisel@latest" ;;
    ligolo-ng) install_ligolo_ng ;;
    peass) install_peass ;;
    mingw-w64) apt_tool mingw-w64 mingw-w64 x86_64-w64-mingw32-gcc ;;
    rust) install_rust ;;
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
    case "$name" in
      libimage-exiftool-perl) install_full_tool exiftool ;;
      *) record "$name" MISS "unknown tool (see --list)" ;;
    esac
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
