{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.buildServer;
  sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";

  nightlyEnabled = cfg.enable && cfg.nightly.enable;
  notifyEnabled = nightlyEnabled && cfg.nightly.notify.enable;
  # `config.sops.secrets.<name>.path` only exists when the matching entry below
  # is declared, so guard each lookup behind the same condition (Nix `if` is lazy).
  repoSshKeyPath =
    if nightlyEnabled then
      config.sops.secrets.nix_nightly_ssh_key.path
    else
      "/run/secrets/nix_nightly_ssh_key";
  wallpaperSshKeyPath =
    if nightlyEnabled then
      config.sops.secrets.nix_nightly_flake_ssh_key.path
    else
      "/run/secrets/nix_nightly_flake_ssh_key";
  webhookPath =
    if notifyEnabled then
      config.sops.secrets.nix_nightly_webhook.path
    else
      "/run/secrets/nix_nightly_webhook";
  notifyEnabledStr = if notifyEnabled then "1" else "0";

  validGithubRepo =
    repo: builtins.match "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+" repo != null && !(lib.hasSuffix ".git" repo);
  sanitizeRepoName = repo: builtins.replaceStrings [ "/" "." "-" ] [ "_" "_" "_" ] repo;

  extraDeployEntries = lib.imap0 (
    i: repo:
    let
      secretName = "nix_nightly_deploy_${sanitizeRepoName repo}";
    in
    {
      inherit repo secretName;
      alias = "github-flake-${toString (i + 1)}";
      secretKey = cfg.nightly.extraDeployKeys.${repo};
      keyPath =
        if nightlyEnabled then config.sops.secrets.${secretName}.path else "/run/secrets/${secretName}";
    }
  ) (builtins.attrNames cfg.nightly.extraDeployKeys);

  allFlakeDeployEntries = [
    {
      repo = "Irgendeinwer/wallpaper";
      alias = "github-flake-0";
      keyPath = wallpaperSshKeyPath;
    }
  ]
  ++ extraDeployEntries;

  mkSshHostBlock = host: keyPath: ''
    Host ${host}
      HostName github.com
      User git
      IdentityFile ${keyPath}
      IdentitiesOnly yes
      IdentityAgent none
      BatchMode yes
      StrictHostKeyChecking accept-new
  '';

  flakeSshConfig = pkgs.writeText "nix-nightly-flake-ssh-config" (
    lib.concatStringsSep "\n" (
      (map (entry: mkSshHostBlock entry.alias entry.keyPath) allFlakeDeployEntries)
      ++ [ (mkSshHostBlock "github.com" wallpaperSshKeyPath) ]
    )
  );

  flakeGitRewritePairs = lib.concatMap (entry: [
    {
      key = "url.ssh://git@${entry.alias}/${entry.repo}.insteadOf";
      value = "ssh://git@github.com/${entry.repo}";
    }
    {
      key = "url.ssh://git@${entry.alias}/${entry.repo}.insteadOf";
      value = "git@github.com:${entry.repo}";
    }
  ]) allFlakeDeployEntries;

  flakeGitEnvAssignments = lib.concatStringsSep " " (
    [ "GIT_CONFIG_COUNT=${lib.escapeShellArg (toString (builtins.length flakeGitRewritePairs))}" ]
    ++ lib.concatLists (
      lib.imap0 (i: pair: [
        "GIT_CONFIG_KEY_${toString i}=${lib.escapeShellArg pair.key}"
        "GIT_CONFIG_VALUE_${toString i}=${lib.escapeShellArg pair.value}"
      ]) flakeGitRewritePairs
    )
  );

  nixBin = lib.getExe' config.nix.package.out "nix";
  nixStoreBin = lib.getExe' config.nix.package.out "nix-store";
  nixEnvBin = lib.getExe' config.nix.package.out "nix-env";

  nightlyHosts = lib.unique cfg.nightly.hosts;
  nightlyStatusFile = "/var/lib/nix-nightly-status/status.json";

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
      status_file=${lib.escapeShellArg nightlyStatusFile}
      stage="startup"
      activation_deferred=0
      signal_received=0
      log_redirected=0
      summary=""

      # Inline helpers so ShellCheck can analyze cross-function globals rather
      # than treating variables consumed by these functions as unused.
      ${builtins.readFile ./scripts/nightly-summary.sh}
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
      # Keep potentially sensitive command output in the root-only log, not journal.
      start_private_log

      repo_ssh_key=${lib.escapeShellArg repoSshKeyPath}
      flake_ssh_keys=(
        ${lib.escapeShellArgs (map (entry: entry.keyPath) allFlakeDeployEntries)}
      )

      for key_path in "$repo_ssh_key" "''${flake_ssh_keys[@]}"; do
        if [ ! -s "$key_path" ]; then
          echo "nix-nightly-update: error: SSH key missing or empty at $key_path (enroll host in sops first)." >&2
          exit 1
        fi
      done

      common_ssh_opts="-o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
      repo_ssh_opts="-i $repo_ssh_key $common_ssh_opts"
      flake_ssh_opts="-F ${flakeSshConfig}"

      repo_git() {
        GIT_SSH_COMMAND="ssh $repo_ssh_opts" run_private git "$@"
      }

      flake_nix() {
        ${flakeGitEnvAssignments} \
          GIT_SSH_COMMAND="ssh $flake_ssh_opts" \
          NIX_SSHOPTS="$flake_ssh_opts" \
          run_private ${nixBin} "$@"
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
      repo_git rebase --abort 2>/dev/null || true
      repo_git merge --abort 2>/dev/null || true
      repo_git remote set-url origin "$repo_url"
      repo_git fetch origin "$branch"
      repo_git checkout -f -B "$branch" "origin/$branch"
      repo_git reset --hard "origin/$branch"
      repo_git clean -fdx

      stage="flake update"
      lock_updated=0
      flake_nix flake update nixpkgs
      if repo_git diff --quiet flake.lock; then
        echo "No nixpkgs updates available; pre-building current $branch closures."
        add_summary "nixpkgs: up to date; lockfile update skipped"
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
      if [ "$lock_updated" -eq 1 ] && ! repo_git diff --quiet flake.lock; then
        repo_git config user.name "Irgendeinwer"
        repo_git config user.email "175053643+Irgendeinwer@users.noreply.github.com"
        repo_git add flake.lock
        repo_git commit -m "chore(flake): update inputs"
        if repo_git push origin "HEAD:$branch"; then
          add_summary "push: pushed flake.lock to $branch"
        else
          echo "nix-nightly-update: could not push flake.lock; deferring activation and releasing staged roots on exit." >&2
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
      description = ''
        SSH public keys authorized to submit on-demand distributed Nix builds.
        These keys authenticate a trusted Nix daemon user and therefore grant
        root-equivalent access, not just permission to upload signed outputs.
      '';
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

      extraDeployKeys = lib.mkOption {
        type = lib.types.attrsOf lib.types.nonEmptyStr;
        default = { };
        example = {
          "Irgendeinwer/nix-private" = "nix_private_deploy_key";
        };
        description = ''
          Additional private GitHub repositories (`owner/repo`) fetched during
          `nix flake update` and pre-builds, mapped to sops secret keys in this
          host's secrets file. Each entry generates a dedicated SSH host alias
          and Git `insteadOf` rewrite so GitHub receives the repository-specific
          deploy key rather than the first key offered on `github.com`.
        '';
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
      {
        assertion =
          !cfg.nightly.enable || lib.all validGithubRepo (builtins.attrNames cfg.nightly.extraDeployKeys);
        message = "custom.services.buildServer.nightly.extraDeployKeys: attribute names must be GitHub 'owner/repo' slugs without a '.git' suffix.";
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
        # ssh-ng BuildDerivation requires trust for ordinary input-addressed
        # builds, not just unsigned uploads. Treat these SSH keys as root keys.
        trusted-users = [
          "root"
          "@wheel"
          "nixbuilder"
        ];
        keep-outputs = true;
        keep-derivations = true;
        # When free space drops below 20 GiB, collect toward a 60 GiB free-space target
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

    sops.secrets = lib.mkMerge [
      (lib.mkIf cfg.nightly.enable (
        {
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
        }
        // builtins.listToAttrs (
          map (entry: {
            name = entry.secretName;
            value = {
              inherit sopsFile;
              key = entry.secretKey;
              owner = "root";
              mode = "0400";
            };
          }) extraDeployEntries
        )
      ))
      (lib.mkIf notifyEnabled {
        nix_nightly_webhook = {
          inherit sopsFile;
          key = "nix_nightly_webhook";
          owner = "root";
          mode = "0400";
        };
      })
    ];

    # Sanitized run summary directory readable by the unprivileged status API;
    # `/var/lib/nix-nightly` itself remains 0700 root-only.
    systemd.tmpfiles.rules = lib.mkIf cfg.nightly.enable [
      "d /var/lib/nix-nightly-status 0755 root root -"
    ];

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
