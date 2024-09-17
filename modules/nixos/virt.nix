{ config, lib, pkgs, ...}:
{
# boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ];
  boot.kernelModules = [ "kvm-intel" "vfio" "vfio-pci" "vfio_iommu_type1" ];

  users.users.julian = {
	extraGroups = [ "libvirtd" ];
  };

  virtualisation.libvirtd = {
	enable = true;
	onBoot = "ignore";
	onShutdown = "shutdown";
	qemu = {
		ovmf.enable = true;
		runAsRoot = true;
  	};
  };

  boot.kernelParams = let
  devices = [ "1002:73ff" ]; #RX6600
  in [
	"intel_iommu=on" "iommu=pt" "vfio-pci.ids=${lib.concatStringsSep "," devices}"
  ];

  boot.initrd.kernelModules = [
       	"vfio_pci"
       	"vfio"
       	"vfio_iommu_type1"
  ];

  virtualisation.spiceUSBRedirection.enable = true;

#  systemd.tmpfiles.rules = [
#        "f /dev/shm/looking-glass 0660 ${config.settings.user.name} libvirtd -"
#  ];

  environment.systemPackages = with pkgs; [
	virt-manager
	libguestfs
	looking-glass-client
  ];
}
