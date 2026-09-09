{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.services.ai;

  # List of environment variable names: GEMINI_KEY_1 ... GEMINI_KEY_x
  keyEnvVars = map (i: "GEMINI_KEY_${toString i}") (lib.range 1 cfg.geminiKeyCount);

  # Fallback priority tiers
  models = [
    {
      name = "gemini-flash";
      target = "gemini/gemini-3.8-flash";
    }
    {
      name = "gemini-3.7";
      target = "gemini/gemini-3.7-flash";
    }
    {
      name = "gemini-3.6";
      target = "gemini/gemini-3.6-flash";
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
    }) keyEnvVars
  ) models;

  # Wrapper script that retrieves the decrypted Tavily key from RAM
  tavilyMcp = pkgs.writeShellScriptBin "tavily-mcp" ''
    export TAVILY_API_KEY="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.tavily_key_1.path})"
    exec ${pkgs.nodejs}/bin/npx -y tavily-mcp@latest "$@"
  '';
in
{
  options.custom.services.ai = {
    enable = lib.mkEnableOption "AI developer stack (Gemini rotation, LiteLLM, and Tavily MCP)";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.custom.user;
      description = "User who owns the decrypted Tavily secret for MCP execution.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/ai.yaml;
      description = "Path to the sops-encrypted AI secrets file.";
    };

    geminiKeyCount = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Number of Gemini project keys to register and rotate.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets =
      (lib.genAttrs (map (i: "gemini_key_${toString i}") (lib.range 1 cfg.geminiKeyCount)) (_: {
        sopsFile = cfg.secretsFile;
      }))
      // {
        tavily_key_1 = {
          sopsFile = cfg.secretsFile;
          owner = cfg.user;
          mode = "0400";
        };
      };

    sops.templates."litellm-env" = {
      content = lib.concatStringsSep "\n" (
        map (i: "GEMINI_KEY_${toString i}=${config.sops.placeholder."gemini_key_${toString i}"}") (
          lib.range 1 cfg.geminiKeyCount
        )
      );
    };

    services.litellm = {
      enable = true;
      host = "127.0.0.1";
      port = 4000;
      environmentFile = config.sops.templates."litellm-env".path;
      settings = {
        model_list = modelList;
        router_settings = {
          routing_strategy = "least-busy";
          num_retries = 5;
          allowed_fails = 1;
          cooldown_time = 30;
          retry_after = 0.5;
          fallbacks = [
            {
              "gemini-flash" = [
                "gemini-3.7"
                "gemini-3.6"
              ];
            }
            { "gemini-3.7" = [ "gemini-3.6" ]; }
          ];
        };
      };
    };

    environment.systemPackages = [
      pkgs.nodejs
      tavilyMcp
    ];
  };
}
