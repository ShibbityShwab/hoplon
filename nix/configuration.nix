# =============================================================================
# Hoplon NixOS guest configuration (shared by the VM and the qcow2 image).
#
# One declarative file describes a full guest operating system with its own
# kernel. `nix run .#vm` boots it under QEMU/KVM; `nix build .#qcow2` produces a
# bootable disk image. The guest is separate from the host and from the Debian
# QEMU guest used by HOPLON_ISOLATION=vm.
#
# QEMU runner settings (cores, memory, port forwards, graphics) live in
# nix/vm.nix because they need the qemu-vm module, which is not part of the
# default NixOS module set on 25.05.
# =============================================================================
{
  config,
  lib,
  pkgs,
  modulesPath,
  hoplonAuthorizedKeys,
  hoplonPackage,
  ...
}:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  # Match the pinned nixpkgs branch. Do not bump without a deliberate migration.
  system.stateVersion = "25.05";

  networking.hostName = "hoplon-vm";

  # The guest is a red-team workstation, so allow unfree packages and flakes
  # natively.
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # ---------------------------------------------------------------------------
  # Networking. DHCP on every interface, firewall on, port 22 open.
  # ---------------------------------------------------------------------------
  networking.useDHCP = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # ---------------------------------------------------------------------------
  # SSH. Key auth comes from hoplonAuthorizedKeys. Password SSH stays off so the
  # documented console password never becomes a remote entry point; the guest is
  # reached over the QEMU host-forward, or over the console for first login.
  # ---------------------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.hoplon = {
    isNormalUser = true;
    description = "Hoplon operator";
    extraGroups = [ "wheel" ];
    initialPassword = "hoplon";
    openssh.authorizedKeys.keys = hoplonAuthorizedKeys;
  };

  # Passwordless sudo for the operator, matching the Hoplon host workflow.
  security.sudo.wheelNeedsPassword = false;

  # ---------------------------------------------------------------------------
  # Boot. A QEMU virtio disk shows as /dev/vda; GRUB on that device boots the
  # qcow2 image. The run script boots its own kernel and ignores the loader.
  # ---------------------------------------------------------------------------
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };
  boot.loader.timeout = 0;

  # 30 GiB backing disk for both the qcow2 image and the VM runner. The option
  # is defined by disk-size-option.nix, which both the qemu-vm module and the
  # nixos-generators format module import.
  virtualisation.diskSize = 30720;

  # Hoplon itself. The red-team toolchain lives in nix/toolchain.nix.
  environment.systemPackages = [ hoplonPackage ];
}
