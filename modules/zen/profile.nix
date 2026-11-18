# Adopt a host's existing profile while sharing the same settings and mods.
# This is explicitly imported by hosts; it is not in the shared module scanner.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  zen = config.programs.zen-browser;
  inherit (config.custom.desktop.zen) profilePath;
  profile = zen.profiles.default;
  relativeProfile = "${zen.profilesPath}/${profile.path}";
  absoluteHomePath =
    path: if lib.hasPrefix "/" path then path else "${config.home.homeDirectory}/${path}";
  profileDir = absoluteHomePath relativeProfile;
  backupRoot = "${config.xdg.stateHome}/nixos-dotfiles/zen-mod-backups";

  # Use regular profile copies rather than immutable store links: Zen's mod
  # manager edits/removes them. Validate and back up existing files first.
  manifest = import ./manifest.nix { inherit lib pkgs; };
  reconcile =
    mode:
    "${lib.getExe pkgs.python3} ${./reconcile-mods.py} "
    + lib.escapeShellArgs [
      mode
      "--profile"
      profileDir
      "--registry"
      (absoluteHomePath "${zen.configPath}/profiles.ini")
      "--manifest"
      (toString manifest)
      "--backup-root"
      backupRoot
    ];
in
{
  options.custom.desktop.zen.profilePath = lib.mkOption {
    type = lib.types.nullOr lib.types.nonEmptyStr;
    default = null;
    description = ''
      Existing profile directory relative to programs.zen-browser.profilesPath.
      Null leaves the profile unmanaged without changing the browser's registry location.
    '';
  };

  config = lib.mkIf (zen.enable && profilePath != null) {
    programs.zen-browser = {
      policies.ExtensionSettings = import ./extensions.nix { inherit lib; };
      profiles.default = {
        id = 0;
        isDefault = true;
        path = profilePath;
        settings = import ./settings.nix {
          palette = config.custom.theme.palette;
          zenVersion = lib.getVersion zen.package;
        };
        userChrome = import ./user-chrome.nix { palette = config.custom.theme.palette; };
      };
    };

    # Zen's existing registry remains authoritative, including install entries.
    home.file."${zen.configPath}/profiles.ini".enable = false;

    home.activation.checkExistingZenProfile = import ../../lib/zen-profile-guard.nix {
      inherit config lib pkgs;
      profileName = "default";
    };

    assertions = [
      {
        assertion = profile.mods == [ ] && !profile.sine.enable;
        message = "Do not combine the shared pinned Zen Mods with the upstream mods or Sine activation; see docs/zen-browser.md.";
      }
    ];

    home.activation.checkZenMods =
      lib.hm.dag.entryBetween
        [ "checkLinkTargets" ]
        [
          "checkExistingZenProfile"
        ]
        ''
          ${reconcile "check"}
        '';

    # Recheck under the browser's actual fcntl profile lock, then perform the
    # collision-safe writes before HM links or upstream profile fragments run.
    home.activation.reconcileZenMods =
      lib.hm.dag.entryBetween
        [
          "linkGeneration"
          "zen-browser-default"
        ]
        [ "writeBoundary" ]
        ''
          if [[ -v DRY_RUN ]]; then
            printf '%s\n' ${lib.escapeShellArg "zen-mods: would reconcile the pinned mods for ${profileDir}"}
          else
            ${reconcile "apply"}
          fi
        '';
  };
}
