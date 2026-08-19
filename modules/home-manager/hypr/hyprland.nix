{ config, pkgs, ... }:

let
  # Apps & UI
  kitty = "${pkgs.kitty}/bin/kitty";
  rofi = "${pkgs.rofi}/bin/rofi";
  signal = "${pkgs.signal-desktop}/bin/signal-desktop";
  easyeffects = "${pkgs.easyeffects}/bin/easyeffects";
  hyprlock = "${pkgs.hyprlock}/bin/hyprlock";

  # CLI Utilities
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  pamixer = "${pkgs.pamixer}/bin/pamixer";
  playerctl = "${pkgs.playerctl}/bin/playerctl";
  cliphist = "${pkgs.cliphist}/bin/cliphist";
  wlPaste = "${pkgs.wl-clipboard}/bin/wl-paste";
  wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
  notifySend = "${pkgs.libnotify}/bin/notify-send";
  hyprshot = "${pkgs.hyprshot}/bin/hyprshot";
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    plugins = [ ];
    systemd.enable = true;
    systemd.variables = [ "--all" ];
    extraConfig = ''
      --------------------------------------------------
      -- Environment Variables
      --------------------------------------------------
      hl.env("QT_QPA_PLATFORM", "wayland;xcb")
      hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

      --------------------------------------------------
      -- Monitors
      --------------------------------------------------
      -- eDP-1: Laptop built-in display
      hl.monitor({
        output = "eDP-1",
        mode = "preferred",
        position = "auto",
        scale = 1,
      })

      -- DP-2: Lenovo G27qe-20 (Left, 1440p @ 100Hz)
      hl.monitor({
        output = "DP-2",
        mode = "2560x1440@100",
        position = "0x0",
        scale = 1,
      })

      -- DP-1: KTC M27T6 (Right, 1440p @ 180Hz) - Starts in 10-bit SDR mode
      hl.monitor({
        output = "DP-1",
        mode = "2560x1440@180",
        position = "2560x0",
        scale = 1,
        bitdepth = 10,
        cm = "srgb",
      })

      --------------------------------------------------
      -- Autostart (exec-once)
      --------------------------------------------------
      hl.on("hyprland.start", function()
        hl.exec_cmd("${hyprlock}")
        hl.exec_cmd("systemctl --user start hyprpolkitagent")

        hl.exec_cmd("${wlPaste} --type text --watch ${cliphist} store")
        hl.exec_cmd("${wlPaste} --type image --watch ${cliphist} store")

        hl.exec_cmd("${brightnessctl} set 100%")

        hl.exec_cmd("${signal}", { workspace = "10 silent" })
        hl.exec_cmd("${easyeffects}", { workspace = "10 silent" })
      end)

      --------------------------------------------------
      -- General Configurations
      --------------------------------------------------
      hl.config({
        render = {
          cm_auto_hdr = 2,
        },
        input = {
          kb_layout = "de",
          numlock_by_default = false,
          follow_mouse = 2,
          sensitivity = 0,
          accel_profile = "flat",
          touchpad = {
            natural_scroll = false,
            disable_while_typing = false,
          },
        },
        general = {
          gaps_in = 2,
          gaps_out = 4,
          border_size = 1,
          col = {
            active_border = {
              colors = { "rgba(33ccffee)", "rgba(00ff99ee)" },
              angle = 45,
            },
            inactive_border = "rgba(595959aa)",
          },
          allow_tearing = false,
          layout = "dwindle",
        },
        misc = {
          vrr = 3,
          key_press_enables_dpms = true,
          force_default_wallpaper = 0,
          disable_hyprland_logo = true,
          enable_swallow = true,
          swallow_regex = "^(kitty)$",
        },
        dwindle = {
          smart_split = true,
        },
        decoration = {
          rounding = 3,
          blur = {
            enabled = false,
          },
          shadow = {
            enabled = false,
          },
        },
        animations = {
          enabled = true,
        },
        cursor = {
          hide_on_key_press = true,
        },
      })

      --------------------------------------------------
      -- Gestures & Workspace Rules
      --------------------------------------------------
      hl.gesture({
        fingers = 3,
        direction = "horizontal",
        action = "workspace",
      })

      hl.workspace_rule({ workspace = "w[t1]", gaps_out = 0, gaps_in = 0 })
      hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })

      --------------------------------------------------
      -- Window Rules
      --------------------------------------------------
      -- Picture-in-Picture
      hl.window_rule({
        match = { title = "^(Picture-in-Picture)$" },
        float = true,
        pin = true,
        move = { 2038, 10 },
        size = { 512, 288 },
        no_initial_focus = true,
        opacity = "1.0 override 1.0 override",
      })

      -- General
      hl.window_rule({
        match = { class = ".*" },
        suppress_event = "maximize",
      })

      -- Smart Gaps
      hl.window_rule({ match = { workspace = "w[t1]" }, border_size = 0, rounding = 0 })
      hl.window_rule({ match = { workspace = "f[1]" }, border_size = 0, rounding = 0 })

      --------------------------------------------------
      -- Keybindings
      --------------------------------------------------
      local mainMod = "SUPER"

      -- App shortcuts
      hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("${kitty}"))
      hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("${rofi} -show drun -show-icons"))
      hl.bind(mainMod .. " + D", hl.dsp.window.close())
      hl.bind(mainMod .. " + M", hl.dsp.exit())
      hl.bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }))
      hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
      hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("loginctl lock-session"))

      -- Native Lua HDR Toggle for DP-1
      local hdr_on = false
      local function toggle_hdr()
        hdr_on = not hdr_on
        hl.monitor({
          output = "DP-1",
          mode = "2560x1440@180",
          position = "2560x0",
          scale = 1,
          bitdepth = 10,
          cm = hdr_on and "hdr" or "srgb",
          sdrbrightness = hdr_on and 1.2 or 1.0,
        })

        local status = hdr_on and "HDR Enabled (10-bit)" or "SDR Mode (10-bit)"
        hl.exec_cmd(string.format([[${notifySend} "Display" "%s" -t 5000]], status))
      end
      hl.bind(mainMod .. " + SHIFT + H", toggle_hdr)

      -- Utilities
      hl.bind("PRINT", hl.dsp.exec_cmd("${hyprshot} -m region --freeze -o ${config.programs.hyprshot.saveLocation}"))
      hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("${cliphist} list | ${rofi} -dmenu | ${cliphist} decode | ${wlCopy}"))
      hl.bind(mainMod .. " + T", hl.dsp.exec_cmd([[${notifySend} -t 3000 "$(date +%H):$(date +%M) Uhr" "$(date)"]]))

      -- Media & Volume Controls (with repeat and lockscreen support)
      hl.bind("F8", hl.dsp.exec_cmd("${playerctl} play-pause"), { locked = true })
      hl.bind("F9", hl.dsp.exec_cmd("${pamixer} -d 2"), { repeating = true, locked = true})
      hl.bind("F10", hl.dsp.exec_cmd("${pamixer} -i 2"), { repeating = true, locked = true })

      hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("${pamixer} -i 2"), { repeating = true, locked = true })
      hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("${pamixer} -d 2"), { repeating = true, locked = true })
      hl.bind("XF86AudioMute", hl.dsp.exec_cmd("${pamixer} -t"), { locked = true })
      hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("${playerctl} play-pause"), { locked = true })
      hl.bind("XF86AudioNext", hl.dsp.exec_cmd("${playerctl} next"), { locked = true })
      hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("${playerctl} previous"), { locked = true })
      hl.bind("XF86AudioStop", hl.dsp.exec_cmd("${playerctl} stop"), { locked = true })
      hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("${pamixer} --default-source -t"), { locked = true })
      hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("${brightnessctl} set 10%+"), { repeating = true, locked = true })
      hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("${brightnessctl} set 10%-"), { repeating = true, locked = true })

      -- Directional Navigation & Movement
      local directions = { left = "l", right = "r", up = "u", down = "d" }
      for key, dir in pairs(directions) do
        hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = dir }))
        hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
      end

      -- Workspaces 1 - 10
      for i = 1, 10 do
        local key = tostring(i % 10)
        hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = tostring(i) }))
        hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(i), follow = false }))
      end

      -- Special Workspace & Scrolling
      hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
      hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
      hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e-1" }))
      hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e+1" }))

      -- Window Resizing & Moving (Relative offsets)
      hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
      hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 40, y = 0, relative = true }), { repeating = true })
      hl.bind(mainMod .. " + CTRL + up", hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
      hl.bind(mainMod .. " + CTRL + down", hl.dsp.window.resize({ x = 0, y = 40, relative = true }), { repeating = true })

      hl.bind(mainMod .. " + ALT + left", hl.dsp.window.move({ x = -40, y = 0, relative = true }), { repeating = true })
      hl.bind(mainMod .. " + ALT + right", hl.dsp.window.move({ x = 40, y = 0, relative = true }), { repeating = true })
      hl.bind(mainMod .. " + ALT + up", hl.dsp.window.move({ x = 0, y = -40, relative = true }), { repeating = true })
      hl.bind(mainMod .. " + ALT + down", hl.dsp.window.move({ x = 0, y = 40, relative = true }), { repeating = true })

      -- Mouse drag & resize
      hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
      hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
    '';
  };
}
