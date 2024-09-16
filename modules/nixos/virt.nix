{ config, pkgs, ...}:
{
  boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ];
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

  environment.systemPackages = with pkgs; [
	virt-manager
	libguestfs
	looking-glass-client
  ];
}
