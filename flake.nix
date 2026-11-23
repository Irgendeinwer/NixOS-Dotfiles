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

    private = {
      url = "git+ssh://git@github.com/Irgendeinwer/nix-private.git";
      inputs.nixpkgs.follows = "nixpkgs";
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

      inherit (nixpkgs) lib;
      myOverlays = loadOverlays ./modules/overlays;
      hasPrivate = inputs ? private;
      privateOverlays =
        if hasPrivate && inputs.private ? overlays.default then
          [ inputs.private.overlays.default ]
        else
          [ ];
      privateNixosModulesFor =
        name:
        if hasPrivate && inputs.private ? nixosModules then
          let
            mods = inputs.private.nixosModules;
          in
          lib.optional (mods ? default) mods.default ++ lib.optional (mods ? ${name}) mods.${name}
        else
          [ ];
      privateHomeModulesFor =
        name:
        if hasPrivate && inputs.private ? homeManagerModules then
          let
            mods = inputs.private.homeManagerModules;
          in
          lib.optional (mods ? default) mods.default ++ lib.optional (mods ? ${name}) mods.${name}
        else
          [ ];

      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      customScripts = import ./pkgs/scripts { inherit pkgs; };

      # Keep host-specific modules explicit, while sharing the integrations
      # and Home Manager setup that every host needs.
      mkHost =
        name: hostModules:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.overlays = myOverlays ++ privateOverlays; }
          ]
          ++ hostModules
          ++ privateNixosModulesFor name
          ++ [
            inputs.sops-nix.nixosModules.sops
            inputs.lanzaboote.nixosModules.lanzaboote
            inputs.home-manager.nixosModules.default
            (
              { config, ... }:
              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  backupFileExtension = "backup";
                  extraSpecialArgs = { inherit inputs; };
                  sharedModules = privateHomeModulesFor name;
                  users.${config.custom.user} = import (./hosts + "/${name}/home.nix");
                };
              }
            )
            inputs.nixvim.nixosModules.nixvim
          ];
        };
    in
    {
      # `nix fmt` formats every .nix file in the repo with nixfmt
      formatter.${system} = pkgs.nixfmt-tree;

      packages.${system} =
        customScripts
        // {
          without-userns = pkgs.callPackage ./pkgs/without-userns.nix { };
        }
        // (
          if hasPrivate && inputs.private ? packages.${system} then inputs.private.packages.${system} else { }
        );

      checks.${system} = {
        custom-scripts =
          let
            entries = lib.mapAttrsToList (name: path: { inherit name path; }) customScripts;
          in
          pkgs.linkFarm "custom-scripts-check" entries;

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

        portal-status = pkgs.runCommand "portal-status-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          export PORTAL_STATUS_HELPER=${./modules/services/scripts/portal-status.py}
          python3 -B ${./tests/portal-status.py}
          mkdir -p "$out"
        '';

        plan-engine = pkgs.runCommand "plan-engine-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
          export JUNIX_PLAN_HELPER=${./pkgs/scripts/plan.py}
          python3 -B ${./tests/plan.py}
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

        desktop-options = import ./tests/desktop-options.nix {
          inherit nixpkgs pkgs self;
          sopsModule = inputs.sops-nix.nixosModules.sops;
        };
        tailscale-options = import ./tests/tailscale-options.nix { inherit nixpkgs pkgs self; };
        syncthing-options = import ./tests/syncthing-options.nix { inherit nixpkgs pkgs self; };
        navidrome-options = import ./tests/navidrome-options.nix { inherit nixpkgs pkgs self; };
        portal-options = import ./tests/portal-options.nix {
          inherit nixpkgs pkgs self;
          sopsModule = inputs.sops-nix.nixosModules.sops;
        };
        planner-options = import ./tests/planner-options.nix {
          inherit nixpkgs pkgs self;
          sopsModule = inputs.sops-nix.nixosModules.sops;
        };
        standalone-home = import ./tests/standalone-home.nix { inherit inputs pkgs; };
        theme-options = import ./tests/theme-options.nix { inherit nixpkgs pkgs self; };
        zen-options = import ./tests/zen-options.nix { inherit inputs pkgs self; };

        without-userns-filter = pkgs.runCommandCC "without-userns-filter-test" { } ''
          "$CC" -O2 -Wall -Wextra -Werror ${./tests/without-userns.c} -o filter-probe
          ./filter-probe ${pkgs.callPackage ./pkgs/without-userns.nix { }}/bin/without-userns
          mkdir -p "$out"
        '';
      };

      nixosConfigurations = {
        junixos = mkHost "junixos" [
          inputs.disko.nixosModules.disko
          ./hosts/junixos/disk-config.nix
          ./hosts/junixos/configuration.nix
          nixos-hardware.nixosModules.common-cpu-intel-cpu-only
          nixos-hardware.nixosModules.common-pc-ssd
        ];

        junixbook = mkHost "junixbook" [
          ./hosts/junixbook/configuration.nix
          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-ssd
          nixos-hardware.nixosModules.common-pc-laptop # TLP power management
        ];

        junixsrv = mkHost "junixsrv" [
          ./hosts/junixsrv/configuration.nix
        ];
      };
    };
}
