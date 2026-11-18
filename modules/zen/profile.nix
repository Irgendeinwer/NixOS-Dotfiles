# Adopt a host's existing profile while sharing the same settings and mods.
# This is explicitly imported by hosts; it is not in the shared module scanner.
{ profilePath }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  zen = config.programs.zen-browser;
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
      "--manifest"
      (toString manifest)
      "--backup-root"
      backupRoot
    ];
in
{
  config = lib.mkMerge [
    {
      programs.zen-browser = {
        configPath = ".zen";
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
    }
    (lib.mkIf zen.enable {
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
    })
  ];
}
