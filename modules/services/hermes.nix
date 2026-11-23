{
  config,
  lib,
  pkgs,
  inputs ? { },
  ...
}:
let
  cfg = config.custom.services.hermes;
  isContainer = config.boot.isContainer or false;
  hasUpstreamModule = inputs ? hermes-agent;
  primaryUser = config.custom.user or "julian";

  aiCfg = config.custom.services.ai or { };
  litellmCfg = aiCfg.litellm or { };
  litellmPort = litellmCfg.port or 4000;
  tavilyEnabled = (aiCfg.tavily.enable or false) || (aiCfg.mcp.enable or false);

  matrixSvcCfg = config.custom.services.matrix or { };
  localMatrixEnabled = matrixSvcCfg.enable or false;
  matrixPort = matrixSvcCfg.port or 6167;

  portalCfg = config.custom.services.portal or { };
  portalEnabled = portalCfg.enable or false;
  portalDomainSuffix = portalCfg.domainSuffix or "${config.networking.hostName}.internal";
  matrixServerName = matrixSvcCfg.serverName or portalDomainSuffix;

  stateDir = "/var/lib/hermes";
  defaultSshKeyPath = "${stateDir}/.ssh/id_hermes_box";
  sshKeyPath =
    if cfg.ssh.privateKeyFile != null then "${cfg.ssh.privateKeyFile}" else defaultSshKeyPath;

  sopsFile = ../../secrets + "/${config.networking.hostName}.yaml";
  hasHermesEnvInRepo =
    builtins.pathExists sopsFile
    && builtins.match "(^|.*\n)hermes_env:.*" (builtins.readFile sopsFile) != null;
  useSopsHermesEnv =
    cfg.enable && cfg.matrix.enable && cfg.environmentFile == null && cfg.useSopsSecret;
  hermesEnvPath =
    if cfg.environmentFile != null then
      "${cfg.environmentFile}"
    else if useSopsHermesEnv then
      config.sops.secrets.hermes_env.path
    else
      null;

  defaultPackage =
    if hasUpstreamModule then
      inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.minimal.override {
        extraDependencyGroups = [ "matrix" ];
      }
    else
      pkgs.emptyDirectory;

  auxSlot = {
    provider = "custom:litellm";
    model = cfg.llm.auxiliaryModel;
    base_url = cfg.llm.baseUrl;
  };

  auxiliaryConfig = lib.genAttrs [
    "approval"
    "background_review"
    "compression"
    "curator"
    "goal_judge"
    "group_router"
    "kanban_decomposer"
    "mcp"
    "memory_query_rewrite"
    "monitor"
    "profile_describer"
    "title_generation"
    "triage_specifier"
    "vision"
  ] (_: auxSlot);

  modelMeta = {
    context_length = cfg.llm.contextLength;
    supports_vision = true;
  };

  afterUnits =
    lib.optional (litellmCfg.enable or false) "litellm.service"
    ++ lib.optional cfg.searx.enable "searx.service"
    ++ lib.optional (cfg.matrix.enable && localMatrixEnabled) "continuwuity.service";
