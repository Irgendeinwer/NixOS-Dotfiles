{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.desktop.messaging;
in
{
  options.custom.desktop.messaging = {
    enable = lib.mkEnableOption "desktop messaging applications (Signal, Telegram, Vesktop, Element)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      android-mic
      element-desktop
      vesktop
      zapzap # whatsapp-for-linux
      signal-desktop
      telegram-desktop
    ];
  };
}
