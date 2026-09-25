# NixOS guest

`HOPLON_ISOLATION=nix` boots a declarative NixOS guest with its own kernel,
userspace, red-team toolchain, and Hoplon, built from pinned Nix inputs.
`flake.nix` is the source of truth, alongside `HOPLON_ISOLATION=vm` (a Debian
QEMU guest) and `host`.

## Install Nix

If `nix` is missing, `scripts/nix-vm.sh` prints this and exits non-zero:

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon     # multi-user
sh <(curl -L https://nixos.org/nix/install) --no-daemon  # single-user
```

Add `experimental-features = nix-command flakes` to `~/.config/nix/nix.conf`.
`/dev/kvm` enables acceleration; without it QEMU emulates and boot is slow.

## Build and boot

```bash
nix run .#vm        # build and boot under QEMU/KVM (serial console)
nix build .#qcow2   # build the disk image
scripts/nix-vm.sh build   # same, linking vm/nixos-qcow2
scripts/nix-vm.sh run     # same as nix run .#vm, with a nix check
nix run path:.#vm   # use path: when the flake files are untracked by git
```

`hoplon` with `HOPLON_ISOLATION=nix` delegates to `scripts/nix-vm.sh`, which
defaults to `run`.

Guest `hoplon-vm`: DHCP, firewall open on port 22 only, 4 vCPU, 4 GiB RAM, 30
GiB disk, and guest port 22 forwarded to `127.0.0.1:2222`.

## Log in

- Console: log in at the getty as `hoplon` with the initial password `hoplon`,
  then run `passwd`. This is the first-boot path; SSH password auth is off.
- SSH: key only. Pass `hoplonAuthorizedKeys` (default `[]`) by wrapping the
  flake:

```nix
{ inputs.hoplon.url = "path:/path/to/hoplon";
  outputs = { hoplon, ... }:
    hoplon.mkHoplon { hoplonAuthorizedKeys = [ "ssh-ed25519 AAAA... you@host" ]; }; }
```

Then `nix run ./my-hoplon#vm`, or edit the default in `flake.nix`.

## Toolchain

From nixpkgs `nixos-25.05`: nmap, netcat, masscan, nikto, whatweb, nuclei,
subfinder, httpx, ffuf, gobuster, amass, dnsrecon, thc-hydra, john, sqlmap,
netexec, bloodhound, samba, openldap, python3Packages.impacket, aircrack-ng,
metasploit, radare2, gdb, strace, ltrace, binutils, go, gcc, gnumake, python3,
pipx, git, jq, ripgrep, tmux, file, openssl, procps, unzip, zip, seclists,
wordlists. Full list: `nix/toolchain.nix`.

Omitted (absent): `bloodhound-ce` (classic `bloodhound` ships) and top-level
`impacket` (ships as `python3Packages.impacket`). nixpkgs `hydra` is the CI
server, so the cracker ships as `thc-hydra`; top-level `httpx` is the scanner.
nixos-generators calls the qcow2 format id `qcow`; the flake aliases it.

## Tradeoffs versus the Debian guest

NixOS pins kernel, packages, and Hoplon in one file, so builds are reproducible.
The Debian guest provisions faster and is easier to tweak live but drifts with
the cloud image and `toolchain.sh`. The Nix store is read-only, so Hoplon seeds
`~/.local/share/hoplon`. The first NixOS build is heavy, and there is no
cloud-init or 9p share by default. Use NixOS for reproducibility, Debian for a
fast throwaway guest.
