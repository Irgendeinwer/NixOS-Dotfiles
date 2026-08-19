{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.system.android;
in
{
  options.custom.system.android = {
    enable = lib.mkEnableOption "Android tools and Waydroid virtualization";
    user = lib.mkOption {
      type = lib.types.str;
      default = "julian";
      description = "User to add to adbusers and kvm groups";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      scrcpy
      android-tools
    ];

    users.users.${cfg.user}.extraGroups = [
      "adbusers"
      "kvm"
    ];

    virtualisation.waydroid = {
      enable = true;
      package = pkgs.waydroid-nftables;
    };
  };
}
