# =============================================================================
# Hoplon red-team toolchain (NixOS guest).
#
# Every attribute below was verified against the pinned nixpkgs
# (nixos-25.05, rev ac62194c3917d5f474c1a844b6fd6da2db95077d) by importing the
# flake input and forcing each candidate derivation inside `builtins.tryEval`,
# then re-confirmed through the full system evaluation:
#
#   nix eval --raw "path:.#nixosConfigurations.hoplon.config.networking.hostName"
#   nix eval "path:.#nixosConfigurations.hoplon.config.system.build.toplevel.drvPath"
#   nix build --dry-run "path:.#nixosConfigurations.hoplon.config.system.build.toplevel"
#
# Naming notes:
#   * `thc-hydra` is the login cracker; nixpkgs `hydra` is the CI server.
#   * top-level `httpx` is the ProjectDiscovery scanner, not the Python library.
#   * OWASP ZAP is packaged as `zap`, not `zaproxy`.
#   * hping3 is packaged as `hping`; dirsearch/patator live under python3Packages.
#   * gef, boofuzz, frida-tools, mitm6, evil-winrm and pacu are top-level.
#   * mingw-w64 is not a top-level attr; it comes from pkgsCross.mingwW64.
#
# Not packaged in the pinned nixpkgs, install inside the guest instead:
#   * pwndbg     -> removed from nixpkgs; use `gef` below or `pipx install pwndbg`
#   * objection  -> `pipx install objection`
#   * scoutsuite -> `pipx install scoutsuite`
#   * sliver     -> `go install` from source or fetch a release inside the guest
#   * PEASS (linpeas/winpeas) -> not packaged, out of scope for this file
#   * patator    -> its oracle extra (cx-oracle) fails to build against the
#                   packaged instantclient; use `pipx install patator` in-guest
# =============================================================================
{
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    # -------------------------------------------------------------------------
    # Networking basics
    # -------------------------------------------------------------------------
    curl
    wget
    socat
    tcpdump
    iproute2
    inetutils
    openssl

    # -------------------------------------------------------------------------
    # Recon and OSINT
    # -------------------------------------------------------------------------
    nmap
    masscan
    netcat
    netcat-gnu
    netcat-openbsd
    dnsutils
    whois
    dnsx
    naabu
    subfinder
    amass
    httpx
    katana
    gau
    theharvester
    dnsrecon

    # -------------------------------------------------------------------------
    # Web application testing
    # -------------------------------------------------------------------------
    nuclei
    ffuf
    gobuster
    feroxbuster
    python3Packages.dirsearch
    dalfox
    arjun
    commix
    wpscan
    nikto
    whatweb
    sqlmap
    zap # OWASP ZAP (nixpkgs name for zaproxy)
    mitmproxy
    gospider

    # -------------------------------------------------------------------------
    # Credentials and password attacks
    # -------------------------------------------------------------------------
    hashcat
    hashcat-utils
    john
    thc-hydra
    medusa
    crunch
    cewl
    aircrack-ng
    seclists
    wordlists

    # -------------------------------------------------------------------------
    # Active Directory and Windows
    # -------------------------------------------------------------------------
    python3Packages.impacket
    netexec
    bloodhound
    kerbrute
    python3Packages.certipy
    mitm6
    responder
    ldapdomaindump
    smbmap
    enum4linux
    enum4linux-ng
    evil-winrm
    python3Packages.pypykatz
    coercer
    samba
    openldap

    # -------------------------------------------------------------------------
    # Exploit development and pwn
    # -------------------------------------------------------------------------
    python3Packages.pwntools
    gef # pwndbg is not packaged; gef is the shipped GDB UX
    python3Packages.ropgadget
    python3Packages.ropper
    checksec
    rubyPackages.one_gadget
    capstone
    python3Packages.keystone-engine
    unicorn
    python3Packages.angr
    valgrind
    qemu-user
    nasm
    gdb

    # -------------------------------------------------------------------------
    # Fuzzing
    # -------------------------------------------------------------------------
    aflplusplus
    honggfuzz
    radamsa
    boofuzz
    clang
    llvm

    # -------------------------------------------------------------------------
    # Reversing and forensics
    # -------------------------------------------------------------------------
    ghidra
    radare2
    rizin
    cutter
    binutils
    ltrace
    strace
    binwalk
    exiftool
    yara
    sleuthkit
    foremost
    testdisk
    steghide
    volatility3
    upx
    jadx
    apktool
    frida-tools

    # -------------------------------------------------------------------------
    # Network interception and MITM
    # -------------------------------------------------------------------------
    wireshark-cli # provides tshark
    bettercap
    ettercap
    python3Packages.scapy
    hping
    arp-scan

    # -------------------------------------------------------------------------
    # Cloud and containers
    # -------------------------------------------------------------------------
    awscli2
    azure-cli
    google-cloud-sdk
    kubectl
    trivy
    kube-hunter
    pacu
    podman # daemonless; the Docker daemon is not enabled here

    # -------------------------------------------------------------------------
    # Post-exploitation and C2
    # -------------------------------------------------------------------------
    metasploit
    chisel
    ligolo-ng

    # -------------------------------------------------------------------------
    # Compilers and build tooling (clang/llvm are in the fuzzing block above)
    # -------------------------------------------------------------------------
    gcc
    gnumake
    cmake
    pkg-config
    pkgsCross.mingwW64.buildPackages.gcc
    pkgsCross.mingwW64.buildPackages.binutils
    ruby
    nodejs
    rustc
    cargo
    go
    python3
    pipx

    # -------------------------------------------------------------------------
    # Shell and data quality of life
    # -------------------------------------------------------------------------
    git
    jq
    ripgrep
    tmux
    file
    procps
    unzip
    zip
  ];
}