in
{
  imports = lib.optional hasUpstreamModule inputs.hermes-agent.nixosModules.default;

  options.custom.services.hermes = {
    enable = lib.mkEnableOption "Hermes Agent gateway with SearXNG search and SSH Ubuntu sandbox";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression ''
        inputs.hermes-agent.packages.''${system}.minimal.override {
          extraDependencyGroups = [ "matrix" ];
        }
      '';
      description = "Hermes Agent package used for the gateway service and host CLI.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Environment file supplying Matrix credentials (`MATRIX_PASSWORD` or
        `MATRIX_ACCESS_TOKEN`); `null` reads `hermes_env` from `sopsFile` when
        present and `matrix.enable` is true.
      '';
    };

    useSopsSecret = lib.mkOption {
      type = lib.types.bool;
      default = hasHermesEnvInRepo;
      defaultText = lib.literalExpression "hasHermesEnvInRepo";
      description = "Automatically load `hermes_env` from `secrets/<hostName>.yaml` via sops-nix.";
    };

    llm = {
      baseUrl = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "http://127.0.0.1:${toString litellmPort}/v1";
        defaultText = lib.literalExpression ''"http://127.0.0.1:''${toString ai.litellm.port}/v1"'';
        description = "OpenAI-compatible LiteLLM base URL used by Hermes Agent.";
      };

      primaryModel = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "gemini-4-hydrogen";
        description = "Primary model routed via LiteLLM for main agent turns.";
      };

      fallbackModel = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "gemini-3.8-flash";
        description = "Overflow fallback model when the primary RPD pool is exhausted.";
      };

      auxiliaryModel = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "gemini-flash-lite";
        description = ''
          High-quota model pinned to all auxiliary slots (compression, titles,
          smart approvals, background review) to preserve primary RPD quota.
        '';
      };

      contextLength = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1048576;
        description = "Context window advertised for the LiteLLM Gemini models.";
      };
    };

    searx = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        defaultText = lib.literalExpression "config.custom.services.hermes.enable";
        description = "Run a local loopback SearXNG JSON metasearch instance for `web_search`.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8888;
        description = "Loopback TCP port (`127.0.0.1:<port>`) for SearXNG.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Optional environment file setting `SEARX_SECRET_KEY`; `null`
          auto-generates a persistent key in `/var/lib/searx/secret_key`.
        '';
      };
    };

    ssh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Execute terminal/file tool commands over SSH inside the sibling
          Ubuntu 26.04.1 LTS (`resolute`) `systemd-nspawn` sandbox container.
        '';
      };

      host = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "hermes-box.local";
        description = "Hostname or IP address of the sibling Ubuntu `hermes-box` container.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 22;
        description = "SSH TCP port exposed by `hermes-box`.";
      };

      user = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "hermes";
        description = "Unprivileged SSH login user inside `hermes-box`.";
      };

      remoteCwd = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "/home/hermes/workspace";
        description = "Default working directory inside `hermes-box`.";
      };

      privateKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Explicit SSH private key path; `null` auto-generates an Ed25519 key at
          `/var/lib/hermes/.ssh/id_hermes_box` on first service start.
        '';
      };

      timeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 300;
        description = "Per-command timeout in seconds for the SSH terminal backend.";
      };
    };

    matrix = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = localMatrixEnabled;
        defaultText = lib.literalExpression "config.custom.services.matrix.enable";
        description = "Connect Hermes Agent's native Matrix (`mautrix`) adapter.";
      };

      homeserverUrl = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default =
          if localMatrixEnabled then
            "http://127.0.0.1:${toString matrixPort}"
          else
            "https://matrix.${portalDomainSuffix}";
        defaultText = lib.literalExpression ''
          if matrix.enable then "http://127.0.0.1:6167" else "https://matrix.<domainSuffix>"
        '';
        description = "Matrix homeserver base URL used by the Hermes gateway.";
      };

      botLocalpart = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "hermes";
        description = "Localpart of the Hermes bot account (`@<botLocalpart>:<serverName>`).";
      };

      allowedUsers = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [ "@${primaryUser}:${matrixServerName}" ];
        defaultText = lib.literalExpression ''[ "@<custom.user>:<matrix.serverName>" ]'';
        description = "Allowlisted Matrix user IDs permitted to trigger Hermes Agent.";
      };

      deviceId = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "HERMES_JUNIXSRV";
        description = "Stable Matrix device ID preserving E2EE state across restarts.";
      };

      autoThread = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically create Matrix threads for multi-user room replies.";
      };

      dmAutoThread = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Keep 1:1 Matrix DMs linear unless explicitly threaded.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions =
        lib.optional cfg.enable {
          assertion = hasUpstreamModule;
          message = "custom.services.hermes: flake input `hermes-agent` is required when enabled.";
        }
        ++ lib.optional (cfg.enable && cfg.matrix.enable) {
          assertion = cfg.matrix.allowedUsers != [ ];
          message = "custom.services.hermes.matrix: allowedUsers must not be empty.";
        };

      custom.services.portal.services = {
        searxng = lib.mkIf (portalEnabled && cfg.searx.enable) {
          title = lib.mkDefault "SearXNG";
          description = lib.mkDefault "Private loopback metasearch JSON engine for Hermes";
          category = lib.mkDefault "Infrastructure";
          badge = lib.mkDefault "127.0.0.1:${toString cfg.searx.port}";
          icon = lib.mkDefault "globe";
          systemdUnit = lib.mkDefault "searx.service";
          hintCommand = lib.mkDefault (
            "ssh -N -L ${toString cfg.searx.port}:127.0.0.1:${toString cfg.searx.port} "
            + "${primaryUser}@{host}"
          );
          order = lib.mkDefault 36;
        };

        hermes = lib.mkIf (portalEnabled && cfg.enable) {
          title = lib.mkDefault "Hermes Agent";
          description = lib.mkDefault "Autonomous Matrix agent executing in Ubuntu 26.04 sandbox";
          category = lib.mkDefault "Productivity";
          badge = lib.mkDefault (if cfg.ssh.enable then "Matrix · SSH" else "Matrix · Local");
          icon = lib.mkDefault "bot";
          systemdUnit = lib.mkDefault "hermes-agent.service";
          hintCommand = lib.mkDefault "ssh ${primaryUser}@{host} journalctl -u hermes-agent -n 50";
          order = lib.mkDefault 19;
        };
      };
    }

    (lib.mkIf cfg.searx.enable {
      services.searx = {
        enable = true;
        configureUwsgi = false;
        configureNginx = false;
        redisCreateLocally = false;
        inherit (cfg.searx) environmentFile;
        settings = {
          server = {
            bind_address = "127.0.0.1";
            inherit (cfg.searx) port;
            secret_key = "$SEARX_SECRET_KEY";
            limiter = false;
            image_proxy = false;
          };
          search.formats = [
            "html"
            "json"
          ];
        };
      };

      systemd.services = {
        searx-init = lib.mkIf (cfg.searx.environmentFile == null) {
          serviceConfig = {
            StateDirectory = "searx";
            StateDirectoryMode = "0700";
          };
          script = lib.mkBefore ''
            secret_file=/var/lib/searx/secret_key
            if [ ! -s "$secret_file" ]; then
              umask 077
              ${pkgs.openssl}/bin/openssl rand -hex 32 > "$secret_file"
            fi
            export SEARX_SECRET_KEY="$(cat "$secret_file")"
          '';
        };

        searx.serviceConfig = lib.mkIf isContainer {
          DynamicUser = lib.mkForce false;
          PrivateUsers = lib.mkForce false;
          ProtectProc = lib.mkForce "default";
          ProtectHostname = lib.mkForce false;
          ProtectClock = lib.mkForce false;
        };
      };
    })

    (lib.mkIf (cfg.enable && hasUpstreamModule) {
      users.users.${primaryUser}.extraGroups = [ "hermes" ];

      services.avahi.nssmdns4 = lib.mkIf (cfg.ssh.enable && lib.hasSuffix ".local" cfg.ssh.host) (
        lib.mkDefault true
      );

      sops.secrets =
        lib.optionalAttrs useSopsHermesEnv {
          hermes_env = {
            inherit sopsFile;
            key = "hermes_env";
            owner = "hermes";
            group = "hermes";
            mode = "0400";
            restartUnits = [ "hermes-agent.service" ];
          };
        }
        // lib.optionalAttrs tavilyEnabled {
          tavily_key_1.restartUnits = [ "hermes-agent.service" ];
        };

      sops.templates."hermes-ai-env" = lib.mkIf tavilyEnabled {
        owner = "hermes";
        group = "hermes";
        mode = "0400";
        content = "TAVILY_API_KEY=${config.sops.placeholder.tavily_key_1}\n";
      };

      systemd.services.hermes-agent = {
        after = afterUnits;
        wants = afterUnits;
        preStart = lib.mkIf (cfg.ssh.enable && cfg.ssh.privateKeyFile == null) (
          lib.mkBefore ''
            install -d -m 0700 "${stateDir}/.ssh"
            if [ ! -s "${defaultSshKeyPath}" ]; then
              ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" \
                -C "hermes@${config.networking.hostName}" \
                -f "${defaultSshKeyPath}"
            fi
            chmod 0600 "${defaultSshKeyPath}"
            chmod 0644 "${defaultSshKeyPath}.pub"
          ''
        );
        serviceConfig = {
          MemoryHigh = "2G";
          MemoryMax = "3G";
        };
      };
    })

    (lib.optionalAttrs hasUpstreamModule (
      lib.mkIf cfg.enable {
        services.hermes-agent = {
          enable = true;
          inherit (cfg) package;
          inherit stateDir;
          addToSystemPackages = lib.mkDefault true;
          extraPackages = [ pkgs.openssh ];

          environment =
            lib.optionalAttrs cfg.searx.enable {
              SEARXNG_URL = "http://127.0.0.1:${toString cfg.searx.port}";
            }
            // lib.optionalAttrs cfg.matrix.enable {
              MATRIX_HOMESERVER = cfg.matrix.homeserverUrl;
              MATRIX_USER_ID = "@${cfg.matrix.botLocalpart}:${matrixServerName}";
              MATRIX_ALLOWED_USERS = lib.concatStringsSep "," cfg.matrix.allowedUsers;
              MATRIX_DEVICE_ID = cfg.matrix.deviceId;
              MATRIX_AUTO_THREAD = lib.boolToString cfg.matrix.autoThread;
              MATRIX_DM_AUTO_THREAD = lib.boolToString cfg.matrix.dmAutoThread;
            };

          environmentFiles =
            lib.optional tavilyEnabled config.sops.templates."hermes-ai-env".path
            ++ lib.optional (hermesEnvPath != null) hermesEnvPath;

          settings = {
            providers.litellm = {
              api = cfg.llm.baseUrl;
              transport = "chat_completions";
              session_affinity_header = "x-litellm-session-id";
              models = {
                ${cfg.llm.primaryModel} = modelMeta;
                ${cfg.llm.fallbackModel} = modelMeta;
                ${cfg.llm.auxiliaryModel} = modelMeta;
              };
            };

            model = {
              provider = "custom:litellm";
              default = cfg.llm.primaryModel;
              base_url = cfg.llm.baseUrl;
              context_length = cfg.llm.contextLength;
              supports_vision = true;
            };

            fallback_providers = [
              {
                provider = "custom:litellm";
                model = cfg.llm.fallbackModel;
                base_url = cfg.llm.baseUrl;
              }
            ];

            auxiliary = auxiliaryConfig;

            web = {
              search_backend = if cfg.searx.enable then "searxng" else "";
              extract_backend = if tavilyEnabled then "tavily" else "";
              keyless_fallback = true;
              keyless_rescue = true;
            };

            terminal = {
              backend = if cfg.ssh.enable then "ssh" else "local";
              ssh_host = cfg.ssh.host;
              ssh_user = cfg.ssh.user;
              ssh_port = cfg.ssh.port;
              ssh_key = sshKeyPath;
              ssh_persistent = true;
              persistent_shell = true;
              cwd = if cfg.ssh.enable then cfg.ssh.remoteCwd else "${stateDir}/workspace";
              inherit (cfg.ssh) timeout;
            };

            agent.environment_hint = lib.mkIf cfg.ssh.enable (
              "Terminal commands run over SSH inside hermes-box (Ubuntu 26.04.1 LTS resolute, "
              + "cwd ${cfg.ssh.remoteCwd}) with passwordless sudo apt, uv, pip, npm, and git."
            );
          };
        };
      }
    ))
  ];
}
