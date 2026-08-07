{ ... }:

{
  services.lact.enable = true;

  boot.kernelParams = [
    "amdgpu.ppfeaturemask=0xffffffff"
  ];
}
