{pkgs, ...}:
{
	environment.systemPackages = with pkgs; [
		protonup
		mangohud
		ddnet
		osu-lazer-bin # "-bin" is needed to submit scores and play online multiplayer
	];
	programs = {
		steam.enable = true;
		gamemode.enable = true;
	};
	virtualisation.waydroid.enable = true;
}
