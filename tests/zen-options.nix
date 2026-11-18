{
  nixpkgs,
  pkgs,
  self,
}:
let
  inherit (nixpkgs) lib;
  home = cfg: cfg.home-manager.users.${cfg.custom.user};
  desktop = home self.nixosConfigurations.junixos.config;
  laptop = home self.nixosConfigurations.junixbook.config;
  server = home self.nixosConfigurations.junixsrv.config;
  zen = desktop.programs.zen-browser;
  profile = zen.profiles.default;
  managedZenFiles = lib.filterAttrs (
    _: file: file.enable && lib.hasPrefix ".zen/" file.target
  ) desktop.home.file;
  wrapperHas =
    args: key: value:
    lib.any (
      i:
      builtins.elemAt args i == "--set"
      && builtins.elemAt args (i + 1) == key
      && builtins.elemAt args (i + 2) == value
    ) (lib.range 0 (builtins.length args - 3));
in
assert zen.enable && zen.configPath == ".zen" && zen.profilesPath == ".zen";
assert profile.id == 0 && profile.isDefault && profile.path == "mpjpva0z.default";
assert profile.settings."browser.aboutConfig.showWarning" == false;
assert !desktop.home.file.".zen/profiles.ini".enable;
assert builtins.elem "checkLinkTargets" desktop.home.activation.checkExistingZenProfile.before;
assert lib.hasInfix "check-zen-profile.sh" desktop.home.activation.checkExistingZenProfile.data;
assert lib.hasInfix "${desktop.home.homeDirectory}/.zen/mpjpva0z.default"
  desktop.home.activation.checkExistingZenProfile.data;
assert
  builtins.attrNames managedZenFiles == [
    ".zen/mpjpva0z.default/.keep"
    ".zen/mpjpva0z.default/user.js"
  ];
assert lib.hasInfix ''user_pref("browser.aboutConfig.showWarning", false);''
  managedZenFiles.".zen/mpjpva0z.default/user.js".text;
assert profile.extensions.packages == [ ] && profile.pins == { } && profile.spaces == { };
assert !profile.pinsForce && !profile.spacesForce;
assert !profile.bookmarks.enable && !profile.search.enable && !profile.handlers.enable;
assert !zen.setAsDefaultBrowser;
assert zen.policies.DisableAppUpdate && zen.policies.DisableTelemetry;
assert wrapperHas zen.finalPackage.makeWrapperArgs "MOZ_APP_DATA"
  "${desktop.home.homeDirectory}/.zen";
assert wrapperHas zen.finalPackage.makeWrapperArgs "MOZ_LEGACY_PROFILES" "1";
# The upstream profile module installs only cleanup fragments for past
# declaratively managed presets/buttons, not a session-store writer here.
assert
  map (fragment: fragment.skipSubject) zen.activationFragments.default == [
    "preset prefs"
    "extension buttons"
  ];
assert laptop.programs.zen-browser.enable && laptop.programs.zen-browser.profiles == { };
assert !(builtins.elem "MOZ_APP_DATA" laptop.programs.zen-browser.finalPackage.makeWrapperArgs);
assert !server.programs.zen-browser.enable && server.programs.zen-browser.profiles == { };
pkgs.runCommand "zen-profile-options"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    export ZEN_PROFILE_GUARD=${../modules/home-manager/scripts/check-zen-profile.sh}
    bash ${./zen-profile-guard.sh}
    mkdir -p "$out"
  ''
