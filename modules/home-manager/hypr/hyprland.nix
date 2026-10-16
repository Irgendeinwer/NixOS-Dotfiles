{
  config,
  osConfig ? null,
  lib,
  pkgs,
  ...
}:

let
  p = config.custom.theme.palette;
  inherit (import ../../theme/lib.nix { inherit lib; }) hex;
  hyprlandEnabled =
    if osConfig != null then (osConfig.custom.desktop.hyprland.enable or false) else true;
  # The autostarted apps below belong to optional feature modules: launch
  # them only when the host enables those features (they install the apps).
  messagingEnabled =
    if osConfig != null then (osConfig.custom.desktop.messaging.enable or false) else true;
  soundEnabled = if osConfig != null then (osConfig.custom.desktop.sound.enable or false) else true;
  # Frosted desktop layers, opt-in per host (the laptop skips the cost)
  layerBlur =
    if osConfig != null then (osConfig.custom.desktop.hyprland.layerBlur or false) else false;
  # Qt theme from qt.nix for everything launched from Hyprland: Home Manager
  # exports these only to shells and systemd services, and greetd starts
  # Hyprland outside both.
  qtEnv = lib.optionalString (config.home.sessionVariables ? QT_QPA_PLATFORMTHEME) ''
    hl.env("QT_QPA_PLATFORMTHEME", "${config.home.sessionVariables.QT_QPA_PLATFORMTHEME}")
    hl.env("QT_PLUGIN_PATH", "${lib.concatStringsSep ":" config.home.sessionSearchVariables.QT_PLUGIN_PATH}")
  '';

  # Apps & UI
  kitty = "${pkgs.kitty}/bin/kitty";
  rofi = "${pkgs.rofi}/bin/rofi";
  signal = "${pkgs.signal-desktop}/bin/signal-desktop";
  easyeffects = "${pkgs.easyeffects}/bin/easyeffects";

  # CLI Utilities
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  swayosdClient = "${config.services.swayosd.package}/bin/swayosd-client";
  makoctl = "${pkgs.mako}/bin/makoctl";
  cliphist = "${pkgs.cliphist}/bin/cliphist";
  wlPaste = "${pkgs.wl-clipboard}/bin/wl-paste";
  wlCopy = "${pkgs.wl-clipboard}/bin/wl-copy";
  notifySend = "${pkgs.libnotify}/bin/notify-send";
  hyprshot = "${pkgs.hyprshot}/bin/hyprshot";

  # Power menu (shellchecked at build time by writeShellApplication)
  powerMenu = lib.getExe (
    pkgs.writeShellApplication {
      name = "hypr-power-menu";
      runtimeInputs = with pkgs; [
        rofi
        systemd
        hyprshutdown
      ];
      text = builtins.readFile ./scripts/power-menu.sh;
    }
  );

  formatMonitor =
    m:
    let
      bitdepthStr = if m ? bitdepth then "\n      bitdepth = ${toString m.bitdepth}," else "";
      cmStr = if m ? cm then "\n      cm = \"${m.cm}\"," else "";
      sdrbrightnessStr =
        if m ? sdrbrightness then "\n      sdrbrightness = ${toString m.sdrbrightness}," else "";
    in
    ''
      hl.monitor({
        output = "${m.output}",
        mode = "${m.mode or "preferred"}",
        position = "${m.position or "auto"}",
        scale = ${toString (m.scale or 1)},${bitdepthStr}${cmStr}${sdrbrightnessStr}
      })
    '';

  configuredMonitors =
    if osConfig != null then (osConfig.custom.desktop.hyprland.monitors or [ ]) else [ ];

  monitorsLua =
    if configuredMonitors != [ ] then
      lib.concatMapStringsSep "\n\n" formatMonitor configuredMonitors
    else
      ''
        hl.monitor({
          output = "",
          mode = "preferred",
          position = "auto",
          scale = 1,
        })
      '';

  # The monitor (if any) the HDR toggle keybind switches: marked with
  # `hdr = true` in the host's monitor list.
  hdrMonitor = lib.findFirst (m: m.hdr or false) null configuredMonitors;
  hasHdr = hdrMonitor != null;
  hdrMode = if hasHdr then (hdrMonitor.mode or "preferred") else "preferred";
  hdrPos = if hasHdr then (hdrMonitor.position or "auto") else "auto";
  hdrScale = if hasHdr then toString (hdrMonitor.scale or 1) else "1";
  hdrBitdepth = if hasHdr then toString (hdrMonitor.bitdepth or 10) else "10";
  hdrBaseCm = if hasHdr then (hdrMonitor.cm or "srgb") else "srgb";
