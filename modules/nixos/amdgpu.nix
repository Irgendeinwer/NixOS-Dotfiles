{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.hardware.amdgpu;
in
{
  options.custom.hardware.amdgpu = {
    enable = lib.mkEnableOption "AMDGPU OpenCL acceleration";

    lact = {
      enable = lib.mkEnableOption "LACT Linux AMDGPU Controller daemon";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      hardware.amdgpu.opencl.enable = true;
    })
    (lib.mkIf cfg.lact.enable {
      services.lact.enable = true;
      boot.kernelParams = [
        "amdgpu.ppfeaturemask=0xffffffff"
      ];
    })
  ];
}
