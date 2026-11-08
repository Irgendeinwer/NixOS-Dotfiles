{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wallpaper = {
      url = "git+ssh://git@github.com/Irgendeinwer/wallpaper.git";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      ...
    }@inputs:
    let
      loadOverlays =
        dir:
        if builtins.pathExists dir then
          let
            files = builtins.attrNames (builtins.readDir dir);
            nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) files;
          in
          map (name: import (dir + "/${name}")) nixFiles
        else
          [ ];

      myOverlays = loadOverlays ./modules/overlays;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # `nix fmt` formats every .nix file in the repo with nixfmt
      formatter.${system} = pkgs.nixfmt-tree;

      checks.${system} = {
        nightly-runtime =
          pkgs.runCommand "nightly-runtime-tests"
            {
              nativeBuildInputs = with pkgs; [
                bash
                coreutils
                git
                gnugrep
                jq
              ];
            }
            ''
              export NIGHTLY_SUMMARY_HELPER=${./modules/services/scripts/nightly-summary.sh}
              export NIGHTLY_NOTIFY_HELPER=${./modules/services/scripts/nightly-notify.sh}
              export NIGHTLY_FINISH_HELPER=${./modules/services/scripts/nightly-finish.sh}
              export NIGHTLY_GCROOTS_HELPER=${./modules/services/scripts/nightly-gcroots.sh}
              export NIGHTLY_LOG_HELPER=${./modules/services/scripts/nightly-log.sh}
              export NIGHTLY_ACTIVATE_HELPER=${./modules/services/scripts/nightly-activate.sh}
              export NIGHTLY_SIGNALS_HELPER=${./modules/services/scripts/nightly-signals.sh}
              ${pkgs.bash}/bin/bash ${./tests/nightly-notify.sh}
              ${pkgs.bash}/bin/bash ${./tests/nightly-gcroots.sh}
              ${pkgs.bash}/bin/bash ${./tests/nightly-log.sh}
              ${pkgs.bash}/bin/bash ${./tests/nightly-flow.sh}
              mkdir -p "$out"
            '';

        remote-builder-mdns =
          pkgs.runCommand "remote-builder-mdns-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              export REMOTE_BUILDER_MDNS_HELPER=${./modules/nixos/scripts/remote-builder-mdns.py}
              python3 -B ${./tests/remote-builder-mdns.py}
              mkdir -p "$out"
            '';

        container-options = import ./tests/container-options.nix {
          inherit nixpkgs pkgs system;
        };

        remote-builder-options = import ./tests/remote-builder-options.nix {
          inherit nixpkgs pkgs system;
          sopsModule = inputs.sops-nix.nixosModules.sops;
        };

        build-server-options = import ./tests/build-server-options.nix {
          inherit nixpkgs pkgs system;
          sopsModule = inputs.sops-nix.nixosModules.sops;
        };

        without-userns-filter = pkgs.runCommandCC "without-userns-filter-test" { } ''
          "$CC" -O2 -Wall -Wextra -Werror ${./tests/without-userns.c} -o filter-probe
          ./filter-probe ${pkgs.callPackage ./pkgs/without-userns.nix { }}/bin/without-userns
          mkdir -p "$out"
        '';
      };

      nixosConfigurations."junixos" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          { nixpkgs.overlays = myOverlays; }

          inputs.disko.nixosModules.disko
          ./hosts/junixos/disk-config.nix
          ./hosts/junixos/configuration.nix

          nixos-hardware.nixosModules.common-cpu-intel-cpu-only
          nixos-hardware.nixosModules.common-pc-ssd

          inputs.sops-nix.nixosModules.sops
          inputs.lanzaboote.nixosModules.lanzaboote
          inputs.home-manager.nixosModules.default
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "backup";
          }

          inputs.nixvim.nixosModules.nixvim
        ];
      };

      nixosConfigurations."junixbook" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          { nixpkgs.overlays = myOverlays; }

          ./hosts/junixbook/configuration.nix

          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-ssd
          nixos-hardware.nixosModules.common-pc-laptop # TLP power management

          inputs.sops-nix.nixosModules.sops
          inputs.lanzaboote.nixosModules.lanzaboote
          inputs.home-manager.nixosModules.default
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "backup";
          }

          inputs.nixvim.nixosModules.nixvim
        ];
      };

      nixosConfigurations."junixsrv" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          { nixpkgs.overlays = myOverlays; }

          ./hosts/junixsrv/configuration.nix

          inputs.sops-nix.nixosModules.sops
          inputs.lanzaboote.nixosModules.lanzaboote
          inputs.home-manager.nixosModules.default
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "backup";
          }

          inputs.nixvim.nixosModules.nixvim
        ];
      };
    };
}
