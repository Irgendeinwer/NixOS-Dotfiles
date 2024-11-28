{ lib, config, pkgs, ... }:
{
  options = {
    sound-module = {
	enable = lib.mkEnableOption "sound-module";
    };
  };
  config = lib.mkIf config.sound-module.enable {
    environment.systemPackages = with pkgs; [
	alsa-utils
	helvum
	pulseaudioFull
	pulsemixer
	pavucontrol
	pamixer
    ];
    security.rtkit.enable = true;
    services.pipewire = {
	enable = true;
	alsa = {
	    enable = true;
	    support32Bit = true;
	};
	pulse.enable = true;
    };
  };
}
