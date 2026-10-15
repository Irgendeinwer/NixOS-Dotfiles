{
  config,
  lib,
  pkgs,
  ...
}:
let
  p = config.custom.theme.palette;

  # Drawn as SVG in assets/ and rasterized at build time, so the PNG can never
  # drift from its source.
  logo = pkgs.runCommand "fastfetch-logo.png" { nativeBuildInputs = [ pkgs.resvg ]; } ''
    resvg --width 1024 ${../../assets/icon.svg} $out
  '';

  # Inline color codes for fastfetch format strings: "{#<color>}" switches the
  # color, "{#1}" turns on bold and "{#}" resets both.
  color = c: "{#${c}}";

  # One accent per group, shared by its header and its icons.
  accent = {
    system = p.yellow;
    desktop = p.aqua;
    hardware = p.orange;
  };

  # Tree header such as "├─ desktop ───", padded to a common width.
  header = corner: group: {
    type = "custom";
    format =
      "${color p.bg5}${corner}─ {#1}${color accent.${group}}${group}{#}"
      + "${color p.bg5} ${lib.strings.replicate (30 - lib.stringLength group) "─"}";
  };

  # Key such as "│ <icon>  kernel": tree line, icon in the group accent and
  # label in grey. {icon} is the module's built-in Nerd Font icon unless the
  # module sets keyIcon.
  key = group: label: "${color p.bg5}│ ${color accent.${group}}{icon}  ${color p.grey2}${label}";
in
{
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = "${logo}";
        # Columns wide; height auto-scales to preserve the square aspect.
        # (With neither set, fastfetch renders the 1024px original.)
        width = 40;
        padding = {
          right = 3;
        };
      };
      display = {
        # Values line up in one column instead of following a separator
        separator = "";
        key.width = 18;
        brightColor = false;
        color = {
          keys = p.grey2;
          output = p.fg0;
        };
        percent.color = {
          green = p.green;
          yellow = p.yellow;
          red = p.red;
        };
      };
      modules = [
        {
          type = "title";
          format = "{#1}{user-name-colored}{at-symbol-colored}{#1}{host-name-colored}";
          color = {
            user = p.yellow;
            at = p.grey0;
            host = p.aqua;
          };
        }
        (header "╭" "system")
        {
          type = "os";
          key = key "system" "os";
          keyIcon = ""; # nf-linux-nixos; the default is Tux
        }
        {
          type = "kernel";
          key = key "system" "kernel";
          format = "{release}";
        }
        {
          type = "uptime";
          key = key "system" "uptime";
        }
        {
          type = "packages";
          key = key "system" "packages";
          combined = true;
        }
        (header "├" "desktop")
        {
          type = "wm";
          key = key "desktop" "wm";
        }
        {
          type = "terminal";
          key = key "desktop" "terminal";
        }
        {
          type = "shell";
          key = key "desktop" "shell";
        }
        {
          type = "display";
          key = key "desktop" "{name}";
        }
        (header "├" "hardware")
        {
          type = "host";
          key = key "hardware" "host";
          keyIcon = ""; # nf-cod-circuit_board; the default is a laptop
        }
        {
          type = "cpu";
          key = key "hardware" "cpu";
          # Name and core split without the clock, to keep the line short
          format = "{name}{?core-types} ({core-types}){?}";
        }
        {
          type = "gpu";
          key = key "hardware" "gpu";
        }
        {
          type = "memory";
          key = key "hardware" "memory";
        }
        {
          type = "disk";
          key = key "hardware" "{mountpoint}";
        }
        {
          # Closes the tree with a row of the palette's colors
          type = "colors";
          key = "${color p.bg5}╰─";
          keyWidth = 4;
          symbol = "circle";
          brightness = "light";
        }
      ];
    };
  };
}
