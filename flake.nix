{
  description = "Nixos config flake";

  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs-unstable";
        home-manager.follows = "home-manager";
      };
    };

    wallpaper = {
      url = "git+ssh://git@github.com/Irgendeinwer/wallpaper.git";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs-unstable,
      nixos-hardware,
      ...
    }@inputs:
    let
      nixpkgs = nixpkgs-unstable;

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
    in
    {
      nixosConfigurations."junixos" = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inputs = inputs // {
            nixpkgs = nixpkgs-unstable;
          };
        };
        modules = [
          { nixpkgs.overlays = myOverlays; }

          inputs.disko.nixosModules.disko
          ./hosts/junixos/disk-config.nix
          ./hosts/junixos/configuration.nix

          nixos-hardware.nixosModules.common-cpu-intel-cpu-only
          nixos-hardware.nixosModules.common-pc-ssd

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
        specialArgs = {
          inputs = inputs // {
            nixpkgs = nixpkgs-unstable;
          };
        };
        modules = [
          { nixpkgs.overlays = myOverlays; }

          ./hosts/junixbook/configuration.nix

          nixos-hardware.nixosModules.common-cpu-intel
          nixos-hardware.nixosModules.common-pc-ssd

          inputs.home-manager.nixosModules.default
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
          }

          inputs.nixvim.nixosModules.nixvim
        ];
      };
    };
}
