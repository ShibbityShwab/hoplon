# QEMU guest

`HOPLON_ISOLATION=vm` runs the whole stack inside a Debian QEMU guest with its
own kernel, filesystem, and user. Nothing the guest does reaches the host OS.
This is the middle tier: stronger than the isolated host tier, lighter than the
[NixOS guest](nixos-vm.md). QEMU is the one virtualization layer present on
Linux, macOS, and Windows, so this is the single cross-platform isolation model.

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

```bash
scripts/vm.sh create     # download the Debian cloud image, build the seed
scripts/vm.sh start      # boot it headless
scripts/vm.sh ssh        # open the guest (waits for SSH on 127.0.0.1:2222)
scripts/vm.sh status     # state, disk, pid
scripts/vm.sh stop       # shut it down
scripts/vm.sh destroy    # remove the VM state
```

`hoplon` with `HOPLON_ISOLATION=vm` delegates to `scripts/vm.sh`.

## What the guest gets

cloud-init provisions the guest on first boot: it installs the base packages,
runs `scripts/toolchain.sh` when `HOPLON_VM_TOOLS` is `core` or `full`, and
installs Hoplon so the `hoplon` command exists for the `hoplon` user. `core` is
the modest base set; `full` adds the wider red-team toolset. Set
`HOPLON_VM_TOOLS=none` for a bare guest (no toolchain, no Hoplon install).

## Knobs

| Variable | Default | Effect |
| --- | --- | --- |
| `HOPLON_VM_TOOLS` | `core` | toolchain in the guest: none, core, or full |
| `HOPLON_VM_RAM` | `4096` | guest memory in MiB |
| `HOPLON_VM_CPUS` | `4` | guest vCPUs |
| `HOPLON_VM_ACCEL` | auto by host | QEMU accelerator: kvm, hvf, whpx, or tcg |
| `HOPLON_VM_DISK` | `20G` | guest disk size |
| `HOPLON_VM_SSH_KEY` | host `~/.ssh/id_ed25519.pub` | key authorized in the guest |
| `HOPLON_VM_SSH_PORT` | `2222` | host port forwarded to guest port 22 |
| `HOPLON_VM_SHARE` | none | directory shared in over virtio-9p |
| `HOPLON_VM_IMAGE_URL` | Debian bookworm latest for the host arch | base cloud image to download |

## Tradeoff

The Debian guest provisions quickly and is easy to change live, but it drifts
with the cloud image and the toolchain script. For a fully pinned, reproducible
guest use the [NixOS guest](nixos-vm.md).
