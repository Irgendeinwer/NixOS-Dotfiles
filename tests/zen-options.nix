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
  mods = builtins.fromJSON (builtins.readFile ../modules/zen/mods.json);
  reportedPreferences = builtins.fromJSON (builtins.readFile ./zen-preferences.json);
  pinnedManifest = import ../modules/zen/manifest.nix { inherit lib pkgs; };
  modIds = map (mod: mod.entry.id) mods;
  extensionIds = [
    "{34daeb50-c2d2-4f14-886a-7160b24d66a4}"
    "{0d7cafdd-501c-49ca-8ebb-e3341caaa55e}"
    "open-in-mpv@binarynoise.de"
    "{91aa3897-2634-4a8a-9092-279db23a7689}"
    "sponsorBlocker@ajay.app"
    "deArrow@ajay.app"
    "{9350bc42-47fb-4598-ae0f-825e3dd9ceba}"
    "firefox-extension@steamdb.info"
    "{5d554479-7cc4-487f-bd25-d8fc67a42602}"
    "{1be309c5-3e4f-4b99-927d-bb500eb4fa88}"
    "{30280527-c46c-4e03-bb16-2e3ed94fa57c}"
    "keepassxc-browser@keepassxc.org"
    "adnauseam@rednoise.org"
    "addon@darkreader.org"
    "seventv-next@7tv.app"
    "{762f9885-5a13-4abd-9c77-433dcd38b8fd}"
    "{b11bea1f-a888-4332-8d8a-cec2be7d24b9}"
  ];
  expectedModIds = [
    "58649066-2b6f-4a5b-af6d-c3d21d16fc00"
    "d8b79d4a-6cba-4495-9ff6-d6d30b0e94fe"
    "599a1599-e6ab-4749-ab22-de533860de2c"
    "bfcc400a-4ecb-4752-bfd2-a68f116a2722"
    "d93e67f8-e5e1-401e-9b82-f9d5bab231e6"
    "13696593-837d-464d-adf4-ff13bd0e0545"
    "1b88a6d1-d931-45e8-b6c3-bfdca2c7e9d6"
    "81fcd6b3-f014-4796-988f-6c3cb3874db8"
    "f7c71d9a-bce2-420f-ae44-a64bd92975ab"
    "72f8f48d-86b9-4487-acea-eb4977b18f21"
  ];
  wrapperHas =
    args: key: value:
    lib.any (
      i:
      builtins.elemAt args i == "--set"
      && builtins.elemAt args (i + 1) == key
      && builtins.elemAt args (i + 2) == value
    ) (lib.range 0 (builtins.length args - 3));
  managedZenFiles =
    homeConfig:
    lib.filterAttrs (_: file: file.enable && lib.hasPrefix ".zen/" file.target) homeConfig.home.file;
  checkHost =
    homeConfig: path:
    let
      zen = homeConfig.programs.zen-browser;
      profile = zen.profiles.default;
      files = managedZenFiles homeConfig;
      base = ".zen/${path}";
      settings = profile.settings;
      policies = zen.policies.ExtensionSettings;
    in
    assert zen.enable && zen.configPath == ".zen" && zen.profilesPath == ".zen";
    assert profile.id == 0 && profile.isDefault && profile.path == path;
    assert !homeConfig.home.file.".zen/profiles.ini".enable;
    assert
      builtins.attrNames files == [
        "${base}/.keep"
        "${base}/chrome/userChrome.css"
        "${base}/user.js"
      ];
    assert builtins.elem "checkLinkTargets" homeConfig.home.activation.checkExistingZenProfile.before;
    assert builtins.elem "checkExistingZenProfile" homeConfig.home.activation.checkZenMods.after;
    assert builtins.elem "checkLinkTargets" homeConfig.home.activation.checkZenMods.before;
    assert builtins.elem "writeBoundary" homeConfig.home.activation.reconcileZenMods.after;
    assert builtins.elem "linkGeneration" homeConfig.home.activation.reconcileZenMods.before;
    assert builtins.elem "zen-browser-default" homeConfig.home.activation.reconcileZenMods.before;
    assert lib.hasInfix "${homeConfig.home.homeDirectory}/${base}"
      homeConfig.home.activation.checkZenMods.data;
    assert lib.hasInfix "zen-pinned-mods.json" homeConfig.home.activation.checkZenMods.data;
    assert lib.hasInfix "DRY_RUN" homeConfig.home.activation.reconcileZenMods.data;
    assert
      settings == (
        reportedPreferences
        // {
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "zen.mods.auto-update" = false;
          "zen.mods.last-update" = 0;
          "zen.mods.milestone" = lib.getVersion zen.package;
        }
      );
    assert settings."browser.aboutConfig.showWarning" == false;
    assert settings."toolkit.legacyUserProfileCustomizations.stylesheets";
    assert settings."mod.remove-tab-x.scope" == "all";
    assert settings."theme.no_gaps.border" && !settings."theme.no_gaps.gaps";
    assert settings."uc.hidecontext.icons" && !settings."uc.hidecontext.navigation";
    assert settings."uc.private-browsing-top-bar.highlighting-style" == "gradient";
    assert
      settings."uc.urlbar.custom-bg-color" == "${homeConfig.custom.theme.palette.bg_current_word} ";
    assert settings."uc.urlbar.custom-bg-color.mode" == "AlwaysColor";
    assert settings."zen.tab-unloader.timeout-minutes" == 60;
    assert !settings."zen.mods.auto-update" && !settings."zen.themes.disable-all";
    assert settings."zen.mods.last-update" == 0;
    assert settings."zen.mods.milestone" == lib.getVersion zen.package;
    assert !settings."zen.view.use-single-toolbar" && settings."zen.workspaces.continue-where-left-off";
    assert !(settings ? "extensions.webextensions.ExtensionStorageIDB.enabled");
    assert lib.hasInfix homeConfig.custom.theme.palette.accent profile.userChrome;
    assert lib.hasInfix homeConfig.custom.theme.palette.bg0 profile.userChrome;
    assert !(lib.hasInfix "zen-themes.css" profile.userChrome);
    assert lib.hasInfix ''user_pref("mod.remove-tab-x.scope", "all");'' files."${base}/user.js".text;
    assert builtins.attrNames policies == lib.sort builtins.lessThan extensionIds;
    assert lib.all (
      id:
      policies.${id}.installation_mode == "normal_installed"
      &&
        policies.${id}.install_url
        == "https://addons.mozilla.org/firefox/downloads/latest/${lib.escapeURL id}/latest.xpi"
      && !(policies.${id} ? updates_disabled)
    ) extensionIds;
    assert profile.extensions.packages == [ ] && profile.extensions.settings == { };
    # Avoid the binary wrapper's forced links in the shared native-host directory.
    assert zen.nativeMessagingHosts == [ ];
    assert profile.mods == [ ] && !profile.sine.enable;
    assert profile.pins == { } && profile.spaces == { };
    assert !profile.pinsForce && !profile.spacesForce;
    assert !profile.bookmarks.enable && !profile.search.enable && !profile.handlers.enable;
    assert !zen.setAsDefaultBrowser;
    assert zen.policies.DisableAppUpdate && zen.policies.DisableTelemetry;
    assert wrapperHas zen.finalPackage.makeWrapperArgs "MOZ_APP_DATA"
      "${homeConfig.home.homeDirectory}/.zen";
    assert wrapperHas zen.finalPackage.makeWrapperArgs "MOZ_LEGACY_PROFILES" "1";
    # These upstream cleanup fragments have no declared presets/buttons. The
    # preflight blocks their old markers instead of letting them alter prefs.js.
    assert
      map (fragment: fragment.skipSubject) zen.activationFragments.default == [
        "preset prefs"
        "extension buttons"
      ];
    true;
  fallbackPalette = desktop.custom.theme.palette // {
    bg_current_word = null;
    bg1 = "#010203";
  };
  fallbackSettings = import ../modules/zen/settings.nix {
    palette = fallbackPalette;
    zenVersion = "test";
  };
  fallbackCss = import ../modules/zen/user-chrome.nix { palette = fallbackPalette; };
  removeTabX = lib.findFirst (mod: mod.entry.id == "1b88a6d1-d931-45e8-b6c3-bfdca2c7e9d6") null mods;
