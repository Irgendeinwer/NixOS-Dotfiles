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
		fortune
		neo-cowsay
		pipes
		pipes-rs
		cool-retro-term
	];
}
