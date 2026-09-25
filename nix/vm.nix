# =============================================================================
# QEMU/KVM runner settings for `nix run .#vm`.
#
# On NixOS 25.05 the qemu-vm module is not part of the default module list, so
# it is imported here explicitly. This module is only added to
# nixosConfigurations.hoplon (the runnable VM); the qcow2 image is generated
# separately from the shared guest modules.
# =============================================================================
{ modulesPath, ... }:
{
  imports = [
    "${modulesPath}/virtualisation/qemu-vm.nix"
  ];

  virtualisation = {
    # Serial console instead of a graphical window, so the guest is usable over
    # SSH or a terminal. Guest port 22 is forwarded to 127.0.0.1:2222.
    graphics = false;
    cores = 4;
    memorySize = 4096;
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 2222;
        guest.port = 22;
      }
    ];
  };
}
