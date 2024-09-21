{pkgs, ...}:
{
	environment.systemPackages = with pkgs; [
		protonup
		mangohud
		ddnet
		osu-lazer
	];
	programs = {
		steam.enable = true;
		gamemode.enable = true;
	};
	virtualisation.waydroid.enable = true;
}
