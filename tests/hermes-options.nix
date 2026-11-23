{
  nixpkgs,
  pkgs,
  self,
  sopsModule,
  hermesModule,
}:
let
  inherit (nixpkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  dummyCa = pkgs.writeText "dummy-junix-ca.pem" "TEST-CA\n";
  dummyHermesEnv = pkgs.writeText "dummy-hermes.env" "MATRIX_PASSWORD=test-secret\n";

  evalHermesWithInputs =
    inputsAttr: extraConfig:
    (lib.nixosSystem {
      inherit system;
      specialArgs.inputs = inputsAttr;
      modules = [
        sopsModule
        {
          options.custom.user = lib.mkOption {
            type = lib.types.str;
            default = "julian";
          };
          config.users.users.julian = {
            isNormalUser = true;
            home = "/home/julian";
          };
        }
        ../modules/nixos/pki.nix
        ../modules/services/portal.nix
        ../modules/services/ai.nix
        ../modules/services/matrix.nix
        ../modules/services/hermes.nix
        {
          networking.hostName = "junixsrv";
          system.stateVersion = "26.11";
        }
        extraConfig
      ];
    }).config;

  mockHermesInput.hermes-agent = {
    nixosModules.default = hermesModule;
    packages.${system}.minimal = lib.makeOverridable (_: pkgs.hello) { };
  };

  evalHermes = evalHermesWithInputs mockHermesInput;

  disabled = evalHermes { };

  enabledContainer = evalHermes {
    boot.isContainer = true;
    custom.system.security.localCa.certificateFile = dummyCa;
    custom.services = {
      portal.enable = true;
      ai.enable = true;
      matrix.enable = true;
      hermes = {
        enable = true;
        useSopsSecret = true;
      };
    };
  };

  explicitEnvAndLocal = evalHermes {
    boot.isContainer = false;
    custom.services = {
      matrix.enable = false;
      hermes = {
        enable = true;
        environmentFile = dummyHermesEnv;
        ssh.enable = false;
        searx.enable = false;
        matrix = {
          enable = true;
          allowedUsers = [ "@julian:example.internal" ];
        };
      };
    };
  };

  missingUpstream = evalHermesWithInputs { } {
    custom.services.hermes.enable = true;
  };

  emptyAllowedUsers = evalHermes {
    custom.services = {
      matrix.enable = true;
      hermes = {
        enable = true;
        matrix.allowedUsers = [ ];
      };
    };
  };

  openRegistrationNoToken = evalHermes {
    custom.services.matrix = {
      enable = true;
      allowRegistration = true;
    };
  };

  hasFailedAssertion =
    prefix: cfg: lib.any (a: !a.assertion && lib.hasPrefix prefix a.message) cfg.assertions;

  noModuleFailures =
    cfg:
    !(hasFailedAssertion "custom.services.hermes" cfg)
    && !(hasFailedAssertion "custom.services.matrix" cfg)
    && !(hasFailedAssertion "custom.services.portal" cfg)
    && !(hasFailedAssertion "services.hermes-agent" cfg);

  hermesSettings = enabledContainer.services.hermes-agent.settings;
  matrixGlobal = enabledContainer.services.matrix-continuwuity.settings.global;
  matrixVhost = enabledContainer.services.nginx.virtualHosts."matrix.junixsrv.internal";
  defaultVhost = enabledContainer.services.nginx.virtualHosts."junixsrv";

  serverHost = self.nixosConfigurations.junixsrv.config;
  desktopHost = self.nixosConfigurations.junixos.config;
  laptopHost = self.nixosConfigurations.junixbook.config;
in
assert !disabled.services.matrix-continuwuity.enable;
assert !disabled.services.searx.enable;
assert !disabled.services.hermes-agent.enable;
assert noModuleFailures disabled;
# Enabled container stack: Matrix (Continuwuity) + Portal + .well-known
assert noModuleFailures enabledContainer;
assert enabledContainer.services.matrix-continuwuity.enable;
assert matrixGlobal.server_name == "junixsrv.internal";
assert matrixGlobal.address == [ "127.0.0.1" ];
assert matrixGlobal.port == [ 6167 ];
assert !matrixGlobal.allow_federation;
assert !matrixGlobal.allow_registration;
assert !matrixGlobal.allow_announcements_check;
assert matrixGlobal.trusted_servers == [ ];
assert matrixGlobal.well_known.client == "https://matrix.junixsrv.internal";
assert !enabledContainer.systemd.services.continuwuity.serviceConfig.DynamicUser;
assert !enabledContainer.systemd.services.continuwuity.serviceConfig.PrivateUsers;
assert enabledContainer.systemd.services.continuwuity.serviceConfig.ProtectProc == "default";
assert matrixVhost.forceSSL;
assert matrixVhost.locations."/".proxyPass == "http://127.0.0.1:6167";
assert defaultVhost.locations ? "= /.well-known/matrix/client";
assert lib.hasInfix "$junix_matrix_base_url"
  defaultVhost.locations."= /.well-known/matrix/client".extraConfig;
assert lib.hasInfix ''Vary "Host"''
  defaultVhost.locations."= /.well-known/matrix/client".extraConfig;
assert lib.hasInfix "map $http_host $junix_matrix_base_url"
  enabledContainer.services.nginx.appendHttpConfig;
assert defaultVhost.locations ? "/_matrix/";
assert defaultVhost.locations."/_matrix/".proxyPass == "http://127.0.0.1:6167";
assert lib.hasInfix "client_max_body_size 67108864;" defaultVhost.locations."/_matrix/".extraConfig;
# Enabled container stack: SearXNG loopback JSON search
assert enabledContainer.services.searx.enable;
assert !enabledContainer.services.searx.configureUwsgi;
assert !enabledContainer.services.searx.configureNginx;
assert enabledContainer.services.searx.settings.server.bind_address == "127.0.0.1";
assert enabledContainer.services.searx.settings.server.port == 8888;
assert builtins.elem "json" enabledContainer.services.searx.settings.search.formats;
assert !enabledContainer.systemd.services.searx.serviceConfig.DynamicUser;
assert !enabledContainer.systemd.services.searx.serviceConfig.PrivateUsers;
assert enabledContainer.systemd.services.searx.serviceConfig.ProtectProc == "default";
# Enabled container stack: Hermes Agent + LiteLLM + Quota Aux + SSH Sandbox + SOPS
assert enabledContainer.services.hermes-agent.enable;
assert builtins.elem "hermes" enabledContainer.users.users.julian.extraGroups;
assert enabledContainer.services.avahi.enable;
assert enabledContainer.services.avahi.nssmdns4;
assert enabledContainer.sops.secrets ? hermes_env;
assert enabledContainer.sops.templates ? "hermes-ai-env";
assert builtins.length enabledContainer.services.hermes-agent.environmentFiles == 2;
assert enabledContainer.services.hermes-agent.environment.SEARXNG_URL == "http://127.0.0.1:8888";
assert
  enabledContainer.services.hermes-agent.environment.MATRIX_HOMESERVER == "http://127.0.0.1:6167";
assert
  enabledContainer.services.hermes-agent.environment.MATRIX_USER_ID == "@hermes:junixsrv.internal";
assert
  enabledContainer.services.hermes-agent.environment.MATRIX_ALLOWED_USERS
  == "@julian:junixsrv.internal";
assert hermesSettings.providers.litellm.api == "http://127.0.0.1:4000/v1";
assert hermesSettings.providers.litellm.session_affinity_header == "x-litellm-session-id";
assert hermesSettings.model.provider == "custom:litellm";
assert hermesSettings.model.default == "gemini-4-hydrogen";
assert (builtins.head hermesSettings.fallback_providers).model == "gemini-3.8-flash";
assert hermesSettings.auxiliary.compression.model == "gemini-flash-lite";
assert hermesSettings.auxiliary.title_generation.model == "gemini-flash-lite";
assert hermesSettings.auxiliary.approval.model == "gemini-flash-lite";
assert hermesSettings.auxiliary.curator.model == "gemini-flash-lite";
assert hermesSettings.auxiliary.background_review.model == "gemini-flash-lite";
assert hermesSettings.web.search_backend == "searxng";
assert hermesSettings.web.extract_backend == "tavily";
assert hermesSettings.terminal.backend == "ssh";
assert hermesSettings.terminal.ssh_host == "hermes-box.local";
assert hermesSettings.terminal.ssh_user == "hermes";
assert hermesSettings.terminal.cwd == "/home/hermes/workspace";
assert enabledContainer.systemd.services.hermes-agent.serviceConfig.MemoryMax == "3G";
assert !(builtins.elem 6167 enabledContainer.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 8888 enabledContainer.networking.firewall.allowedTCPPorts);
# Explicit env file + local backend fallback
assert noModuleFailures explicitEnvAndLocal;
assert !(explicitEnvAndLocal.sops.secrets ? hermes_env);
assert explicitEnvAndLocal.services.hermes-agent.settings.terminal.backend == "local";
assert
  explicitEnvAndLocal.services.hermes-agent.environment.MATRIX_HOMESERVER
  == "https://matrix.junixsrv.internal";
# Guard assertions
assert hasFailedAssertion "custom.services.hermes:" missingUpstream;
assert hasFailedAssertion "custom.services.hermes.matrix:" emptyAllowedUsers;
assert hasFailedAssertion "custom.services.matrix:" openRegistrationNoToken;
# Real host wiring across junixsrv, junixos, and junixbook
assert serverHost.custom.services.matrix.enable;
assert serverHost.custom.services.hermes.enable;
assert serverHost.services.matrix-continuwuity.enable;
assert serverHost.services.searx.enable;
assert serverHost.services.hermes-agent.enable;
assert serverHost.sops.secrets ? hermes_env;
assert lib.all (
  dep:
  (dep.pname or "") != "patchelf"
  || lib.versionAtLeast (dep.version or "0") "0.18"
  || dep.drvPath == pkgs.patchelf.drvPath
) (serverHost.custom.services.hermes.package.hermesNpmLib.pnpm.nativeBuildInputs or [ ]);
assert serverHost.custom.services.portal.services.matrix.subdomain == "matrix";
assert serverHost.custom.services.portal.services.hermes.icon == "bot";
assert serverHost.custom.services.portal.services.searxng.badge == "127.0.0.1:8888";
assert builtins.elem "matrix.junixsrv.internal"
  desktopHost.custom.system.remoteBuilder.extraHostAliases;
assert laptopHost.custom.services.tailscale.peers."matrix.junixsrv.internal" == "100.110.103.47";
pkgs.runCommand "hermes-options"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.shellcheck
    ];
  }
  ''
    bash -n ${../scripts/provision-hermes-box.sh}
    shellcheck ${../scripts/provision-hermes-box.sh}
    mkdir -p "$out"
  ''
