{
  nixpkgs,
  pkgs,
  self,
}:
let
  inherit (nixpkgs) lib;
  base = import ../modules/theme/gruvbox-material-mix-dark-medium.nix;
  themeLib = import ../modules/theme/lib.nix { inherit lib; };

  # Exercise an older, smaller palette: optional Neovim-only roles are absent.
  palette =
    (builtins.removeAttrs base [
      "bg2"
      "bg4"
      "bg_statusline1"
      "bg_statusline3"
      "bg_current_word"
      "bg_visual_green"
      "bg_visual_blue"
      "bg_visual_purple"
      "bg_diff_red"
      "bg_diff_green"
      "bg_diff_blue"
      "bg_red"
      "bg_green"
      "bg_yellow"
    ])
    // {
      bg0 = "#123456";
      red = "#fedcba";
      ansi = lib.imap0 (i: color: if i == 8 then "#123abc" else color) base.ansi;
      extraMetadata = {
        arbitrary = true;
      };
    };

  evaluate =
    selectedPalette:
    (self.nixosConfigurations.junixsrv.extendModules {
      modules = [
        {
          custom.desktop.enable = true;
          custom.theme.palette = selectedPalette;
        }
      ];
    }).config;
  cfg = evaluate palette;
  hm = cfg.home-manager.users.${cfg.custom.user};
  vim = cfg.programs.nixvim;
  overrides = vim.colorschemes.gruvbox-material.settings.colors_override;
  invalidColor = (evaluate (palette // { red = "not-a-color"; })).custom.theme.palette.red;
  shortAnsi = evaluate (palette // { ansi = [ "#123456" ]; });
  paletteError =
    a: !a.assertion && lib.hasInfix "custom.theme.palette.ansi must contain exactly 16" a.message;
  # As with the former attrsOf option, an explicit palette replaces the
  # option default. Partial palettes should fail instead of silently mixing
  # unrelated default colors into an alternative scheme.
  partial =
    (lib.evalModules {
      modules = [
        ../modules/nixos/theme.nix
        {
          config._module.check = false;
          options.assertions = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            default = [ ];
          };
          config.custom.theme.palette.red = "#123456";
        }
      ];
    }).config.custom.theme.palette;
in
assert cfg.custom.theme.palette.extraMetadata.arbitrary;
assert hm.custom.theme.palette.bg0 == palette.bg0;
assert
  cfg.console.colors == map (lib.removePrefix "#") ([ palette.bg0 ] ++ lib.drop 1 palette.ansi);
assert hm.programs.kitty.settings.color8 == builtins.elemAt palette.ansi 8;
assert
  overrides.bg0 == [
    palette.bg0
    (themeLib.cterm palette.bg0)
  ];
assert
  overrides.red == [
    palette.red
    (themeLib.cterm palette.red)
  ];
assert overrides.bg_red == overrides.red; # absent optional role falls back to red
assert builtins.head overrides.bg_diff_red == palette.bg_visual_red;
assert vim.plugins.lualine.settings.options.theme.visual.a.bg == palette.red;
assert vim.plugins.lualine.settings.options.theme.normal.c.bg == palette.bg1;
assert vim.colorschemes.gruvbox-material.settings.disable_terminal_colors == 1;
assert lib.all (i: vim.globals."terminal_color_${toString i}" == builtins.elemAt palette.ansi i) (
  lib.range 0 15
);
assert lib.hasInfix ''terminal_color_8 = "#123abc"'' vim.content;
assert lib.hasInfix "gruvbox_material_colors_override" vim.content;
assert themeLib.cterm "#000000" == 16;
assert themeLib.cterm "#ffffff" == 231;
assert themeLib.cterm "#ff0000" == 196;
assert themeLib.cterm "#FF0000" == 196;
assert themeLib.cterm "#808080" == 244;
assert !(builtins.tryEval invalidColor).success;
assert !(builtins.tryEval (builtins.deepSeq partial true)).success;
assert lib.any paletteError shortAnsi.assertions;
assert lib.any paletteError shortAnsi.home-manager.users.${shortAnsi.custom.user}.assertions;
pkgs.runCommand "shared-palette-options" { } ''
  mkdir -p "$out"
''
