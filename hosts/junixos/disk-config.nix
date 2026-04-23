{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Targeting your Samsung 990 EVO Plus explicitly by ID
        device = "/dev/disk/by-id/nvme-Samsung_SSD_990_EVO_Plus_1TB_S7U4NU0YA83063R";
        content = {
          type = "gpt";
          partitions = {
            # 1. Boot Partition (ESP) - 1GB
            # Large enough to avoid "No space left on device" during updates
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
            # 2. Root Partition (Btrfs)
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ]; # Force overwrite

                # Subvolumes allow distinct mount options and backup policies
                subvolumes = {
                  # Root System
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  # Home Data (Your personal files)
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  # Nix Store (Heavy writes, exclude from backups)
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  # Swap File (16GB - Isolated to disable Copy-on-Write)
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
}
