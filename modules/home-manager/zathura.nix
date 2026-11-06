{
  config,
  lib,
  osConfig ? null,
  ...
}:
let
  officeEnabled = if osConfig != null then (osConfig.custom.desktop.office.enable or false) else true;
  p = config.custom.theme.palette;
in
lib.mkIf officeEnabled {
  programs.zathura = {
    enable = true;
    options = {
      font = "monospace 11";
      default-bg = p.bg0;
      default-fg = p.fg0;
      statusbar-fg = p.fg0;
      statusbar-bg = p.bg1;
      inputbar-bg = p.bg0;
      inputbar-fg = p.fg0;
      notification-bg = p.bg0;
      notification-fg = p.fg0;
      notification-error-bg = p.red;
      notification-error-fg = p.bg0;
      notification-warning-bg = p.yellow;
      notification-warning-fg = p.bg0;
      completion-bg = p.bg1;
      completion-fg = p.fg0;
      completion-highlight-bg = p.accent;
      completion-highlight-fg = p.bg0;
      indexbg = p.bg0;
      indexfg = p.fg0;
      index-active-bg = p.accent;
      index-active-fg = p.bg0;
      recolor = "true";
      recolor-lightcolor = p.bg0;
      recolor-darkcolor = p.fg0;
      window-title-basename = "true";
      adjust-open = "best-fit";
    };
  };
}
