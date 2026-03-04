{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [ scrcpy ];
  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };
}
