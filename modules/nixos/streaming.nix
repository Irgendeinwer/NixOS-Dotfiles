{ pkgs, ... }:
{
	environment.systemPackages = with pkgs; [
		youtube-music
		spotube
	];
}
