{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.buildServer;
  sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";

  nixBin = lib.getExe' config.nix.package.out "nix";
  nixStoreBin = lib.getExe' config.nix.package.out "nix-store";
  nixEnvBin = lib.getExe' config.nix.package.out "nix-env";

  nightlyHosts = lib.unique cfg.nightly.hosts;

  nightlyScript = pkgs.writeShellApplication {
    name = "nix-nightly-update";
    runtimeInputs = [
      config.nix.package
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      repo_ssh_key="${config.sops.secrets.nix_nightly_ssh_key.path}"
      flake_ssh_key="${config.sops.secrets.nix_nightly_flake_ssh_key.path}"

      for key_path in "$repo_ssh_key" "$flake_ssh_key"; do
        if [ ! -s "$key_path" ]; then
          echo "nix-nightly-update: error: SSH key missing or empty at $key_path (enroll host in sops first)." >&2
          exit 1
        fi
      done

      common_ssh_opts="-o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
      repo_ssh_opts="-i $repo_ssh_key $common_ssh_opts"
      flake_ssh_opts="-i $flake_ssh_key $common_ssh_opts"

      repo_git() {
        GIT_SSH_COMMAND="ssh $repo_ssh_opts" git "$@"
      }

      flake_nix() {
        GIT_SSH_COMMAND="ssh $flake_ssh_opts" NIX_SSHOPTS="$flake_ssh_opts" ${nixBin} "$@"
      }

      state_dir="/var/lib/nix-nightly"
      repo_dir="$state_dir/repo"
      gcroots_dir="/nix/var/nix/gcroots/nix-nightly"
      mkdir -p "$state_dir" "$gcroots_dir"

      branch="main"
      repo_url="git@github.com:Irgendeinwer/NixOS-Dotfiles.git"

      if [ ! -d "$repo_dir/.git" ]; then
        rm -rf "$repo_dir"
        repo_git clone --branch "$branch" "$repo_url" "$repo_dir"
      fi

      cd "$repo_dir"
      git rebase --abort 2>/dev/null || true
      git merge --abort 2>/dev/null || true
      git remote set-url origin "$repo_url"
      repo_git fetch origin "$branch"
      git checkout -f -B "$branch" "origin/$branch"
      git reset --hard "origin/$branch"
      git clean -fdx

      lock_updated=0
      flake_nix flake update nixpkgs
      if git diff --quiet flake.lock; then
        echo "No nixpkgs updates available; pre-building current $branch closures."
      else
        echo "New nixpkgs revision found; updating remaining flake inputs."
        flake_nix flake update
        lock_updated=1
      fi

      hosts=(${lib.escapeShellArgs nightlyHosts})
      tmp_gcroots="$(mktemp -d "$gcroots_dir/.staging.XXXXXX")"
      cleanup_staging() {
        rm -rf "$tmp_gcroots"
      }
      trap cleanup_staging EXIT

      # Evaluate and build hosts sequentially so only one NixOS evaluation heap
      # stays resident in RAM at a time, while staging each result inside
      # /nix/var/nix/gcroots immediately so min-free auto-GC cannot sweep
      # earlier closures during subsequent builds.
      for host in "''${hosts[@]}"; do
        flake_nix build --out-link "$tmp_gcroots/host-$host" \
          ".#nixosConfigurations.$host.config.system.build.toplevel"
      done

      for link in "$tmp_gcroots"/host-*; do
        mv -Tf "$link" "$gcroots_dir/$(basename "$link")"
      done
      for existing in "$gcroots_dir"/host-*; do
        [ -L "$existing" ] || continue
        existing_name="$(basename "$existing")"
        keep=0
        for host in "''${hosts[@]}"; do
          if [ "$existing_name" = "host-$host" ]; then
            keep=1
            break
          fi
        done
        if [ "$keep" -eq 0 ]; then
          rm -f "$existing"
        fi
      done
      rmdir "$tmp_gcroots"
      trap - EXIT

      if [ "$lock_updated" -eq 1 ] && ! git diff --quiet flake.lock; then
        git config user.name "Irgendeinwer"
        git config user.email "175053643+Irgendeinwer@users.noreply.github.com"
        git add flake.lock
        git commit -m "chore(flake): update inputs"
        if ! repo_git push origin "HEAD:$branch"; then
          echo "nix-nightly-update: origin/$branch advanced during the build; skipping push of untested rebase so the next run evaluates cleanly against the new tip." >&2
          exit 0
        fi
      fi

      self_link="$gcroots_dir/host-${config.networking.hostName}"
      if [ -L "$self_link" ]; then
        self_toplevel="$(readlink -f "$self_link")"
        current_toplevel="$(readlink -f /run/current-system || true)"
        ${nixEnvBin} -p /nix/var/nix/profiles/system --set "$self_toplevel"
        if [ "$self_toplevel" != "$current_toplevel" ]; then
          "$self_toplevel/bin/switch-to-configuration" switch
        else
          echo "nix-nightly-update: ${config.networking.hostName} is already at $self_toplevel; skipping switch."
        fi
      fi
    '';
  };
in
{
  options.custom.services.buildServer = {
    enable = lib.mkEnableOption "Nix build server (on-demand ssh-ng, Harmonia cache, and nightly auto-builder)";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the Harmonia HTTP binary cache port (TCP 5000) in the firewall.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = config.custom.system.container.authorizedKeys;
      defaultText = lib.literalExpression "config.custom.system.container.authorizedKeys";
      description = "SSH public keys authorized to submit on-demand distributed Nix builds.";
    };

    nightly = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run nightly flake.lock updates, pre-build host closures, and auto-upgrade this server.";
      };

      dates = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 02:15:00";
        description = "Nightly systemd.time(7) schedule in the host's local timezone.";
      };

      hosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          config.networking.hostName
          "junixbook"
          "junixos"
        ];
        defaultText = lib.literalExpression "[ config.networking.hostName \"junixbook\" \"junixos\" ]";
        description = "Flake nixosConfigurations to evaluate and pre-build into Harmonia each night.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.authorizedKeys != [ ];
        message = "custom.services.buildServer.authorizedKeys must not be empty when buildServer is enabled.";
      }
      {
        assertion = cfg.nightly.enable -> cfg.nightly.hosts != [ ];
        message = "custom.services.buildServer.nightly.hosts must not be empty when nightly builds are enabled.";
      }
    ];

    users.groups.nixbuilder = { };
    users.users.nixbuilder = {
      isSystemUser = true;
      group = "nixbuilder";
      useDefaultShell = true;
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };

    nix = {
      daemonCPUSchedPolicy = lib.mkDefault "idle";
      daemonIOSchedClass = lib.mkDefault "idle";

      gc = lib.mkIf (!config.programs.nh.clean.enable) {
        automatic = lib.mkDefault true;
        dates = lib.mkDefault "Sun *-*-* 06:30:00";
        persistent = lib.mkDefault false;
        options = lib.mkDefault "--delete-older-than 14d";
      };

      settings = {
        trusted-users = [
          "root"
          "@wheel"
          "nixbuilder"
        ];
        keep-outputs = true;
        keep-derivations = true;
        # Automatically reclaim up to 60 GiB whenever free space drops below 20 GiB
        min-free = 21474836480;
        max-free = 64424509440;
        # Allow substituting junixos's CachyOS kernel instead of compiling it from source
        substituters = [ "https://cache.lantian.pub/lantian" ];
        trusted-public-keys = [ "lantian:WVGO7vsRMSEN+h7Lp7kv6SAmrkEXgUGbbXm7jMDjBuQ=" ];
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 5000 ];
    };

    sops.secrets = lib.mkIf cfg.nightly.enable {
      nix_nightly_ssh_key = {
        inherit sopsFile;
        key = "nix_nightly_ssh_key";
        owner = "root";
        mode = "0400";
      };
      nix_nightly_flake_ssh_key = {
        inherit sopsFile;
        key = "wallpaper_deploy_key";
        owner = "root";
        mode = "0400";
      };
    };

    # Generate a persistent signing keypair at boot BEFORE harmonia.service evaluates LoadCredential
    systemd.services = {
      harmonia-keygen = {
        description = "Generate persistent Harmonia binary cache signing key";
        wantedBy = [ "multi-user.target" ];
        before = [ "harmonia.service" ];
        requiredBy = [ "harmonia.service" ];
        unitConfig.ConditionPathExists = "!/var/lib/harmonia/cache-priv-key.pem";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "harmonia";
          StateDirectoryMode = "0755";
          UMask = "0077";
        };
        script = ''
          ${nixStoreBin} --generate-binary-cache-key \
            "${config.networking.hostName}-1" \
            /var/lib/harmonia/cache-priv-key.pem \
            /var/lib/harmonia/cache-pub-key.pem
          chmod 0400 /var/lib/harmonia/cache-priv-key.pem
          chmod 0644 /var/lib/harmonia/cache-pub-key.pem
        '';
      };

      harmonia.serviceConfig = lib.mkIf config.boot.isContainer {
        PrivateUsers = lib.mkForce false;
      };

      nix-nightly-update = lib.mkIf cfg.nightly.enable {
        description = "Nightly Nix flake update, closure pre-build, and server upgrade";
        after = [
          "network-online.target"
          "nix-daemon.socket"
        ];
        wants = [ "network-online.target" ];
        environment = {
          TMPDIR = "/var/tmp";
          NIX_REMOTE = lib.mkIf config.nix.daemon.enable "daemon";
        };
        restartIfChanged = false;
        stopIfChanged = false;
        unitConfig.X-StopOnRemoval = false;
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nix-nightly";
          TimeoutStartSec = "4h";
          CPUSchedulingPolicy = "idle";
          IOSchedulingClass = "idle";
          ExecStart = lib.getExe nightlyScript;
        };
      };
    };

    services.harmonia.cache = {
      enable = true;
      signKeyPaths = [ "/var/lib/harmonia/cache-priv-key.pem" ];
      settings = {
        bind = "[::]:5000";
        priority = 30;
      };
    };

    systemd.timers.nix-nightly-update = lib.mkIf cfg.nightly.enable {
      description = "Run Nix nightly flake update and pre-build strictly overnight";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.nightly.dates;
        # Never catch up during daytime after an overnight power-off
        Persistent = false;
        RandomizedDelaySec = "5m";
      };
    };
  };
}
