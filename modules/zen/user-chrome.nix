{ palette }:
let
  urlbarBackground = if palette.bg_current_word != null then palette.bg_current_word else palette.bg1;
in
''
  /* Palette colors only: layout and behavior remain with Zen and its mods. */
  :root {
    --zen-primary-color: ${palette.accent} !important;
    --zen-colors-primary: ${palette.bg1} !important;
    --zen-colors-secondary: ${palette.bg3} !important;
    --zen-colors-tertiary: ${palette.bg0} !important;
    --zen-colors-border: ${palette.bg5} !important;
    --zen-colors-primary-foreground: ${palette.fg0} !important;
    --zen-colors-input-bg: ${palette.bg1} !important;
    --zen-urlbar-background: ${urlbarBackground} !important;
    --toolbar-bgcolor: ${palette.bg0} !important;
    --toolbar-color: ${palette.fg0} !important;
    --toolbar-field-background-color: ${urlbarBackground} !important;
    --toolbar-field-color: ${palette.fg0} !important;
    --lwt-accent-color: ${palette.bg_dim} !important;
    --lwt-text-color: ${palette.fg0} !important;
    --arrowpanel-background: ${palette.bg1} !important;
    --arrowpanel-color: ${palette.fg0} !important;
  }
''
