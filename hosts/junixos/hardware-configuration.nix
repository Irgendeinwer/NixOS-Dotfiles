{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Swap for Hibernation
  boot.resumeDevice = "/dev/disk/by-uuid/5ef65cfe-e632-47eb-b239-3eff47eacd8f";
  boot.kernelParams = [ "resume_offset=533760" ];

  fileSystems."/media/fun" = {
    device = "/dev/disk/by-uuid/70a537a9-fc4a-4271-84c0-ef999c2a1bdf";
    fsType = "ext4";
  };

  zramSwap.enable = true;
  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
