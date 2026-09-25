# =============================================================================
# Hoplon red-team toolchain.
#
# Every attribute here was verified to exist in the pinned nixpkgs
# (nixos-25.05, rev ac62194c3917d5f474c1a844b6fd6da2db95077d) with `nix eval`.
# Naming notes:
#   * `thc-hydra` is the network login cracker; nixpkgs `hydra` is the CI server.
#   * top-level `httpx` is the ProjectDiscovery scanner, not the Python library.
#   * `impacket` lives under `python3Packages`.
#   * `bloodhound-ce` is not packaged; the classic `bloodhound` is.
# =============================================================================
{
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    # Networking and recon
    nmap
    netcat-gnu
    netcat-openbsd
    dnsutils
    whois
    curl
    wget
    socat
    tcpdump
    iproute2
    inetutils
    masscan

    # Web and DNS
    nikto
    whatweb
    nuclei
    subfinder
    httpx
    ffuf
    gobuster
    dnsrecon
    amass

    # Credential and Active Directory
    thc-hydra
    john
    sqlmap
    netexec
    bloodhound
    samba
    openldap
    python3Packages.impacket
    aircrack-ng

    # Exploitation
    metasploit

    # Reversing and debugging
    radare2
    gdb
    strace
    ltrace
    binutils

    # Languages and build tooling
    go
    gcc
    gnumake
    python3
    pipx

    # Shell and data quality of life
    git
    jq
    ripgrep
    tmux
    file
    openssl
    procps
    unzip
    zip

    # Wordlists
    seclists
    wordlists
  ];
}
