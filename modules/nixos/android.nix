{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    scrcpy
    android-tools
  ];

  users.users.julian.extraGroups = [ "adbusers" "kvm" ];

  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };
}
