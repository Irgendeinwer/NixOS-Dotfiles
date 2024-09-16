{ pkgs, ...}:
{
  environment.systemPackages = with pkgs; [
	virt-manager
	looking-glass-client
  ];
}
