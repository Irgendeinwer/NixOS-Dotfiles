{
description = "Nixos config flake";

inputs = {
	nixpkgs.url = "github:NixOS/nixpkgs/b79ce4c43f9117b2912e7dbc68ccae4539259dda";
	# nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
	nixos-hardware.url = "github:NixOS/nixos-hardware";
	home-manager = {
		url = "github:nix-community/home-manager";
		inputs.nixpkgs.follows = "nixpkgs";
	};

	hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
};

	


outputs = { self, nixpkgs, nixos-hardware, ... }@inputs: {
	nixosConfigurations.junixos = nixpkgs.lib.nixosSystem {
		specialArgs = {inherit inputs;};
		modules = [
        		./configuration.nix
			nixos-hardware.nixosModules.common-cpu-intel-cpu-only
			inputs.home-manager.nixosModules.default
			{
            			home-manager.useGlobalPkgs = true;
            			home-manager.useUserPackages = true;
          		}
		];
	};
};

}
