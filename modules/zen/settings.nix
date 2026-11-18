{ palette, zenVersion }:
let
  # This was #3c3836 in the existing Super Url Bar preference. Keep it tied to
  # the palette, with a fallback for older alternative palettes.
  urlbarBackground = if palette.bg_current_word != null then palette.bg_current_word else palette.bg1;
in
{
  "browser.aboutConfig.showWarning" = false;

  # Zen Mods: the explicitly reported non-default selections.
  "mod.remove-tab-x.scope" = "all";
  "theme.no_gaps.border" = true;
  "theme.no_gaps.fixes.center_split_view" = false;
  "theme.no_gaps.gaps" = false;
  "theme.no_gaps.rounded_corners" = false;
  "theme.no_gaps.shadow" = true;
  "theme.no_gaps.single_toolbar.disable_navbar" = false;
  "theme.no_gaps.single_toolbar.hide_navbar" = true;
  "theme.no_gaps.split.border" = true;
  "theme.no_gaps.split.enabled" = false;
  "theme.no_gaps.split.gaps" = true;
  "theme.no_gaps.split.outline" = true;
  "theme.no_gaps.split.rounded_corners" = true;
  "theme.no_gaps.split.shadow" = true;
  "theme.no_gaps.split.single_toolbar.disable_navbar" = false;
  "theme.no_gaps.split.single_toolbar.hide_navbar" = false;

  "uc.fixcontext.applyzenaccent" = false;
  "uc.fixcontext.applyzengradient" = false;
  "uc.fixcontext.ergonomicsfortabs" = true;
  "uc.fixcontext.restoreicons" = false;
  "uc.hidecontext.bookmark" = true;
  "uc.hidecontext.checkspelling" = false;
  "uc.hidecontext.closemultiple" = true;
  "uc.hidecontext.copylink" = true;
  "uc.hidecontext.duplicatetab" = true;
  "uc.hidecontext.icons" = true;
  "uc.hidecontext.image" = true;
  "uc.hidecontext.movetaboptions" = true;
  "uc.hidecontext.mutetab" = false;
  "uc.hidecontext.navigation" = false;
  "uc.hidecontext.newtab" = true;
  "uc.hidecontext.printselection" = true;
  "uc.hidecontext.reloadtab" = false;
  "uc.hidecontext.savelink" = true;
  "uc.hidecontext.searchinpriv" = true;
  "uc.hidecontext.selectalltabs" = true;
  "uc.hidecontext.selectalltext" = true;
  "uc.hidecontext.separators" = false;
  "uc.private-browsing-top-bar.border-style" = "default";
  "uc.private-browsing-top-bar.color" = "default";
  "uc.private-browsing-top-bar.highlighting-style" = "gradient";
  "uc.urlbar.blur-intensity" = "";
  "uc.urlbar.border" = false;
  "uc.urlbar.border-radius" = true;
  # Preserve the trailing space in the original preference as well.
  "uc.urlbar.custom-bg-color" = "${urlbarBackground} ";
  "uc.urlbar.custom-bg-color.enabled" = true;
  "uc.urlbar.custom-bg-color.mode" = "AlwaysColor";
  "uc.urlbar.icon.bookmark.removed" = true;
  "uc.urlbar.icon.left-side.removed" = false;
  "uc.urlbar.icon.pip.removed" = true;
  "uc.urlbar.icon.shield.removed" = false;
  "uc.urlbar.icon.split-view.removed" = false;
  "uc.urlbar.move-icon-into" = true;
  "uc.urltext.center" = "advanced";

  # Browser settings from the provided filtered prefs.js. Other preferences,
  # extension storage, bookmarks, workspaces and session state stay browser-owned.
  "zen.glance.activation-method" = "shift";
  "zen.glance.enabled" = false;
  "zen.pinned-tab-manager.restore-pinned-tabs-to-pinned-url" = true;
  "zen.site-data-panel.show-callout" = false;
  "zen.tabs.select-recently-used-on-close" = false;
  "zen.tab-unloader.timeout-minutes" = 60;
  "zen.theme.color-prefs.use-workspace-colors" = false;
  "zen.themes.disable-all" = false;
  "zen.urlbar.behavior" = "normal";
  "zen.view.compact.enable-at-startup" = false;
  "zen.view.compact.hide-toolbar" = true;
  "zen.view.compact.should-enable-at-startup" = false;
  "zen.view.drag-window-from-content" = false;
  "zen.view.sidebar-expanded" = false;
  "zen.view.sidebar-expanded.on-hover" = false;
  "zen.view.split-view.change-on-hover" = true;
  "zen.view.use-single-toolbar" = false;
  "zen.view.window.scheme" = 0;
  "zen.welcome-screen.seen" = true;
  "zen.welcomeScreen.seen" = true;
  "zen.workspaces.continue-where-left-off" = true;
  "zen.workspaces.separate-essentials" = false;

  # Unlike extensions, mod source files are pinned and updated through Nix.
  # Zen 1.24.2b checks once anyway if last-update is missing or its milestone
  # differs. Seed both before Zen Mods initializes, including on browser bumps.
  "zen.mods.auto-update" = false;
  "zen.mods.last-update" = 0;
  "zen.mods.milestone" = zenVersion;
}
