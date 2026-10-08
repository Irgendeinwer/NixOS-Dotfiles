{ ... }:
{
  programs.zathura = {
    enable = true;
    options = {
      font = "monospace 11";
      default-bg = "#282828";
      default-fg = "#ebdbb2";
      statusbar-fg = "#ebdbb2";
      statusbar-bg = "#3c3836";
      inputbar-bg = "#282828";
      inputbar-fg = "#ebdbb2";
      notification-bg = "#282828";
      notification-fg = "#ebdbb2";
      notification-error-bg = "#cc241d";
      notification-error-fg = "#282828";
      notification-warning-bg = "#d79921";
      notification-warning-fg = "#282828";
      completion-bg = "#3c3836";
      completion-fg = "#ebdbb2";
      completion-highlight-bg = "#d79921";
      completion-highlight-fg = "#282828";
      indexbg = "#282828";
      indexfg = "#ebdbb2";
      index-active-bg = "#d79921";
      index-active-fg = "#282828";
      recolor-darkmode = "true";
      recolor-lightcolor = "#282828";
      recolor-darkcolor = "#ebdbb2";
      window-title-basename = "true";
      adjust-open = "best-fit";
    };
  };
}
