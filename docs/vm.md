# QEMU guest

`HOPLON_ISOLATION=vm` (or the one-word `hoplon vm`) runs the whole stack inside
a Debian QEMU guest with its own kernel, filesystem, and user. Nothing the guest
does reaches the host OS.
This is the guest tier: the `host` tier shares the host kernel, while this guest
has its own. QEMU is the one virtualization layer present on Linux, macOS, and
Windows, so this is the single cross-platform isolation model.

## Platform support

| Host | QEMU binary | Accelerator | Notes |
| --- | --- | --- | --- |
| Linux x86_64 | `qemu-system-x86_64` | KVM if `/dev/kvm` is usable, else TCG | install QEMU and xorriso |
| Linux arm64 | `qemu-system-aarch64` | KVM if `/dev/kvm` is usable, else TCG | also needs EDK2 UEFI firmware |
| macOS Intel (x86_64) | `qemu-system-x86_64` | HVF | install QEMU with Homebrew |
| macOS Apple Silicon (arm64) | `qemu-system-aarch64` | HVF | arm64 image and UEFI firmware from QEMU |
| Windows (MSYS/MINGW/Cygwin) | host-arch binary | WHPX, else TCG | WHPX needs the Windows Hypervisor Platform feature |
| Windows via WSL2 | `qemu-system-x86_64` | KVM with nested virtualization, else TCG | `--device /dev/kvm` when the distro exposes it |

The accelerator is chosen automatically. Override it with `HOPLON_VM_ACCEL`
(`kvm`, `hvf`, `whpx`, or `tcg`). An explicitly requested accelerator that is
unavailable fails immediately; an automatic fall to `tcg` warns, because
software emulation is slow.

## Create and run

`hoplon vm` is the shortest path: it creates the guest if it does not exist,
starts it if it is stopped, waits for SSH on 127.0.0.1:2222, and then runs the
Hoplon console inside the guest. It is the guest equivalent of
`HOPLON_ISOLATION=vm ./hoplon`, except it lands in the TUI rather than a shell.
If the first boot is still provisioning and `hoplon` is not on the guest PATH
yet, `vm.sh console` says so and stops; pass `--shell` for a plain shell.

```bash
hoplon vm                 # create if needed, boot, run the guest console
scripts/vm.sh console     # same thing from scripts/vm.sh
scripts/vm.sh             # create if needed, boot, then open a shell (default)
scripts/vm.sh run         # same as the default: open a shell
scripts/vm.sh create      # download the Debian cloud image, build the seed
scripts/vm.sh start       # boot it headless
scripts/vm.sh ssh         # open the guest (waits for SSH on 127.0.0.1:2222)
scripts/vm.sh status      # state, disk, pid
scripts/vm.sh stop        # shut it down
scripts/vm.sh destroy     # remove the VM state
```

Every command also runs through the launcher as
`HOPLON_ISOLATION=vm ./hoplon <subcommand>`. The `console` and `run` subcommands
accept extra arguments as the guest command; `console --shell` opens a shell
instead of the console.

## What the guest gets

cloud-init provisions the guest on first boot. The default mode is `base`: it
installs a minimal package set (`ca-certificates`, `curl`, `git`, `jq`,
`ripgrep`, `python3`, `python3-venv`, `python3-pip`, `pipx`, `unzip`, `xz-utils`,
`tmux`), clones and installs Hoplon, links `hoplon-tool` into
`/usr/local/bin`, and writes the on-demand shell hook to
`/etc/profile.d/hoplon-autotool.sh`. No red-team tool is fetched until it is
needed.

The guest clones `HOPLON_REPO_URL` (default the Hoplon GitHub repo) into
`/opt/hoplon` and installs it for the `hoplon` user, so it runs the remote
revision, not the host working tree. Local uncommitted changes do not reach the
guest. Point `HOPLON_REPO_URL` at a fork or another reachable clone to change
what the guest installs.

Set `HOPLON_VM_TOOLS=core` or `full` to preload instead: cloud-init runs
`scripts/toolchain.sh --core` or `--full` before installing Hoplon. `core` is
the modest base set; `full` adds the wider red-team toolset. Set
`HOPLON_VM_TOOLS=none` for a bare guest (no toolchain, no Hoplon install).

## Tools on demand

Inside the guest, `hoplon-tool` installs a tool only when it is needed:

| Command | Effect |
| --- | --- |
| `hoplon-tool list` | print every known tool name |
| `hoplon-tool install NAME [...]` | install exactly those tools |
| `hoplon-tool install base` | install the minimal core package set |
| `hoplon-tool install all` | install the full red-team toolset |
| `hoplon-tool known NAME` | exit 0 when NAME is a known tool |
| `hoplon-tool suggest NAME` | print the tool that provides NAME |
| `hoplon-tool status` | print which tools are already present |

The `/etc/profile.d/hoplon-autotool.sh` hook fires when the shell cannot find a
command. If the command is a known tool and `HOPLON_AUTO_INSTALL` is not `0`, it
installs the tool with `hoplon-tool` and runs the command. Otherwise it prints a
one-line hint. Set `HOPLON_AUTO_INSTALL=0` inside the guest to only suggest the
install command and never install automatically. See [Tooling](tooling.md).

## Knobs

| Variable | Default | Effect |
| --- | --- | --- |
| `HOPLON_VM_TOOLS` | `base` | toolchain in the guest: none, base, core, or full |
| `HOPLON_VM_RAM` | `4096` | guest memory in MiB |
| `HOPLON_VM_CPUS` | `4` | guest vCPUs |
| `HOPLON_VM_ACCEL` | auto by host | QEMU accelerator: kvm, hvf, whpx, or tcg |
| `HOPLON_VM_DISK` | `20G` | guest disk size |
| `HOPLON_VM_SSH_KEY` | host `~/.ssh/id_ed25519.pub`, else a generated `vm/id_ed25519` | key authorized in the guest |
| `HOPLON_VM_SSH_PORT` | `2222` | host port forwarded to guest port 22 |
| `HOPLON_VM_SSH_TIMEOUT` | `300` | seconds `scripts/vm.sh ssh` waits for sshd |
| `HOPLON_VM_SHARE` | none | directory exposed read-only over virtio-9p; a path inside `HOPLON_HOME` is refused unless `HOPLON_VM_SHARE_ALLOW=1` |
| `HOPLON_VM_SHARE_TAG` | `engagements` | 9p mount tag inside the guest |
| `HOPLON_VM_SHARE_ALLOW` | unset | set `1` to allow sharing a directory inside `HOPLON_HOME` |
| `HOPLON_VM_IMAGE_URL` | Debian bookworm latest for the host arch | base cloud image to download |
| `HOPLON_REPO_URL` | the Hoplon GitHub repo | repository cloud-init clones and installs in the guest |

## Tradeoff

The Debian guest provisions quickly and is easy to change live, but it drifts
with the cloud image and the toolchain script. Pin `HOPLON_VM_IMAGE_URL` and
rerun `scripts/toolchain.sh` on a fresh guest to keep it reproducible.

The default `base` guest stays small and fetches each tool over the network the
first time it is used, so the on-demand path needs connectivity at that moment.
`core` and `full` trade disk and boot time for a guest that is preloaded and
then works offline.
