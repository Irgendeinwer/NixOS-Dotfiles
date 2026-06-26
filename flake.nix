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

    # Preserve kernel binary cache compatibility by keeping this isolated
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
    in
    {
      nixosConfigurations."junixos" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
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
        specialArgs = { inherit inputs; };
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
