#!/usr/bin/env bash
# =============================================================================
# Hoplon QEMU VM backend.
#
# Runs Hoplon inside a Debian bookworm cloud image with its own kernel, fully
# separated from the host. State lives under $HOPLON_HOME/vm: the qcow2 disk,
# the NoCloud seed ISO, the pid file, the serial log, and the SSH key.
#
# QEMU is the one virtualization layer present on every supported host, so this
# backend runs on Linux (KVM), macOS on Intel and Apple Silicon (HVF), and
# Windows through WSL2 (KVM) or QEMU's WHPX/TCG accelerators.
#
# Usage:
#   vm.sh create [--force]   download the base image, copy and resize disk.qcow2,
#                            render vm/cloud-init into seed.iso
#   vm.sh start              boot the VM (hardware or software acceleration)
#   vm.sh stop               power the VM off (SIGTERM, then SIGKILL)
#   vm.sh status             show VM state
#   vm.sh ssh [-- cmd...]    wait for sshd, then open an SSH session
#   vm.sh run [-- cmd...]    create if needed, boot, then open a shell (default)
#   vm.sh console [args...]  create if needed, boot, then run the Hoplon console
#                            inside the guest; --shell opens a shell instead
#   vm.sh destroy            remove the VM disk, seed, logs, and generated key
#   vm.sh help
#
# Environment:
#   HOPLON_HOME            repo root (defaults to this script's parent)
#   HOPLON_VM_TOOLS        none | base | core | full   (default base)
#                          base is minimal and installs tools on demand through
#                          hoplon-tool; core and full preload the arsenal
#   HOPLON_VM_RAM          guest RAM in MiB      (default 4096)
#   HOPLON_VM_CPUS         guest vCPUs           (default 4)
#   HOPLON_VM_DISK         disk size after resize (default 20G)
#   HOPLON_VM_SSH_KEY      key to authorize; may be a public key or a private
#                          key (its .pub is used, or the public part derived).
#                          Default: ~/.ssh/id_ed25519.pub, else a dedicated key
#                          generated at $HOPLON_HOME/vm/id_ed25519
#   HOPLON_VM_SSH_PORT     hostfwd port           (default 2222)
#   HOPLON_VM_SSH_TIMEOUT  seconds to wait for sshd (default 300)
#   HOPLON_VM_SHARE        host dir to expose read-only over virtio-9p
#   HOPLON_VM_SHARE_TAG    9p mount tag (default engagements)
#   HOPLON_VM_SHARE_ALLOW  set 1 to share a directory inside HOPLON_HOME; by
#                          default such a share is refused because it exposes
#                          .env and the repo's home/ and vm/ state to the guest
#   HOPLON_VM_ACCEL        QEMU accelerator: kvm | hvf | whpx | tcg. Defaults to
#                          kvm on Linux with a usable /dev/kvm, hvf on macOS,
#                          whpx on Windows, else tcg (slow software emulation)
#   HOPLON_VM_IMAGE_URL    base qcow2 URL (default Debian bookworm genericcloud
#                          for the host architecture: amd64 or arm64)
# =============================================================================
set -euo pipefail

# State written below (disk.qcow2, seed.iso, vm.log, ssh_private_key_path) can
# include key material and image contents, so create it owner-only. Commands
# that install files explicitly (install -m ...) still set their own mode.
umask 077

HOPLON_HOME="${HOPLON_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)}"
export HOPLON_HOME