in
assert checkHost desktop "mpjpva0z.default";
assert checkHost laptop "xtezh31k.default";
assert
  desktop.programs.zen-browser.profiles.default.settings
  == laptop.programs.zen-browser.profiles.default.settings;
assert
  desktop.programs.zen-browser.profiles.default.userChrome
  == laptop.programs.zen-browser.profiles.default.userChrome;
assert
  desktop.programs.zen-browser.policies.ExtensionSettings
  == laptop.programs.zen-browser.policies.ExtensionSettings;
assert fallbackSettings."uc.urlbar.custom-bg-color" == "#010203 ";
assert lib.hasInfix "--zen-urlbar-background: #010203" fallbackCss;
assert modIds == expectedModIds && lib.length (lib.unique modIds) == 10;
assert lib.all (mod: mod.entry.enabled && mod.files ? "chrome.css") mods;
assert lib.all (
  mod:
  lib.all (
    file: builtins.match "[0-9a-f]{64}" file.sha256 != null && !(lib.hasInfix "/main/" file.url)
  ) (lib.attrValues mod.files)
) mods;
assert
  lib.length (builtins.filter (mod: mod.files."chrome.css" ? acceptedPreviousSha256) mods) == 3;
assert
  removeTabX.files."chrome.css".sha256
  == "b54d1e0fdeaf68707aa84eac38937438d20ae1e265b3e75e850140ee0beb7667";
assert lib.hasInfix "xXMacMillanXx/remove-tab-x/" removeTabX.files."chrome.css".url;
assert !server.programs.zen-browser.enable && server.programs.zen-browser.profiles == { };
pkgs.runCommand "zen-profile-options-and-mods"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.python3
    ];
  }
  ''
    export ZEN_PROFILE_GUARD=${../modules/home-manager/scripts/check-zen-profile.sh}
    export ZEN_MODS_HELPER=${../modules/zen/reconcile-mods.py}
    export ZEN_PINNED_MODS_MANIFEST=${pinnedManifest}
    bash ${./zen-profile-guard.sh}
    python3 -B ${./zen-mods.py}
    mkdir -p "$out"
  ''
