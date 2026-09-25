# Tooling

The Debian guest is minimal by default (`HOPLON_VM_TOOLS=base`): it carries the
`hoplon-tool` CLI and fetches a tool only when you need it, instead of
preloading the whole arsenal. The known catalog still covers a broad
offensive-security toolkit, grouped by category, and the exact list is always
the source of truth, never this page:

- `scripts/vm.sh` provisions the guest and installs `hoplon-tool` on first boot.
- `scripts/toolchain.sh --list` prints every known tool, core and full.
- `scripts/toolchain.sh --core` or `--full` preloads a set when you would rather
  have the tools on disk before an engagement.

## On demand

In the guest, install a tool when you need it:

```bash
hoplon-tool list                 # every known tool
hoplon-tool install sqlmap       # install exactly what you name
hoplon-tool install sqlmap nxc   # several at once; aliases resolve
hoplon-tool install base         # the minimal core package set
hoplon-tool install all          # the full red-team toolset
hoplon-tool status               # what is already present
```

When the shell cannot find a command, `/etc/profile.d/hoplon-autotool.sh`
installs it if it is a known tool and runs it. Set `HOPLON_AUTO_INSTALL=0` to
turn that into a suggestion only:

```bash
HOPLON_AUTO_INSTALL=0 nxc --version
# hoplon: nxc is not installed; run: hoplon-tool install nxc
```

## Categories

| Category | Examples |
| --- | --- |
| Recon and OSINT | nmap, masscan, dnsx, naabu, subfinder, amass, httpx, katana, theHarvester |
| Web | nuclei, ffuf, gobuster, feroxbuster, dirsearch, dalfox, arjun, commix, wpscan, nikto, whatweb, sqlmap, ZAP, mitmproxy |
| Credentials | hashcat, hashcat-utils, john, hydra, medusa, patator, crunch, cewl, seclists, wordlists |
| Active Directory and Windows | impacket, netexec, bloodhound, kerbrute, certipy, mitm6, responder, ldapdomaindump, smbmap, enum4linux-ng, evil-winrm, pypykatz, coercer, samba, openldap |
| Exploit development and pwn | pwntools, gef, ROPgadget, ropper, checksec, one_gadget, capstone, keystone, unicorn, angr, gdb, valgrind, qemu-user |
| Fuzzing | AFL++, honggfuzz, radamsa, boofuzz, clang, llvm |
| Reversing and forensics | Ghidra, radare2, rizin, Cutter, binwalk, exiftool, yara, sleuthkit, foremost, testdisk, steghide, volatility3, upx, jadx, apktool, frida-tools |
| Network interception | tshark, bettercap, ettercap, scapy, hping, arp-scan |
| Cloud and containers | awscli, azure-cli, google-cloud-sdk, kubectl, trivy, kube-hunter, pacu |
| Post-exploitation and C2 | metasploit, chisel, ligolo-ng |
| Compilers and build | gcc, clang, llvm, cmake, mingw-w64 cross, ruby, nodejs, rustc, cargo, go, python3 |
| Shell and data | git, jq, ripgrep, tmux, file |

## Adding a tool

Add an entry to `FULL_TOOLS` and a dispatch case in `scripts/toolchain.sh`. A
`base` guest then picks it up with `hoplon-tool install NAME`; a `core` or
`full` guest picks it up on the next fresh install. You can also install it live
inside the guest.

## What is brought, not shipped

A Linux guest cannot hold everything, and a few things cannot be shipped at all:

- Proprietary tools: Burp Suite Pro, IDA Pro, Binary Ninja, Cobalt Strike,
  Core Impact. Install them under your own license inside the guest.
- Windows-resident tooling: mimikatz, Rubeus, SharpHound, PowerView, and the
  like run on the target Windows host, not in the guest. The guest carries the
  Linux-side equivalents (impacket, netexec, pypykatz, bloodhound) and the
  cross-compiler to build Windows payloads with mingw-w64.
- GPU password cracking: hashcat ships and runs on CPU. Pass a GPU through to
  the VM if you need hardware acceleration.
- Wireless injection: aircrack-ng ships, but monitor-mode and injection depend
  on the physical adapter and are outside a virtual machine.

## Offline

A `base` guest installs its minimal packages and Hoplon over the network on
first boot, then fetches each tool when it is first used, so the on-demand path
needs connectivity at that moment. A `core` or `full` guest preloads on first
boot and then works offline. Either way, set `HOPLON_VM_TOOLS=none` to skip
provisioning, or run `scripts/toolchain.sh` yourself later.
