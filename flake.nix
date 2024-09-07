{
description = "Nixos config flake";

inputs = {
	nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
	nixos-hardware.url = "github:NixOS/nixos-hardware";
	home-manager = {
		url = "github:nix-community/home-manager";
		inputs.nixpkgs.follows = "nixpkgs";
	};

	# hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
};

	


outputs = { self, nixpkgs, nixos-hardware, ... }@inputs: {
	nixosConfigurations."junixos" = nixpkgs.lib.nixosSystem {
		specialArgs = {inherit inputs;};
		modules = [
        		./hosts/junixos/configuration.nix
			nixos-hardware.nixosModules.common-cpu-intel-cpu-only
			nixos-hardware.nixosModules.common-pc-ssd
			inputs.home-manager.nixosModules.default
			{
            			home-manager.useGlobalPkgs = true;
            			home-manager.useUserPackages = true;
          		}
		];
	};

	nixosConfigurations."junixbook" = nixpkgs.lib.nixosSystem {
		specialArgs = {inherit inputs;};
		modules = [
			./hosts/junixbook/configuration.nix
			nixos-hardware.nixosModules.common-cpu-intel
			nixos-hardware.nixosModules.common-pc-ssd
			inputs.home-manager.nixosModules.default
			{
				home-manager.useGlobalPkgs = true;
				home-manager.useUserPackages = true;
			}
		];
	};
};

}
