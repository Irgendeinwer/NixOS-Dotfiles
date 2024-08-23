{ lib, config, pkgs, inputs, ... }:
{
	environment.systemPackages = with pkgs; [
		cmatrix
		hollywood
		cbonsai
		fastfetch
		uwufetch
		cava
		figlet
		lolcat
		neo-cowsay
	];
}
