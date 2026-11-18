{
  config,
  lib,
  pkgs,
  profileName,
}:
let
  zen = config.programs.zen-browser;
  profileDir = "${zen.profilesPath}/${zen.profiles.${profileName}.path}";
  userJs = config.home.file."${profileDir}/user.js" or null;
  absoluteHomePath =
    path: if lib.hasPrefix "/" path then path else "${config.home.homeDirectory}/${path}";
  managedFile = path: (config.home.file.${path} or { enable = false; }).enable;
  otherTargets = map absoluteHomePath (
    builtins.filter managedFile [
      "${profileDir}/.keep"
      "${profileDir}/chrome/userChrome.css"
      "${profileDir}/chrome/userContent.css"
    ]
  );
in
# Check ownership of the registry and managed link targets before Home Manager
# writes any links. checkZenMods then checks membership in that registry.
lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
  PATH=${lib.makeBinPath [ pkgs.coreutils ]}:"$PATH" \
    ${pkgs.bash}/bin/bash ${../modules/home-manager/scripts/check-zen-profile.sh} ${
      lib.escapeShellArgs (
        [
          (absoluteHomePath zen.configPath)
          (absoluteHomePath profileDir)
          builtins.storeDir
          (if userJs != null && userJs.enable then "yes" else "no")
        ]
        ++ otherTargets
      )
    }
''
