{pkgs, ...}:
{
	environment.systemPackages = with pkgs; [
		protonup
		mangohud
	];
	programs = {
		steam.enable = true;
		gamemode.enable = true;
	};
	virtualisation.waydroid.enable = true;
}
