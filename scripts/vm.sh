#!/usr/bin/env bash
# =============================================================================
# Hoplon QEMU/KVM VM backend.
#
# Runs Hoplon inside a Debian bookworm cloud image with its own kernel, fully
# separated from the host. State lives under $HOPLON_HOME/vm: the qcow2 disk,
# the NoCloud seed ISO, the pid file, the serial log, and the SSH key.
#
# Usage:
#   vm.sh create [--force]   download the base image, copy and resize disk.qcow2,
#                            render vm/cloud-init into seed.iso
#   vm.sh start              boot the VM under KVM
#   vm.sh stop               power the VM off (SIGTERM, then SIGKILL)
#   vm.sh status             show VM state
#   vm.sh ssh [-- cmd...]    wait for sshd, then open an SSH session
#   vm.sh destroy            remove the VM disk, seed, logs, and generated key
#   vm.sh help
#
# Environment:
#   HOPLON_HOME            repo root (defaults to this script's parent)
#   HOPLON_VM_TOOLS        none | core | full   (default core)
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
#   HOPLON_VM_IMAGE_URL    base qcow2 URL (default Debian bookworm genericcloud)
# =============================================================================
set -euo pipefail

# State written below (disk.qcow2, seed.iso, vm.log, ssh_private_key_path) can
# include key material and image contents, so create it owner-only. Commands
# that install files explicitly (install -m ...) still set their own mode.
umask 077

HOPLON_HOME="${HOPLON_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd -P)}"
export HOPLON_HOME

# Optional local settings. Matches scripts/install.sh: values in .env win over
# the ambient environment.
if [ -f "$HOPLON_HOME/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$HOPLON_HOME/.env"
  set +a
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

VM_TOOLS="${HOPLON_VM_TOOLS:-core}"
VM_RAM="${HOPLON_VM_RAM:-4096}"
VM_CPUS="${HOPLON_VM_CPUS:-4}"
VM_DISK="${HOPLON_VM_DISK:-20G}"
VM_SSH_PORT="${HOPLON_VM_SSH_PORT:-2222}"
VM_SSH_TIMEOUT="${HOPLON_VM_SSH_TIMEOUT:-300}"
VM_SHARE="${HOPLON_VM_SHARE:-}"
VM_SHARE_TAG="${HOPLON_VM_SHARE_TAG:-engagements}"
HOPLON_REPO_URL="${HOPLON_REPO_URL:-https://github.com/ShibbityShwab/hoplon}"
IMAGE_URL="${HOPLON_VM_IMAGE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2}"

# SSH key material resolved by resolve_ssh_key.
SSH_KEY=""
SSH_KEY_PUB=""

log() { printf 'vm: %s\n' "$*"; }
warn() { printf 'vm: %s\n' "$*" >&2; }
die() {
  printf 'vm: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" > /dev/null 2>&1 || die "missing required command: $1"
}

check_kvm() {
  [ -e /dev/kvm ] || die "/dev/kvm is absent; KVM acceleration is unavailable"
  [ -r /dev/kvm ] && [ -w /dev/kvm ] || die "/dev/kvm is not writable by $(id -un)"
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
  base="$(basename "$IMAGE_URL")"
  if ! command -v sha512sum > /dev/null 2>&1; then
    warn "sha512sum unavailable; skipping image verification"
    return 0
  fi

  sums_text="$(curl -fsSL --retry 2 "${IMAGE_URL%/*}/SHA512SUMS" 2> /dev/null || true)"
  if [ -z "$sums_text" ]; then
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
    warn "no checksum listed for $base; skipping image verification"
    return 0
  fi

  want="${line%% *}"
  got="$(sha512sum "$file")"
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
    none | core | full) ;;
    *) die "HOPLON_VM_TOOLS must be none, core, or full (got: $VM_TOOLS)" ;;
  esac

  need_cmd curl
  need_cmd qemu-img
  need_cmd qemu-system-x86_64
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
  need_cmd qemu-system-x86_64
  check_kvm
  [ -f "$DISK" ] || die "no disk found; run: $0 create"
  [ -f "$SEED_ISO" ] || die "no seed ISO found; run: $0 create"
  if vm_running; then
    die "VM already running (pid $(vm_pid)); run: $0 stop"
  fi

  local -a qemu
  qemu=(
    qemu-system-x86_64
    -name hoplon-vm
    -accel kvm
    -cpu host
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
  log "booting VM (cpus=$VM_CPUS ram=${VM_RAM}MiB ssh=127.0.0.1:$VM_SSH_PORT)"
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

cmd_ssh() {
  need_cmd ssh
  [ "${1:-}" = "--" ] && shift
  [ -f "$DISK" ] || die "no VM found; run: $0 create"
  vm_running || die "VM is not running; run: $0 start"

  local key
  if [ -f "$KEY_RECORD" ]; then
    key="$(cat "$KEY_RECORD")"
  else
    resolve_ssh_key
    key="$SSH_KEY"
  fi
  [ -f "$key" ] || die "SSH private key not found: $key"

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

  exec ssh -p "$VM_SSH_PORT" -i "$key" \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ConnectTimeout=10 \
    hoplon@127.0.0.1 "$@"
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
Hoplon QEMU/KVM VM backend.

Usage:
  vm.sh create [--force]   download the Debian cloud image, build disk.qcow2,
                           render vm/cloud-init into seed.iso
  vm.sh start              boot the VM under KVM
  vm.sh stop               power the VM off
  vm.sh status             show VM state (exit 0 when running, 1 when stopped)
  vm.sh ssh [-- cmd...]    wait for sshd, then open an SSH session
  vm.sh destroy            remove the VM disk, seed, logs, and generated key
  vm.sh help

Provisioning is controlled by HOPLON_VM_TOOLS:
  none   base packages only; skips the toolchain and the Hoplon install
  core   run scripts/toolchain.sh --core, then install Hoplon   (default)
  full   run scripts/toolchain.sh --full, then install Hoplon

See the header of this script for the full environment reference.
EOF
}

main() {
  local cmd="${1:-help}"
  if [ "$#" -gt 0 ]; then
    shift
  fi
  case "$cmd" in
    create)
      validate_env
      cmd_create "$@"
      ;;
    start)
      validate_env
      cmd_start "$@"
      ;;
    stop) cmd_stop "$@" ;;
    status)
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
