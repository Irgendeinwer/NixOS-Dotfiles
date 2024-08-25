{pkgs, ...}:
{
	environment.systemPackages = with pkgs; [
		protonup
		mangohud
		waydroid
	];
	programs = {
		steam.enable = true;
		gamemode.enable = true;
	};
}
