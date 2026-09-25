# QEMU guest

`HOPLON_ISOLATION=vm` runs the whole stack inside a Debian QEMU/KVM guest with
its own kernel, filesystem, and user. Nothing the guest does reaches the host OS.
This is the middle tier: stronger than the host sandbox, lighter than the
[NixOS guest](nixos-vm.md).

## Create and run

```bash
scripts/vm.sh create     # download the Debian cloud image, build the seed
scripts/vm.sh start      # boot it headless with KVM
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
| `HOPLON_VM_DISK` | `20G` | guest disk size |
| `HOPLON_VM_SSH_KEY` | host `~/.ssh/id_ed25519.pub` | key authorized in the guest |
| `HOPLON_VM_SSH_PORT` | `2222` | host port forwarded to guest port 22 |
| `HOPLON_VM_SHARE` | none | directory shared in over virtio-9p |
| `HOPLON_VM_IMAGE_URL` | Debian bookworm latest | base cloud image to download |

## Tradeoff

The Debian guest provisions quickly and is easy to change live, but it drifts
with the cloud image and the toolchain script. For a fully pinned, reproducible
guest use the [NixOS guest](nixos-vm.md).