# Optional local settings. Matches scripts/install.sh and the launcher: .env is
# read as DATA through the shared loader, never sourced.
if [ -f "$HOPLON_HOME/scripts/env.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOPLON_HOME/scripts/env.sh"
  hoplon_load_env "$HOPLON_HOME/.env"
fi

VM_DIR="$HOPLON_HOME/vm"
CLOUD_INIT_DIR="$VM_DIR/cloud-init"
SEED_DIR="$VM_DIR/seed"
BASE_CACHE_DIR="$VM_DIR/cache"
DISK="$VM_DIR/disk.qcow2"
SEED_ISO="$VM_DIR/seed.iso"
PID_FILE="$VM_DIR/vm.pid"
LOG_FILE="$VM_DIR/vm.log"
KEY_RECORD="$VM_DIR/ssh_private_key_path"
KNOWN_HOSTS="$VM_DIR/known_hosts"

VM_TOOLS="${HOPLON_VM_TOOLS:-base}"
VM_RAM="${HOPLON_VM_RAM:-4096}"
VM_CPUS="${HOPLON_VM_CPUS:-4}"
VM_DISK="${HOPLON_VM_DISK:-20G}"
VM_SSH_PORT="${HOPLON_VM_SSH_PORT:-2222}"
VM_SSH_TIMEOUT="${HOPLON_VM_SSH_TIMEOUT:-300}"
VM_SHARE="${HOPLON_VM_SHARE:-}"
VM_SHARE_TAG="${HOPLON_VM_SHARE_TAG:-engagements}"
HOPLON_REPO_URL="${HOPLON_REPO_URL:-https://github.com/ShibbityShwab/hoplon}"

# QEMU binary, base image, accelerator, and CPU, resolved per host by
# resolve_host_arch and resolve_accel. HOPLON_VM_IMAGE_URL and HOPLON_VM_ACCEL
# override the automatic choice.
QEMU_BIN=""
IMAGE_URL=""
VM_ACCEL=""
VM_CPU=""

# SSH key material resolved by resolve_ssh_key.
SSH_KEY=""
SSH_KEY_PUB=""
VM_SSH_KEY_PATH=""

log() { printf 'vm: %s\n' "$*"; }
warn() { printf 'vm: %s\n' "$*" >&2; }
die() {
  printf 'vm: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" > /dev/null 2>&1 || die "missing required command: $1"
}

# Host architecture selects the QEMU system emulator and the Debian cloud image.
# arm64 hosts (Apple Silicon, Linux arm64) use qemu-system-aarch64 and the arm64
# image; x86_64 hosts use qemu-system-x86_64 and the amd64 image. The arm64
# guest also needs UEFI firmware from the host's QEMU install. HOPLON_VM_IMAGE_URL
# overrides the image.
resolve_host_arch() {
  local host_arch
  host_arch="$(uname -m)"
  case "$host_arch" in
    arm64 | aarch64)
      QEMU_BIN="qemu-system-aarch64"
      IMAGE_URL="${HOPLON_VM_IMAGE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2}"
      ;;
    x86_64 | amd64)
      QEMU_BIN="qemu-system-x86_64"
      IMAGE_URL="${HOPLON_VM_IMAGE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2}"
      ;;
    *)
      die "unsupported host architecture: $host_arch (need x86_64 or arm64)"
      ;;
  esac
}

# Resolve the accelerator and the matching -cpu value. HOPLON_VM_ACCEL wins;
# otherwise pick the native accelerator for this host, falling back to tcg
# software emulation when none is usable. Sets VM_ACCEL and VM_CPU.
resolve_accel() {
  if [ -n "${HOPLON_VM_ACCEL:-}" ]; then
    VM_ACCEL="$HOPLON_VM_ACCEL"
  else
    case "$(uname -s)" in
      Linux)
        if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
          VM_ACCEL="kvm"
        else
          VM_ACCEL="tcg"
        fi
        ;;
      Darwin) VM_ACCEL="hvf" ;;
      MSYS* | MINGW* | CYGWIN*) VM_ACCEL="whpx" ;;
      *) VM_ACCEL="tcg" ;;
    esac
  fi

  case "$VM_ACCEL" in
    kvm | hvf) VM_CPU="host" ;;
    whpx | tcg) VM_CPU="max" ;;
    *) VM_CPU="max" ;;
  esac
}

# Verify the resolved accelerator. An explicitly requested accelerator that is
# unavailable is fatal; the automatic tcg fallback never is, it only warns that
# emulation is slow.
check_accel() {
  case "$VM_ACCEL" in
    kvm)
      [ -e /dev/kvm ] || die "HOPLON_VM_ACCEL=kvm but /dev/kvm is absent"
      if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
        die "HOPLON_VM_ACCEL=kvm but /dev/kvm is not writable by $(id -un)"
      fi
      ;;
    hvf)
      [ "$(uname -s)" = "Darwin" ] || die "HOPLON_VM_ACCEL=hvf requires macOS (Darwin)"
      ;;
    whpx)
      case "$(uname -s)" in
        MSYS* | MINGW* | CYGWIN*) ;;
        *) die "HOPLON_VM_ACCEL=whpx requires Windows (MSYS/MINGW/Cygwin)" ;;
      esac
      ;;
    tcg)
      warn "using tcg software emulation; the guest will be slow (set HOPLON_VM_ACCEL or enable a hardware accelerator)"
      ;;
    *)
      die "HOPLON_VM_ACCEL must be kvm, hvf, whpx, or tcg (got: '$VM_ACCEL')"
      ;;
  esac
}

