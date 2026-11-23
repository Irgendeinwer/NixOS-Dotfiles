{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.ai;
  isContainer = config.boot.isContainer or false;
  isLoopbackHost = builtins.elem cfg.litellm.host [
    "127.0.0.1"
    "::1"
    "[::1]"
    "localhost"
  ];

  # Environment variable names: GEMINI_KEY_1 ... GEMINI_KEY_N
  keyIndices = lib.range 1 cfg.geminiKeyCount;
  keyEnvVars = map (i: "GEMINI_KEY_${toString i}") keyIndices;

  commonModelInfo = {
    max_input_tokens = 1048576;
    max_output_tokens = 65536;
    supports_function_calling = true;
    supports_vision = true;
    supports_reasoning = true;
  };

  # Current free-tier Gemini lineup:
  # - gemini-4-hydrogen: primary reasoning & agentic model (20 RPD/key)
  # - gemini-3.8-flash: overflow fallback if Hydrogen's daily cap is exhausted (20 RPD/key)
  # - gemini-flash-lite: high-quota auxiliary model for compression/titles (500 RPD/key)
  models = [
    {
      name = "gemini-4-hydrogen";
      target = "gemini/gemini-4-hydrogen";
    }
    {
      name = "gemini-3.8-flash";
      target = "gemini/gemini-3.8-flash";
    }
    {
      name = "gemini-flash-lite";
      target = "gemini/gemini-3.5-flash-lite";
    }
  ];

  modelList = lib.concatMap (
    m:
    map (envVar: {
      model_name = m.name;
      litellm_params = {
        model = m.target;
        api_key = "os.environ/${envVar}";
      };
      model_info = commonModelInfo;
    }) keyEnvVars
  ) models;

  envLine = i: "GEMINI_KEY_${toString i}=${config.sops.placeholder."gemini_key_${toString i}"}";

  # Wrapper script that retrieves the decrypted Tavily key from RAM
  tavilyMcp = pkgs.writeShellScriptBin "tavily-mcp" ''
    export TAVILY_API_KEY="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.tavily_key_1.path})"
    exec ${pkgs.nodejs}/bin/npx -y tavily-mcp@latest "$@"
  '';
in
{
  options.custom.services.ai = {
    enable = lib.mkEnableOption "AI service stack (Gemini rotation, LiteLLM, Tavily, and MCP)";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.custom.user;
      description = "User who owns the decrypted Tavily secret.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/ai.yaml;
      description = "Path to the sops-encrypted AI secrets file.";
    };

    geminiKeyCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Number of Gemini project keys to register and rotate.";
    };

    litellm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        defaultText = lib.literalExpression "config.custom.services.ai.enable";
        description = "Whether to run the local LiteLLM OpenAI-compatible gateway.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Bind address for the LiteLLM HTTP proxy.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 4000;
        description = "TCP port for the LiteLLM HTTP proxy.";
      };
    };

    tavily.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable || cfg.mcp.enable;
      defaultText = lib.literalExpression "ai.enable || ai.mcp.enable";
      description = "Whether to decrypt tavily_key_1 from secretsFile.";
    };

    mcp.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable && (config.custom.desktop.enable or false);
      defaultText = lib.literalExpression "ai.enable && custom.desktop.enable";
      description = "Whether to install desktop MCP servers (tavily-mcp, playwright-mcp, nodejs).";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.litellm.enable {
      sops.secrets = lib.genAttrs (map (i: "gemini_key_${toString i}") keyIndices) (_: {
        sopsFile = cfg.secretsFile;
        restartUnits = [ "litellm.service" ];
      });

      sops.templates."litellm-env" = {
        content = lib.concatStringsSep "\n" (map envLine keyIndices);
      };

      services.litellm = {
        enable = true;
        inherit (cfg.litellm) host port;
        environmentFile = config.sops.templates."litellm-env".path;
        environment = lib.optionalAttrs isLoopbackHost {
          LITELLM_DANGEROUSLY_PERMIT_WEAK_OR_UNSET_MASTER_KEY = "true";
        };
        settings = {
          general_settings = lib.optionalAttrs isLoopbackHost {
            # LiteLLM >= 1.108 refuses to start without a master_key unless
            # explicitly permitted. Safe when bound strictly to loopback for
            # local callers (Hermes, desktop CLI tools).
            dangerously_permit_weak_or_unset_master_key = true;
          };
          model_list = modelList;
          litellm_settings = {
            # Gemini 4 Hydrogen ignores/rejects unsupported OpenAI sampling params
            # (such as frequency_penalty / presence_penalty); drop them cleanly.
            drop_params = true;
          };
          router_settings = {
            routing_strategy = "least-busy";
            num_retries = cfg.geminiKeyCount;
            allowed_fails = 1;
            cooldown_time = 65;
            retry_after = 3;
            model_group_alias = {
              "gemini-flash" = "gemini-4-hydrogen";
            };
            fallbacks = [
              { "gemini-4-hydrogen" = [ "gemini-3.8-flash" ]; }
            ];
          };
        };
      };

      # Upstream sets DynamicUser = true and PrivateUsers = true, which fail
      # inside systemd-nspawn containers without unprivileged user namespaces.
      users.groups.litellm = lib.mkIf isContainer { };
      users.users.litellm = lib.mkIf isContainer {
        isSystemUser = true;
        group = "litellm";
        home = config.services.litellm.stateDir;
      };
      systemd.services.litellm.serviceConfig = lib.mkIf isContainer {
        DynamicUser = lib.mkForce false;
        User = "litellm";
        Group = "litellm";
        PrivateUsers = lib.mkForce false;
        ExecStartPre = lib.mkBefore [
          "+${pkgs.coreutils}/bin/chown -R litellm:litellm ${config.services.litellm.stateDir}"
        ];
      };
    })

    (lib.mkIf (cfg.tavily.enable || cfg.mcp.enable) {
      sops.secrets.tavily_key_1 = {
        sopsFile = cfg.secretsFile;
        owner = cfg.user;
        mode = "0400";
      };
    })

    (lib.mkIf cfg.mcp.enable {
      environment.systemPackages = [
        pkgs.nodejs
        tavilyMcp
        # Browser automation MCP server (`playwright-mcp`), maintained by
        # Microsoft and packaged in nixpkgs with Playwright's NixOS-patched
        # browsers, so it updates with the flake instead of npx at runtime.
        pkgs.playwright-mcp
      ];
    })
  ];
}
