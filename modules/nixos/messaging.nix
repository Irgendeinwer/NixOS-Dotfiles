{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
	element-desktop
	vesktop
	zapzap # whatsapp-for-linux
	signal-desktop
	telegram-desktop
  ];
}
