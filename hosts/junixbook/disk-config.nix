# Target disk layout for the junixbook reinstall: LUKS with btrfs,
# mirroring the junixos subvolumes (hosts/junixos/disk-config.nix).
#
# This file is deliberately NOT imported yet: the running system still
# uses the partitions in hardware-configuration.nix. For the reinstall,
# follow docs/recovery.md. In short:
#   1. Replace the placeholder device below with the new disk
#      (run `ls /dev/disk/by-id` in the installer).
#   2. Add inputs.disko.nixosModules.disko and this file to the
#      junixbook module list in flake.nix.
#   3. Format and install with disko, then remove the fileSystems and
#      swapDevices entries from hardware-configuration.nix (disko owns
#      them from then on).
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Placeholder: set this to the new disk in the installer.
        device = "/dev/disk/by-id/nvme-CHANGE-ME";
        content = {
          type = "gpt";
          partitions = {
            # Boot partition (ESP), sized like junixos to leave room for
            # several Secure Boot generations
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            # Everything else lives inside one LUKS container
            cryptroot = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                settings = {
                  # TRIM and no workqueues: the standard NVMe settings
                  allowDiscards = true;
                  bypassWorkqueues = true;
                };
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ]; # Force overwrite
                  subvolumes = {
                    "@" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    };
                    # Swap file inside the encrypted container, sized
                    # to the 16G of RAM so hibernation fits. Resuming
                    # from a btrfs swap file also needs boot.resumeDevice
                    # and resume_offset, which disko does not set up.
                    "@swap" = {
                      mountpoint = "/.swapvol";
                      swap = {
                        swapfile.size = "16G";
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
