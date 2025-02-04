{ pkgs, ...}:
{
  imports = [
  	./pkgs/browsers.nix
	./pkgs/flexing.nix
	./pkgs/messaging.nix
	./pkgs/streaming.nix
  ];

  environment.systemPackages = with pkgs; [
    yazi

    keepassxc

    qbittorrent-nox
  ];
}