# Reject a value unless it is a non-negative decimal integer.
require_uint() {
  local name="$1" value="$2"
  case "$value" in
    '' | *[!0-9]*) die "$name must be a decimal integer (got: '$value')" ;;
  esac
}

# Validate operator-tunable environment before any value reaches qemu or the
# cloud-init template. A comma in HOPLON_VM_SSH_PORT would inject extra hostfwd
# rules into the -nic argument, and a newline in HOPLON_REPO_URL or
# HOPLON_VM_SHARE_TAG would break out of the user-data YAML and could add a
# guest-root runcmd. Reject bad values up front with a clear message.
validate_env() {
  require_uint HOPLON_VM_RAM "$VM_RAM"
  [ "$VM_RAM" -gt 0 ] || die "HOPLON_VM_RAM must be greater than 0 (got: '$VM_RAM')"

  require_uint HOPLON_VM_CPUS "$VM_CPUS"
  [ "$VM_CPUS" -gt 0 ] || die "HOPLON_VM_CPUS must be greater than 0 (got: '$VM_CPUS')"

  require_uint HOPLON_VM_SSH_TIMEOUT "$VM_SSH_TIMEOUT"
  [ "$VM_SSH_TIMEOUT" -gt 0 ] ||
    die "HOPLON_VM_SSH_TIMEOUT must be greater than 0 (got: '$VM_SSH_TIMEOUT')"

  require_uint HOPLON_VM_SSH_PORT "$VM_SSH_PORT"
  [ "$VM_SSH_PORT" -ge 1 ] && [ "$VM_SSH_PORT" -le 65535 ] ||
    die "HOPLON_VM_SSH_PORT must be an integer between 1 and 65535 (got: '$VM_SSH_PORT')"

  [[ "$VM_DISK" =~ ^[0-9]+[GgMm]$ ]] ||
    die "HOPLON_VM_DISK must look like 20G or 512M (got: '$VM_DISK')"

  case "$HOPLON_REPO_URL" in
    *[[:cntrl:]]*) die "HOPLON_REPO_URL must not contain control characters or newlines" ;;
  esac
  [[ "$HOPLON_REPO_URL" =~ ^(https|git)://[^[:space:]]+$ ]] ||
    die "HOPLON_REPO_URL must be an https:// or git:// URL without whitespace (got: '$HOPLON_REPO_URL')"

  case "$VM_SHARE_TAG" in
    '' | *[!A-Za-z0-9._-]*)
      die "HOPLON_VM_SHARE_TAG must be non-empty and match [A-Za-z0-9._-]+ (got: '$VM_SHARE_TAG')"
      ;;
  esac

  # A comma is the QEMU option separator, so a comma inside HOPLON_VM_SHARE
  # would inject extra -virtfs options (for example a second path=/ that shares
  # the host root). Reject it rather than try to escape it.
  case "$VM_SHARE" in
    *,*) die "HOPLON_VM_SHARE must not contain a comma (got: '$VM_SHARE')" ;;
  esac

  # HOPLON_VM_IMAGE_URL feeds a curl fetch and a basename, so keep it a plain
  # http(s), file, or absolute-path URL.
  if [ -n "${HOPLON_VM_IMAGE_URL:-}" ]; then
    case "$HOPLON_VM_IMAGE_URL" in
      *[[:space:]]* | *\"* | *\'* | *\`*)
        die "HOPLON_VM_IMAGE_URL must not contain whitespace or quotes"
        ;;
      http://* | https://* | file://* | /*) : ;;
      *)
        die "HOPLON_VM_IMAGE_URL must be an http(s), file, or absolute-path URL (got: '$HOPLON_VM_IMAGE_URL')"
        ;;
    esac
  fi
}

