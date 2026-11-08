{
  nixpkgs,
  system,
  pkgs,
}:
let
  inherit (nixpkgs) lib;
  evalContainer =
    {
      lix,
      enable ? true,
      daemonUser ? "root",
    }:
    lib.nixosSystem {
      inherit system;
      modules = [
        {
          options.custom.user = lib.mkOption {
            type = lib.types.str;
            default = "test";
          };
        }
        ../modules/nixos/container.nix
        {
          networking.hostName = "container-test";
          system.stateVersion = "26.11";
          custom.system.container.enable = enable;
          nix = {
            inherit daemonUser;
            package = if lix then pkgs.lixPackageSets.stable.lix else pkgs.nix;
          };
        }
      ];
    };
  lix = (evalContainer { lix = true; }).config;
  # Non-root users get nixpkgs's nix-nswrapper ExecStart; only test our assertion here.
  lixUnprivileged =
    (evalContainer {
      lix = true;
      daemonUser = "test";
    }).config;
  cpp = (evalContainer { lix = false; }).config;
  cppUnprivileged =
    (evalContainer {
      lix = false;
      daemonUser = "test";
    }).config;
  disabled =
    (evalContainer {
      lix = false;
      enable = false;
      daemonUser = "test";
    }).config;
  # Successful assertions may have diagnostics that are only valid on failure.
  wrapperAssertion =
    cfg:
    lib.findFirst (
      a: !a.assertion && lib.hasPrefix "custom.system.container: the legacy C++ Nix" a.message
    ) null cfg.assertions;
  cppExecStart = cpp.systemd.services.nix-daemon.serviceConfig.ExecStart;
  lixMonolithic = lix.systemd.units."nix-daemon.service".text;
  lixTemplate = lix.systemd.units."nix-daemon@.service".text;
in
assert lix.boot.isNspawnContainer && lix.boot.isContainer;
assert cpp.boot.isNspawnContainer && cpp.boot.isContainer;
assert !disabled.boot.isNspawnContainer;
assert lix.nix.settings.sandbox && !lix.nix.settings.sandbox-fallback;
assert lix.nix.settings.pasta-path == "";
assert !(cpp.nix.settings ? pasta-path);
assert lix.environment.sessionVariables.NIX_REMOTE == "daemon";
assert cpp.environment.sessionVariables.NIX_REMOTE == "daemon";
assert wrapperAssertion lix == null;
assert wrapperAssertion lixUnprivileged == null;
assert wrapperAssertion disabled == null;
assert wrapperAssertion cpp == null;
assert !(wrapperAssertion cppUnprivileged).assertion;
assert builtins.head cppExecStart == "";
assert lib.hasInfix "/bin/without-userns " (builtins.elemAt cppExecStart 1);
assert cpp.systemd.services.nix-daemon.environment.TMPDIR == "/var/tmp";
assert !(lib.hasInfix "without-userns" lixMonolithic);
assert !(lib.hasInfix "without-userns" lixTemplate);
assert !(lix.systemd.services.nix-daemon.serviceConfig ? ExecStart);
assert !(lix.systemd.services."nix-daemon@".serviceConfig ? ExecStart);
pkgs.runCommand "container-daemon-options" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  # Lix's packaged units, rather than the C++ daemon override, handle builds.
  grep -Fx 'Accept=yes' ${lix.nix.package}/lib/systemd/system/nix-daemon.socket
  grep -F -- '--for-socket-activation' ${lix.nix.package}/lib/systemd/system/nix-daemon@.service
  mkdir -p "$out"
''
