{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.buildServer;
  sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";

  notifyEnabled = cfg.enable && cfg.nightly.enable && cfg.nightly.notify.enable;
  # `config.sops.secrets.<name>.path` only exists when the matching entry below
  # is declared, so guard the lookup behind the same condition (Nix `if` is lazy).
  webhookPath =
    if notifyEnabled then
      config.sops.secrets.nix_nightly_webhook.path
    else
      "/run/secrets/nix_nightly_webhook";
  notifyEnabledStr = if notifyEnabled then "1" else "0";

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
      pkgs.curl
      pkgs.git
      pkgs.jq
      pkgs.openssh
    ];
    text = ''
      notify_enabled=${lib.escapeShellArg notifyEnabledStr}
      webhook_file=${lib.escapeShellArg webhookPath}
      host_label=${lib.escapeShellArg config.networking.hostName}
      state_dir="/var/lib/nix-nightly"
      log_file="$state_dir/last-run.log"
      stage="startup"
      activation_deferred=0
      signal_received=0
      summary=""

      add_summary() {
        summary="$summary$1"$'\n'
      }

      format_duration() {
        local total="$1" hours minutes seconds
        hours=$((total / 3600))
        minutes=$(((total % 3600) / 60))
        seconds=$((total % 60))
        if [ "$hours" -gt 0 ]; then
          printf '%dh %dm %ds' "$hours" "$minutes" "$seconds"
        elif [ "$minutes" -gt 0 ]; then
          printf '%dm %ds' "$minutes" "$seconds"
        else
          printf '%ds' "$seconds"
        fi
      }

      # Inline helpers so ShellCheck can analyze cross-function globals rather
      # than treating variables consumed by these functions as unused.
      ${builtins.readFile ./scripts/nightly-notify.sh}
      ${builtins.readFile ./scripts/nightly-gcroots.sh}
      ${builtins.readFile ./scripts/nightly-log.sh}
      ${builtins.readFile ./scripts/nightly-finish.sh}
      ${builtins.readFile ./scripts/nightly-signals.sh}
      ${builtins.readFile ./scripts/nightly-activate.sh}

      nix_env_bin=${lib.escapeShellArg nixEnvBin}
      install_nightly_signal_traps

      # Start a fresh log before any preflight that can fail; never quote a
      # previous run's log as though it belonged to this one.
      prepare_private_log
      exec 5>&1 6>&2
      # Keep potentially sensitive command output in the root-only log, not journal.
      exec > >(tee -a "$log_file" >/dev/null) 2>&1
      tee_pid="$!"

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

      repo_dir="$state_dir/repo"
      gcroots_dir="/nix/var/nix/gcroots/nix-nightly"
      mkdir -p "$gcroots_dir"
      stage="clean stale gcroot staging"
      cleanup_stale_gcroot_staging

      branch="main"
      repo_url="git@github.com:Irgendeinwer/NixOS-Dotfiles.git"

      stage="sync $branch from $repo_url"
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

      stage="flake update"
      lock_updated=0
      flake_nix flake update nixpkgs
      if git diff --quiet flake.lock; then
        echo "No nixpkgs updates available; pre-building current $branch closures."
        add_summary "flake.lock: already current"
      else
        echo "New nixpkgs revision found; updating remaining flake inputs."
        flake_nix flake update
        lock_updated=1
        add_summary "flake.lock: updated"
      fi

      hosts=(${lib.escapeShellArgs nightlyHosts})
      add_summary "hosts: ''${hosts[*]}"
      tmp_gcroots="$(mktemp -d "$gcroots_dir/.staging.XXXXXX")"

      # Evaluate and build hosts sequentially so only one NixOS evaluation heap
      # stays resident in RAM at a time, while staging each result inside
      # /nix/var/nix/gcroots immediately so min-free auto-GC cannot sweep
      # earlier closures during subsequent builds.
      for host in "''${hosts[@]}"; do
        stage="pre-build $host"
        # Background + wait so the shell can handle SIGTERM during a stalled
        # client request and run the bounded notification/cleanup path.
        flake_nix build --out-link "$tmp_gcroots/host-$host" \
          ".#nixosConfigurations.$host.config.system.build.toplevel" &
        build_pid="$!"
        if wait "$build_pid"; then
          build_pid=""
        else
          build_status="$?"
          build_pid=""
          exit "$build_status"
        fi
      done

      stage="commit and push flake.lock"
      if [ "$lock_updated" -eq 1 ] && ! git diff --quiet flake.lock; then
        git config user.name "Irgendeinwer"
        git config user.email "175053643+Irgendeinwer@users.noreply.github.com"
        git add flake.lock
        git commit -m "chore(flake): update inputs"
        if repo_git push origin "HEAD:$branch"; then
          add_summary "push: pushed flake.lock to $branch"
        else
          echo "nix-nightly-update: could not push flake.lock; retaining the tested build and deferring activation until the next run." >&2
          add_summary "push: failed; activation deferred until the next run"
          activation_deferred=1
        fi
      else
        add_summary "push: not needed"
      fi

      complete_nightly_run
      stage="done"
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

      notify.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          POST a run summary to a Discord webhook whose URL is read at runtime
          from the `nix_nightly_webhook` sops key in this host's secrets file.
          Success, deferred-push warnings, and failure stage/exit codes are
          reported; full logs remain root-only on the host. Delivery is best
          effort and never fails the nightly run. See docs/recovery.md to
          create and enroll the webhook.
        '';
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

    sops.secrets.nix_nightly_ssh_key = lib.mkIf cfg.nightly.enable {
      inherit sopsFile;
      key = "nix_nightly_ssh_key";
      owner = "root";
      mode = "0400";
    };

    sops.secrets.nix_nightly_flake_ssh_key = lib.mkIf cfg.nightly.enable {
      inherit sopsFile;
      key = "wallpaper_deploy_key";
      owner = "root";
      mode = "0400";
    };

    sops.secrets.nix_nightly_webhook = lib.mkIf notifyEnabled {
      inherit sopsFile;
      key = "nix_nightly_webhook";
      owner = "root";
      mode = "0400";
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
          StateDirectoryMode = "0700";
          TimeoutStartSec = "4h";
          # Leave time for bounded cleanup and webhook retries after TimeoutStartSec.
          TimeoutStopSec = "40s";
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