# Return success when canonical path $1 is $2 itself or lies beneath it.
path_within() {
  local child="$1" parent="${2%/}"
  [ -n "$parent" ] || return 0
  [ "$child" = "$parent" ] && return 0
  case "$child/" in
    "$parent"/*) return 0 ;;
  esac
  return 1
}

# Refuse to expose HOPLON_HOME (or a directory containing it) to the guest over
# virtio-9p unless the operator opts in. The repo carries .env with live API
# keys plus home/ and vm/ state, none of which the guest should read.
check_share_safety() {
  [ -n "$VM_SHARE" ] || return 0
  local share_real home_real leak
  share_real="$(cd "$VM_SHARE" > /dev/null 2>&1 && pwd -P)" ||
    die "cannot resolve HOPLON_VM_SHARE: $VM_SHARE"
  home_real="$(cd "$HOPLON_HOME" > /dev/null 2>&1 && pwd -P)" ||
    die "cannot resolve HOPLON_HOME: $HOPLON_HOME"

  leak=0
  path_within "$share_real" "$home_real" && leak=1
  path_within "$home_real" "$share_real" && leak=1
  [ "$leak" -eq 1 ] || return 0

  if [ "${HOPLON_VM_SHARE_ALLOW:-0}" = "1" ]; then
    warn "HOPLON_VM_SHARE_ALLOW=1: exposing $share_real, which overlaps HOPLON_HOME, to the guest"
    return 0
  fi

  warn "refusing to share $share_real: it overlaps HOPLON_HOME ($home_real)"
  warn "the guest would be able to read host material such as:"
  warn "  $home_real/.env    (live API keys)"
  warn "  $home_real/home/   (isolated home and caches)"
  warn "  $home_real/vm/     (VM disk, seed, and SSH key)"
  die "set HOPLON_VM_SHARE_ALLOW=1 to override, or point HOPLON_VM_SHARE outside HOPLON_HOME"
}

# Print the recorded PID, or return non-zero when there is none.
vm_pid() {
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2> /dev/null || true)"
  [ -n "$pid" ] || return 1
  printf '%s' "$pid"
}

vm_running() {
  local pid
  pid="$(vm_pid)" || return 1
  kill -0 "$pid" 2> /dev/null || return 1
  return 0
}

# Resolve the public key to authorize and the private key ssh should use.
# Sets SSH_KEY and SSH_KEY_PUB.
resolve_ssh_key() {
  local want="${HOPLON_VM_SSH_KEY:-}"
  local priv="" pub=""

  if [ -n "$want" ]; then
    if [ -f "$want.pub" ]; then
      pub="$want.pub"
      priv="$want"
    elif [ -f "$want" ]; then
      case "$want" in
        *.pub)
          pub="$want"
          priv="${want%.pub}"
          ;;
        *)
          priv="$want"
          pub="$VM_DIR/id_ed25519.pub"
          ssh-keygen -y -f "$priv" > "$pub" 2> /dev/null || die "cannot read private key: $priv"
          ;;
      esac
    else
      die "HOPLON_VM_SSH_KEY not found: $want"
    fi
  fi

  if [ -z "$pub" ] && [ -f "${HOME:-}/.ssh/id_ed25519.pub" ]; then
    pub="${HOME}/.ssh/id_ed25519.pub"
    priv="${HOME}/.ssh/id_ed25519"
  fi

  if [ -z "$pub" ]; then
    priv="$VM_DIR/id_ed25519"
    pub="$VM_DIR/id_ed25519.pub"
    if [ ! -f "$priv" ]; then
      log "generating dedicated VM SSH key: $priv"
      mkdir -p "$VM_DIR"
      ssh-keygen -t ed25519 -N '' -C hoplon-vm -f "$priv" > /dev/null
    fi
  fi

  [ -f "$pub" ] || die "public key not found: $pub"
  SSH_KEY="$priv"
  SSH_KEY_PUB="$pub"
}

# Fetch SHA512SUMS for the base image and verify a downloaded file. Missing
# checksum data is a warning, never a hard stop; a mismatch is fatal.
verify_image() {
  local file="$1"
  local base sums_text line want got
  local -a sha_tool=()
  base="$(basename "$IMAGE_URL")"
  if command -v sha512sum > /dev/null 2>&1; then
    sha_tool=(sha512sum)
  elif command -v shasum > /dev/null 2>&1; then
    sha_tool=(shasum -a 512)
  else
    if [ "${HOPLON_VM_VERIFY:-warn}" = "strict" ]; then
      warn "no sha512 tool (need sha512sum or shasum) and HOPLON_VM_VERIFY=strict"
      return 1
    fi
    warn "no sha512 tool (need sha512sum or shasum); skipping image verification"
    return 0
  fi

  sums_text="$(curl -fsSL --retry 2 "${IMAGE_URL%/*}/SHA512SUMS" 2> /dev/null || true)"
  if [ -z "$sums_text" ]; then
    if [ "${HOPLON_VM_VERIFY:-warn}" = "strict" ]; then
      warn "could not fetch SHA512SUMS and HOPLON_VM_VERIFY=strict"
      return 1
    fi
    warn "could not fetch SHA512SUMS; skipping image verification"
    return 0
  fi

  line=""
  while IFS= read -r entry; do
    case "$entry" in
      *" $base")
        line="$entry"
        break
        ;;
    esac
  done <<< "$sums_text"
  if [ -z "$line" ]; then
    if [ "${HOPLON_VM_VERIFY:-warn}" = "strict" ]; then
      warn "no checksum listed for $base and HOPLON_VM_VERIFY=strict"
      return 1
    fi
    warn "no checksum listed for $base; skipping image verification"
    return 0
  fi

  want="${line%% *}"
  got="$("${sha_tool[@]}" "$file")"
  got="${got%% *}"
  [ "$want" = "$got" ] || {
    warn "checksum mismatch for $base"
    return 1
  }
  log "image checksum verified"
  return 0
}

# Render vm/cloud-init/user-data.yaml into $SEED_DIR/user-data with the operator
# key and the requested tools level substituted in.
render_user_data() {
  local template out pubkey tools repo tag
  template="$CLOUD_INIT_DIR/user-data.yaml"
  [ -f "$template" ] || die "missing template: $template"
  out="$SEED_DIR/user-data"

  pubkey="$(tr -d '\r\n' < "$SSH_KEY_PUB")"
  [ -n "$pubkey" ] || die "public key is empty: $SSH_KEY_PUB"
  case "$pubkey" in
    *\"* | *\\*) die "public key contains characters unsafe for YAML: $SSH_KEY_PUB" ;;
  esac

  tools="$VM_TOOLS"
  repo="$HOPLON_REPO_URL"
  if [ -n "$VM_SHARE" ]; then
    tag="$VM_SHARE_TAG"
  else
    tag=""
  fi

  template="$(cat "$template")"
  template="${template//__HOPLON_SSH_PUBKEY__/$pubkey}"
  template="${template//__HOPLON_VM_TOOLS__/$tools}"
  template="${template//__HOPLON_REPO_URL__/$repo}"
  template="${template//__HOPLON_VM_SHARE_TAG__/$tag}"
  printf '%s\n' "$template" > "$out"
}

# Stage user-data, meta-data, and (when present) the host toolchain installer,
# then build the NoCloud seed ISO.
build_seed() {
  need_cmd xorriso
  mkdir -p "$SEED_DIR"
  render_user_data
  install -m 0644 "$CLOUD_INIT_DIR/meta-data.yaml" "$SEED_DIR/meta-data"

  if [ -f "$HOPLON_HOME/scripts/toolchain.sh" ]; then
    install -m 0755 "$HOPLON_HOME/scripts/toolchain.sh" "$SEED_DIR/toolchain.sh"
  else
    warn "scripts/toolchain.sh not found; the guest falls back to a minimal install"
    rm -f "$SEED_DIR/toolchain.sh"
  fi

  rm -f "$SEED_ISO"
  xorriso -as mkisofs -volid cidata -joliet -rock \
    -o "$SEED_ISO" "$SEED_DIR" > /dev/null
  log "built seed ISO: $SEED_ISO"
}

cmd_create() {
  local force=0
  case "${1:-}" in
    "") ;;
    --force | -f) force=1 ;;
    *) die "create: unknown argument: $1" ;;
  esac
  case "$VM_TOOLS" in
    none | base | core | full) ;;
    *) die "HOPLON_VM_TOOLS must be none, base, core, or full (got: $VM_TOOLS)" ;;
  esac

  need_cmd curl
  need_cmd qemu-img
  need_cmd "$QEMU_BIN"
  need_cmd xorriso
  need_cmd ssh-keygen

  if [ -e "$DISK" ] && [ "$force" -ne 1 ]; then
    die "disk already exists: $DISK (use '$0 create --force' to rebuild)"
  fi

  mkdir -p "$VM_DIR" "$BASE_CACHE_DIR" "$SEED_DIR"

  local base
  base="$BASE_CACHE_DIR/$(basename "$IMAGE_URL")"
  if [ ! -f "$base" ]; then
    log "downloading Debian cloud image (about 350 MiB): $IMAGE_URL"
    curl -fL --retry 3 --retry-delay 2 -o "$base.part" "$IMAGE_URL" ||
      die "image download failed: $IMAGE_URL"
    verify_image "$base.part" || die "refusing to use $base.part"
    mv -f "$base.part" "$base"
  else
    log "using cached base image: $base"
  fi

  log "creating disk: $DISK"
  cp -f "$base" "$DISK"
  qemu-img resize "$DISK" "$VM_DISK" > /dev/null
  log "disk resized to $VM_DISK"

  resolve_ssh_key
  printf '%s\n' "$SSH_KEY" > "$KEY_RECORD"

  build_seed

  printf '\nvm: create complete\n'
  printf '  disk   %s\n' "$DISK"
  printf '  seed   %s\n' "$SEED_ISO"
  printf '  key    %s\n' "$SSH_KEY_PUB"
  printf '\nNext steps:\n'
  printf '  %s start   # boot the VM\n' "$0"
  printf '  %s ssh     # wait for sshd and connect\n' "$0"
}

cmd_start() {
  resolve_accel
  check_accel
  need_cmd "$QEMU_BIN"
  [ -f "$DISK" ] || die "no disk found; run: $0 create"
  [ -f "$SEED_ISO" ] || die "no seed ISO found; run: $0 create"
  if vm_running; then
    die "VM already running (pid $(vm_pid)); run: $0 stop"
  fi

  local -a qemu
  qemu=(
    "$QEMU_BIN"
    -name hoplon-vm
    -accel "$VM_ACCEL"
    -cpu "$VM_CPU"
    -smp "$VM_CPUS"
    -m "$VM_RAM"
    -drive "file=$DISK,if=virtio,format=qcow2"
    -cdrom "$SEED_ISO"
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${VM_SSH_PORT}-:22"
    -display none
    -daemonize
    -pidfile "$PID_FILE"
    -serial "file:$LOG_FILE"
  )
  if [ -n "$VM_SHARE" ]; then
    [ -d "$VM_SHARE" ] || die "HOPLON_VM_SHARE is not a directory: $VM_SHARE"
    check_share_safety
    qemu+=(-virtfs "local,path=$VM_SHARE,mount_tag=$VM_SHARE_TAG,security_model=none,readonly=on")
  fi

  : > "$LOG_FILE"
  log "booting VM (accel=$VM_ACCEL cpu=$VM_CPU cpus=$VM_CPUS ram=${VM_RAM}MiB ssh=127.0.0.1:$VM_SSH_PORT)"
  "${qemu[@]}"
  sleep 1
  if vm_running; then
    log "VM running (pid $(vm_pid))"
    printf '  connect: %s ssh\n' "$0"
  else
    die "VM failed to start; see $LOG_FILE"
  fi
}

cmd_stop() {
  if ! vm_running; then
    log "VM is not running"
    rm -f "$PID_FILE"
    return 0
  fi

  local pid waited
  pid="$(vm_pid)"
  log "stopping VM (pid $pid)"
  kill -TERM "$pid" 2> /dev/null || true

  waited=0
  while [ "$waited" -lt 30 ]; do
    kill -0 "$pid" 2> /dev/null || break
    sleep 0.5
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2> /dev/null; then
    warn "VM did not stop on SIGTERM; sending SIGKILL"
    kill -KILL "$pid" 2> /dev/null || true
    sleep 1
  fi
  rm -f "$PID_FILE"
  log "VM stopped"
}

cmd_status() {
  resolve_accel
  check_accel
  local state
  if vm_running; then
    state="running (pid $(vm_pid))"
  else
    state="stopped"
  fi
  printf 'hoplon vm: %s\n' "$state"
  printf '  state dir     %s\n' "$VM_DIR"
  printf '  config        tools=%s cpus=%s ram=%sMiB disk=%s port=%s\n' \
    "$VM_TOOLS" "$VM_CPUS" "$VM_RAM" "$VM_DISK" "$VM_SSH_PORT"
  printf '  accelerator   %s (cpu %s, %s)\n' "$VM_ACCEL" "$VM_CPU" "$QEMU_BIN"
  printf '  image         %s\n' "$IMAGE_URL"

  if [ -f "$DISK" ]; then
    printf '  disk          %s\n' "$DISK"
    if command -v qemu-img > /dev/null 2>&1; then
      local dinfo
      dinfo="$(qemu-img info "$DISK" 2> /dev/null | grep 'virtual size' || true)"
      [ -n "$dinfo" ] && printf '                %s\n' "$dinfo"
    fi
  else
    printf '  disk          missing\n'
  fi

  if [ -f "$SEED_ISO" ]; then
    printf '  seed iso      %s\n' "$SEED_ISO"
  else
    printf '  seed iso      missing\n'
  fi

  if [ -f "$KEY_RECORD" ]; then
    printf '  ssh key       %s\n' "$(cat "$KEY_RECORD")"
  else
    printf '  ssh key       unresolved (run create)\n'
  fi

  vm_running
}

# Return success when sshd accepts the key on the forwarded port.
vm_ssh_probe() {
  local key="$1"
  ssh -p "$VM_SSH_PORT" -i "$key" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ConnectTimeout=5 \
    hoplon@127.0.0.1 true > /dev/null 2>&1
}

# Resolve the private key to use for the guest connection into VM_SSH_KEY_PATH.
# Prefers the path recorded at create time, else resolves the host or a
# generated key. Kept as a global so the resolver's log lines are not captured.
vm_private_key() {
  if [ -f "$KEY_RECORD" ]; then
    VM_SSH_KEY_PATH="$(cat "$KEY_RECORD")"
  else
    resolve_ssh_key
    VM_SSH_KEY_PATH="$SSH_KEY"
  fi
}

# Wait until sshd accepts the key on the forwarded port. $1 is the private key.
wait_for_ssh() {
  local key="$1"
  log "waiting for sshd on 127.0.0.1:$VM_SSH_PORT (up to ${VM_SSH_TIMEOUT}s)"
  local deadline ok
  deadline=$((SECONDS + VM_SSH_TIMEOUT))
  ok=0
  while [ "$SECONDS" -lt "$deadline" ]; do
    if vm_ssh_probe "$key"; then
      ok=1
      break
    fi
    sleep 2
  done
  [ "$ok" -eq 1 ] || die "timed out waiting for SSH on port $VM_SSH_PORT; see $LOG_FILE"
  log "ssh ready"
}

# Open an SSH session in the guest. Extra arguments become the remote command.
vm_ssh_session() {
  local key="$1"
  shift
  exec ssh -p "$VM_SSH_PORT" -i "$key" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ConnectTimeout=10 \
    hoplon@127.0.0.1 "$@"
}

cmd_ssh() {
  need_cmd ssh
  [ "${1:-}" = "--" ] && shift
  [ -f "$DISK" ] || die "no VM found; run: $0 create"
  vm_running || die "VM is not running; run: $0 start"

  vm_private_key
  [ -f "$VM_SSH_KEY_PATH" ] || die "SSH private key not found: $VM_SSH_KEY_PATH"

  wait_for_ssh "$VM_SSH_KEY_PATH"
  vm_ssh_session "$VM_SSH_KEY_PATH" "$@"
}

# `console`: create if needed, boot, then run the Hoplon TUI in the guest. A
# first boot is still provisioning cloud-init, so if Hoplon is not on PATH yet
# say so and stop; open a plain shell only when --shell is passed.
cmd_console() {
  need_cmd ssh
  local want_shell=0
  case "${1:-}" in
    --shell | -s)
      want_shell=1
      shift
      ;;
  esac
  [ -f "$DISK" ] || die "no VM found; run: $0 create"
  vm_running || die "VM is not running; run: $0 start"

  vm_private_key
  [ -f "$VM_SSH_KEY_PATH" ] || die "SSH private key not found: $VM_SSH_KEY_PATH"

  wait_for_ssh "$VM_SSH_KEY_PATH"

  if [ "$want_shell" -eq 1 ]; then
    [ "${1:-}" = "--" ] && shift
    vm_ssh_session "$VM_SSH_KEY_PATH" "$@"
  fi

  if ! ssh -p "$VM_SSH_PORT" -i "$VM_SSH_KEY_PATH" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ConnectTimeout=10 \
    hoplon@127.0.0.1 'command -v hoplon' > /dev/null 2>&1; then
    warn "the guest is still provisioning: the hoplon command is not on PATH yet"
    warn "wait a minute and rerun, or run hoplon-tool inside the guest"
    warn "for a plain shell now, run: $0 console --shell"
    exit 1
  fi

  exec ssh -t -p "$VM_SSH_PORT" -i "$VM_SSH_KEY_PATH" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ConnectTimeout=10 \
    hoplon@127.0.0.1 hoplon "$@"
}

cmd_destroy() {
  case "${1:-}" in
    "") ;;
    --force | -f) ;;
    *) die "destroy: unknown argument: $1" ;;
  esac

  cmd_stop
  log "removing VM state under $VM_DIR"
  rm -f "$DISK" "$SEED_ISO" "$PID_FILE" "$LOG_FILE" "$KNOWN_HOSTS" "$KEY_RECORD"
  rm -rf "$SEED_DIR"
  # Only a key generated by vm.sh is removed; a host key is never touched.
  rm -f "$VM_DIR/id_ed25519" "$VM_DIR/id_ed25519.pub"
  log "destroy complete (base image cache kept at $BASE_CACHE_DIR)"
}

cmd_help() {
  cat << 'EOF'
Hoplon QEMU VM backend.

Usage:
  vm.sh                    create if needed, boot, and open a shell (default)
  vm.sh run [-- cmd...]    same as the default: open a shell in the guest
  vm.sh console [args...]  create if needed, boot, then run the Hoplon console
                           inside the guest; --shell opens a shell instead
  vm.sh create [--force]   download the Debian cloud image, build disk.qcow2,
                           render vm/cloud-init into seed.iso
  vm.sh start              boot the VM (hardware or software acceleration)
  vm.sh stop               power the VM off
  vm.sh status             show VM state (exit 0 when running, 1 when stopped)
  vm.sh ssh [-- cmd...]    wait for sshd, then open an SSH session
  vm.sh destroy            remove the VM disk, seed, logs, and generated key
  vm.sh help

Provisioning is controlled by HOPLON_VM_TOOLS:
  none   base packages only; skips the toolchain and the Hoplon install
  base   minimal guest; install Hoplon and hoplon-tool for on-demand tools (default)
  core   run scripts/toolchain.sh --core, then install Hoplon (preloaded)
  full   run scripts/toolchain.sh --full, then install Hoplon (preloaded)

With base, the guest fetches a tool only when it is needed: run
`hoplon-tool install NAME` in the guest, or let the missing-command hook do it.

See the header of this script for the full environment reference.
EOF
}

main() {
  local cmd="${1:-run}"
  if [ "$#" -gt 0 ]; then
    shift
  fi
  case "$cmd" in
    run)
      # Default path: ensure the guest exists, boot it, and open a shell.
      resolve_host_arch
      validate_env
      [ -f "$DISK" ] || cmd_create
      cmd_start
      cmd_ssh "$@"
      ;;
    console)
      # Same as run, but lands in the Hoplon console instead of a shell.
      resolve_host_arch
      validate_env
      [ -f "$DISK" ] || cmd_create
      cmd_start
      cmd_console "$@"
      ;;
    create)
      resolve_host_arch
      validate_env
      cmd_create "$@"
      ;;
    start)
      resolve_host_arch
      validate_env
      cmd_start "$@"
      ;;
    stop) cmd_stop "$@" ;;
    status)
      resolve_host_arch
      validate_env
      cmd_status "$@"
      ;;
    ssh)
      validate_env
      cmd_ssh "$@"
      ;;
    destroy) cmd_destroy "$@" ;;
    help | -h | --help) cmd_help ;;
    *)
      warn "unknown subcommand: $cmd"
      cmd_help >&2
      exit 2
      ;;
  esac
}

main "$@"
