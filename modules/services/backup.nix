{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.services.backup;
  secretsDir = ../../secrets;
  hostSecretsFile = secretsDir + "/${config.networking.hostName}.yaml";
  commonSecretsFile = secretsDir + "/common.yaml";
in
{
  options.custom.services.backup = {
    enable = lib.mkEnableOption "Automated BorgBackup to external USB drive";

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/media/backup";
      description = "Mount point directory for the external backup drive";
    };

    deviceUuid = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Filesystem UUID of the backup partition on the external drive";
    };

    repoName = lib.mkOption {
      type = lib.types.str;
      default = "borg-${config.networking.hostName}";
      description = "Name of the Borg repository folder on the backup drive";
    };

    startAt = lib.mkOption {
      type = with lib.types; either str (listOf str);
      default = "daily";
      description = "When or how often the backup should run (systemd calendar format)";
    };

    autoTriggerOnPlug = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically trigger backup job when the external backup drive is plugged in via USB";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.deviceUuid != null;
        message = "custom.services.backup.deviceUuid must be specified when backup is enabled.";
      }
    ];

    sops.secrets.borg_passphrase = {
      sopsFile = if builtins.pathExists hostSecretsFile then hostSecretsFile else commonSecretsFile;
    };

    # Declarative automount for the external backup drive (15s timeout for mechanical HDD spin-up)
    fileSystems."${cfg.mountPoint}" = {
      device = "/dev/disk/by-uuid/${cfg.deviceUuid}";
      fsType = "ext4";
      options = [
        "noauto"
        "nofail"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
        "x-systemd.device-timeout=15s"
      ];
    };

    # Automatically trigger backup service upon USB drive insertion
    services.udev.extraRules = lib.mkIf cfg.autoTriggerOnPlug ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${cfg.deviceUuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="borgbackup-job-systemBackup.service"
    '';

    services.borgbackup.jobs.systemBackup = {
      paths = [
        "/home/${config.custom.user}"
        "/media/fun/music"
        "/media/fun/audiobooks"
        "/media/fun/gallery"
        "/etc/ssh"
        "/var/lib/sops-nix"
      ];

      exclude = [
        # Nix store & generic build caches (shell glob syntax)
        "sh:**/.cache"
        "sh:**/.direnv"
        "sh:**/.devenv"
        "sh:**/result"
        "sh:**/result-*"
        "sh:**/node_modules"
        "sh:**/target"
        "sh:**/__pycache__"
        "sh:**/.gradle"
        "sh:**/.npm"
        "sh:**/.cargo/registry"
        "sh:**/.cargo/git"
        "sh:home/*/nixpkgs"
        "sh:home/*/.local/share/Trash"

        # Large game installations (preserving saves/configs)
        "sh:home/*/Games"
        "sh:home/*/UntrustedGames"
        "sh:home/*/.local/share/Steam/steamapps/common"
        "sh:home/*/.local/share/Steam/steamapps/downloading"
        "sh:home/*/.local/share/Steam/steamapps/temp"
        "sh:home/*/.local/share/Steam/appcache"
        "sh:home/*/.local/share/Steam/shadercache"
        "sh:home/*/.local/share/lutris/runners"
        "sh:home/*/.local/share/heroic"
        "sh:home/*/.local/share/umu"
        "sh:home/*/.local/share/waydroid"

        # PrismLauncher: exclude heavy cache/binaries, preserve instance configs & world saves
        "sh:home/*/.local/share/PrismLauncher/libraries"
        "sh:home/*/.local/share/PrismLauncher/assets"
        "sh:home/*/.local/share/PrismLauncher/meta"
        "sh:home/*/.local/share/PrismLauncher/runtime"
        "sh:home/*/.local/share/PrismLauncher/temp"

        # Large non-essential media & VM images
        "sh:home/*/Screenrecordings"
        "sh:home/*/Downloads"
        "sh:**/windows-11/disk.qcow2"
        "sh:**/windows-11/*.iso"
        "sh:**/windows-11/*.ISO"
      ];

      repo = "${cfg.mountPoint}/${cfg.repoName}";
      removableDevice = true;

      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.sops.secrets.borg_passphrase.path}";
      };

      compression = "auto,zstd,3";

      prune.keep = {
        daily = 7;
        weekly = 4;
        monthly = 12;
        yearly = 1;
      };

      startAt = cfg.startAt;
      persistentTimer = true;
      inhibitsSleep = true;
      doInit = true;
      failOnWarnings = false;
      wrapper = "borg-job-backup";
    };

    # Override unit constraints and dependencies for removable drive & boot ordering
    systemd.services.borgbackup-job-systemBackup = {
      # Ensure sops-nix and filesystem targets are ready before backup runs (prevents boot race conditions)
      after = [
        "sops-nix.service"
        "local-fs.target"
      ];
      wants = [ "sops-nix.service" ];

      unitConfig = {
        # Prevent systemd from failing the unit before execution if the drive is disconnected
        RequiresMountsFor = lib.mkForce [ ];
        ConditionPathExists = "/dev/disk/by-uuid/${cfg.deviceUuid}";
      };

      serviceConfig = {
        # Explicitly make the mountpoint writable in the namespace, avoiding 226/NAMESPACE errors on first run
        ReadWritePaths = lib.mkForce [
          "/root/.config/borg"
          "/root/.cache/borg"
          cfg.mountPoint
        ];
      };
    };
  };
}
