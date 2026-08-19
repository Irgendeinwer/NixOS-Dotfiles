{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.playerctl;
in
{
  options.custom.services.playerctl = {
    enable = lib.mkEnableOption "Playerctld media player control daemon";
  };

  config = lib.mkIf cfg.enable {
    services.playerctld.enable = true;
  };
}
