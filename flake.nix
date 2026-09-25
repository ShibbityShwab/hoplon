{
  description = "Hoplon NixOS guest: a declarative, self-contained red-team workstation with its own kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      ...
    }:
    let
      # Flake-level builder. `hoplonAuthorizedKeys` is the flake argument: it
      # defaults to an empty list so the default outputs always evaluate and
      # build with no personal key baked in. A consumer flake injects keys by
      # calling this function, for example:
      #
      #   outputs = { hoplon, ... }:
      #     hoplon.mkHoplon {
      #       hoplonAuthorizedKeys = [ "ssh-ed25519 AAAA... operator@host" ];
      #     };
      #
      # Console login still works with the initial password documented in
      # docs/nixos-vm.md.
      mkHoplon =
        {
          system ? "x86_64-linux",
          hoplonAuthorizedKeys ? [],
        }:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # The `hoplon` package: repo payload plus the pinned opencode binary,
          # exposed on PATH through a wrapper that seeds a writable runtime home.
          hoplonPackage = pkgs.callPackage ./nix/hoplon-package.nix { };

          # Shared between the standalone NixOS configuration and the
          # nixos-generators image so both build exactly the same guest.
          specialArgs = { inherit hoplonAuthorizedKeys hoplonPackage; };

          # Modules shared by the runnable VM and the qcow2 image.
          guestModules = [
            ./nix/configuration.nix
            ./nix/toolchain.nix
          ];

          # The VM adds qemu-vm.nix; the qcow2 image gets its own format module
          # from nixos-generators and does not need qemu-vm.
          nixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system specialArgs;
            modules = guestModules ++ [ ./nix/vm.nix ];
          };

          vmScript = nixosConfiguration.config.system.build.vm;
          vmName = "run-${nixosConfiguration.config.networking.hostName}-vm";
        in
        {
          nixosConfigurations.hoplon = nixosConfiguration;

          packages.${system} = {
            hoplon = hoplonPackage;
            vm = vmScript;

            # nixos-generators names the qcow2 format id `qcow` (the produced
            # file is `nixos.qcow2`). We expose it under the requested `qcow2`
            # attribute and alias the format id so `format = "qcow2"` resolves.
            qcow2 = nixos-generators.nixosGenerate {
              inherit system specialArgs;
              format = "qcow2";
              customFormats.qcow2 = {
                imports = [ "${nixos-generators}/formats/qcow.nix" ];
              };
              modules = guestModules;
            };
          };

          apps.${system}.vm = {
            type = "app";
            program = "${vmScript}/bin/${vmName}";
            meta.description = "Boot the Hoplon NixOS guest under QEMU/KVM";
          };
        };
    in
    mkHoplon { } // { inherit mkHoplon; };
}
