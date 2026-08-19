{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.lact;
in
{
  options.custom.services.lact = {
    enable = lib.mkEnableOption "LACT Linux AMDGPU Controller daemon";
  };

  config = lib.mkIf cfg.enable {
    services.lact.enable = true;

    boot.kernelParams = [
      "amdgpu.ppfeaturemask=0xffffffff"
    ];
  };
}
