{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.system.virtualisation;
  devices = [ "1002:73ff" ]; # RX6600
in
{
  options.custom.system.virtualisation = {
    enable = lib.mkEnableOption "Libvirt virtualization and GPU passthrough";
    user = lib.mkOption {
      type = lib.types.str;
      default = "julian";
      description = "User to add to libvirtd group";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [
      "kvm-intel"
      "vfio"
      "vfio-pci"
      "vfio_iommu_type1"
    ];

    users.users.${cfg.user}.extraGroups = [ "libvirtd" ];

    virtualisation.libvirtd = {
      enable = true;
      onBoot = "ignore";
      onShutdown = "shutdown";
      qemu = {
        runAsRoot = true;
      };
    };

    boot.kernelParams = [
      "intel_iommu=on"
      "iommu=pt"
      "vfio-pci.ids=${lib.concatStringsSep "," devices}"
    ];

    boot.initrd.kernelModules = [
      "vfio_pci"
      "vfio"
      "vfio_iommu_type1"
    ];

    virtualisation.spiceUSBRedirection.enable = true;

    environment.systemPackages = with pkgs; [
      virt-manager
      libguestfs
      looking-glass-client
    ];
  };
}
