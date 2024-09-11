{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
	i2p
	i2pd
  ];
}
