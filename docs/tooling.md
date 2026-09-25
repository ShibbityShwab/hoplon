# Tooling

The Debian guest ships a broad offensive-security toolkit so you can start
working the moment the guest boots. Coverage is grouped by category and the
exact list is always the source of truth, never this page:

- `scripts/vm.sh` provisions the guest and runs the installer on first boot.
- `scripts/toolchain.sh --list` prints the exact list installed when
  `HOPLON_VM_TOOLS=core` or `full`.

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

Add an entry to `FULL_TOOLS` and a dispatch case in `scripts/toolchain.sh`, or
install it live inside the guest. The next `scripts/vm.sh start` on a fresh
guest runs the installer and picks it up.

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

The Debian guest installs its toolchain over the network on first boot, so it
needs connectivity then. Set `HOPLON_VM_TOOLS=none` to skip provisioning, or run
`scripts/toolchain.sh` yourself later.