in
lib.mkIf hyprlandEnabled {
  # Polkit agent as a user service bound to the Hyprland session. (The package
  # ships its binary in libexec/, so the old bin/ exec path never started.)
  services.hyprpolkitagent.enable = true;

  # On-screen display for volume, brightness and media keys: with no status
  # bar, this is the only visual feedback for them. Flat GTK CSS with the
  # selectors of swayosd's own stylesheet, recolored from the palette.
  services.swayosd = {
    enable = true;
    stylePath = pkgs.writeText "swayosd.css" ''
      window#osd {
        border-radius: 999px;
        border: 1px solid ${p.bg3};
        background: alpha(${p.bg0}, 0.92);
      }
      window#osd #container {
        margin: 16px;
      }
      window#osd image,
      window#osd label {
        color: ${p.fg0};
      }
      window#osd progressbar:disabled,
      window#osd image:disabled {
        opacity: 0.5;
      }
      window#osd progressbar,
      window#osd segmentedprogress {
        min-height: 6px;
        border-radius: 999px;
        background: transparent;
        border: none;
      }
      window#osd trough,
      window#osd segment {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: ${p.bg3};
      }
      window#osd progress,
      window#osd segment.active {
        min-height: inherit;
        border-radius: inherit;
        border: none;
        background: ${p.accent};
      }
      window#osd segment {
        margin-left: 8px;
      }
      window#osd segment:first-child {
        margin-left: 0;
      }
    '';
  };

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    systemd.enable = true;
    systemd.variables = [ "--all" ];
    extraConfig = ''
      --------------------------------------------------
      -- Environment Variables
      --------------------------------------------------
      hl.env("QT_QPA_PLATFORM", "wayland;xcb")
      hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
      ${qtEnv}

      --------------------------------------------------
      -- Monitors
      --------------------------------------------------
      ${monitorsLua}

      --------------------------------------------------
      -- Autostart (exec-once)
      --------------------------------------------------
      -- The boot session is already locked: greetd starts Hyprland with
      -- --locked-cmd (modules/nixos/hypr.nix).
      hl.on("hyprland.start", function()
        hl.exec_cmd("${wlPaste} --type text --watch ${cliphist} store")
        hl.exec_cmd("${wlPaste} --type image --watch ${cliphist} store")

        hl.exec_cmd("${brightnessctl} set 100%")
      ${lib.optionalString messagingEnabled ''
        hl.exec_cmd("${signal}", { workspace = "10 silent" })
      ''}${lib.optionalString soundEnabled ''
        hl.exec_cmd("${easyeffects}", { workspace = "10 silent" })
      ''}
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
              colors = { "rgba(${hex p.accent}ee)", "rgba(${hex p.orange}ee)" },
              angle = 45,
            },
            inactive_border = "rgba(${hex p.bg3}aa)",
          },
          allow_tearing = false,
          layout = "dwindle",
        },
        misc = {
          vrr = 3,
          key_press_enables_dpms = true,
          force_default_wallpaper = 0,
          background_color = "rgb(${hex p.bg_dim})",
          disable_hyprland_logo = true,
          enable_swallow = true,
          swallow_regex = "^(kitty)$",
          allow_session_lock_restore = true,
          -- Honour activation requests: a link opened from a chat app brings
          -- the browser forward, even from another workspace (there is no bar
          -- to show urgency hints).
          focus_on_activate = true,
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
        move = "monitor_w-window_w-10 10",
        size = { 512, 288 },
        no_initial_focus = true,
        opacity = "1.0 override 1.0 override",
      })

      -- General
      hl.window_rule({
        match = { class = ".*" },
        suppress_event = "maximize",
      })

      -- Smart Gaps: edge-to-edge tiled windows; floating ones keep their frame
      hl.window_rule({ match = { float = false, workspace = "w[t1]" }, border_size = 0, rounding = 0 })
      hl.window_rule({ match = { float = false, workspace = "f[1]" }, border_size = 0, rounding = 0 })

      --------------------------------------------------
      -- On-Screen Display (swayosd)
      --------------------------------------------------
      -- Show swayosd on the focused monitor only (it defaults to all of them).
      local function osd_target()
        local mon = hl.get_active_monitor()
        local name = mon and mon.name and mon.name:gsub("[^%w%-_]", "") or ""
        return name ~= "" and (" --monitor " .. name) or ""
      end

      local function osd(args)
        hl.exec_cmd("${swayosdClient}" .. osd_target() .. " " .. args)
      end

      -- Do not disturb (mako mode), confirmed with an OSD hint since the
      -- notifications themselves are hidden while it is on.
      local function toggle_dnd()
        hl.exec_cmd(string.format(
          [[if %s mode -t do-not-disturb | grep -qx do-not-disturb; then m="Do not disturb: on"; else m="Do not disturb: off"; fi; %s%s --custom-message "$m"]],
          "${makoctl}", "${swayosdClient}", osd_target()
        ))
      end

      --------------------------------------------------
      -- Desktop Layers
      --------------------------------------------------
      ${lib.optionalString layerBlur ''
        -- Background blur behind the launcher, notifications and the
        -- OSD. Only rendered while such a layer is on screen, so the
        -- cost is a few milliseconds when one of them pops up.
        hl.layer_rule({ name = "blur-launcher", match = { namespace = "^rofi$" }, blur = true, ignore_alpha = 0.2 })
        hl.layer_rule({ name = "blur-notifications", match = { namespace = "^notifications$" }, blur = true, ignore_alpha = 0.2 })
        hl.layer_rule({ name = "blur-osd", match = { namespace = "^swayosd$" }, blur = true, ignore_alpha = 0.2 })
      ''}

      --------------------------------------------------
      -- Keybindings
      --------------------------------------------------
      local mainMod = "SUPER"

      -- App shortcuts
      hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("${kitty}"))
      hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("${rofi} -show drun -show-icons"))
      hl.bind(mainMod .. " + D", hl.dsp.window.close())
      hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("${powerMenu}"))
      hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("loginctl lock-session"))

      -- Window state & focus
      hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
      hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
      hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
      hl.bind(mainMod .. " + Tab", hl.dsp.window.cycle_next({ next = true }))
      hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))
      hl.bind("ALT + Tab", hl.dsp.exec_cmd("${rofi} -show window -show-icons"))

      ${lib.optionalString hasHdr ''
        -- HDR toggle for the monitor marked `hdr = true`
        local hdr_on = false
        local function toggle_hdr()
          hdr_on = not hdr_on
          hl.monitor({
            output = "${hdrMonitor.output}",
            mode = "${hdrMode}",
            position = "${hdrPos}",
            scale = ${hdrScale},
            bitdepth = ${hdrBitdepth},
            cm = hdr_on and "hdr" or "${hdrBaseCm}",
            sdrbrightness = hdr_on and 1.2 or 1.0,
          })

          local status = hdr_on and "HDR Enabled (${hdrBitdepth}-bit)" or "SDR Mode (${hdrBitdepth}-bit)"
          hl.exec_cmd(string.format([[${notifySend} "Display" "%s" -t 5000]], status))
        end
        hl.bind(mainMod .. " + SHIFT + H", toggle_hdr)
      ''}

      -- Utilities
      hl.bind("PRINT", hl.dsp.exec_cmd("${hyprshot} -m region --freeze -o ${config.programs.hyprshot.saveLocation}"))
      hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("${cliphist} list | ${rofi} -dmenu -theme-str 'window { width: 760px; height: 470px; } listview { columns: 1; lines: 10; fixed-height: false; } element { orientation: horizontal; children: [ element-text ]; padding: 10px 14px; } element-text { horizontal-align: 0.0; margin: 0px; }' | ${cliphist} decode | ${wlCopy}"))
      hl.bind(mainMod .. " + T", hl.dsp.exec_cmd([[${notifySend} -t 3000 "$(date +%H):$(date +%M) Uhr" "$(date)"]]))
      hl.bind(mainMod .. " + N", toggle_dnd)

      -- Media, Volume & Brightness (swayosd: applies the change and shows an
      -- OSD on the focused monitor; with repeat and lockscreen support)
      local function osd_bind(keys, args, opts)
        hl.bind(keys, function() osd(args) end, opts)
      end
      osd_bind("F8", "--playerctl play-pause", { locked = true })
      osd_bind("F9", "--output-volume=-2", { repeating = true, locked = true })
      osd_bind("F10", "--output-volume=+2", { repeating = true, locked = true })

      osd_bind("XF86AudioRaiseVolume", "--output-volume=+2", { repeating = true, locked = true })
      osd_bind("XF86AudioLowerVolume", "--output-volume=-2", { repeating = true, locked = true })
      osd_bind("XF86AudioMute", "--output-volume mute-toggle", { locked = true })
      osd_bind("XF86AudioMicMute", "--input-volume mute-toggle", { locked = true })
      osd_bind("XF86AudioPlay", "--playerctl play-pause", { locked = true })
      osd_bind("XF86AudioNext", "--playerctl next", { locked = true })
      osd_bind("XF86AudioPrev", "--playerctl prev", { locked = true })
      osd_bind("XF86AudioStop", "--playerctl stop", { locked = true })
      osd_bind("XF86MonBrightnessUp", "--brightness=+10", { repeating = true, locked = true })
      osd_bind("XF86MonBrightnessDown", "--brightness=-10", { repeating = true, locked = true })

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
