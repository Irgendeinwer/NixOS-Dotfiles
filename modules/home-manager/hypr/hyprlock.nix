{
  inputs,
  pkgs,
  ...
}:
let
  # 1x1 transparent PNG fallback
  blankPng = pkgs.runCommand "blank.png" { } ''
    echo -n 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=' | base64 -d > $out
  '';

  # Instant Album Art fetcher (112x112)
  fetchCover = pkgs.writeShellScript "hyprlock-cover" ''
    ART=$(${pkgs.playerctl}/bin/playerctl metadata mpris:artUrl 2>/dev/null || true)
    if [ -n "$ART" ]; then
      if [[ "$ART" =~ ^https?:// ]]; then
        CACHE="/tmp/hyprlock-art.png"
        URL_CACHE="/tmp/hyprlock-art.url"
        if [ ! -f "$CACHE" ] || [ "$(cat "$URL_CACHE" 2>/dev/null)" != "$ART" ]; then
          ${pkgs.curl}/bin/curl -s --max-time 1 "$ART" -o "$CACHE" 2>/dev/null
          echo "$ART" > "$URL_CACHE"
        fi
        echo "$CACHE"
      elif [[ "$ART" =~ ^file:// ]]; then
        FILE_PATH="''${ART#file://}"
        if [ -f "$FILE_PATH" ]; then
          echo "$FILE_PATH"
        else
          echo "${blankPng}"
        fi
      else
        echo "$ART"
      fi
    else
      echo "${blankPng}"
    fi
  '';

  # Song Title
  musicTitle = pkgs.writeShellScript "hyprlock-title" ''
    TITLE=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{title}}' 2>/dev/null)
    if [ -n "$TITLE" ]; then
      [ ''${#TITLE} -gt 22 ] && TITLE="''${TITLE:0:20}…"
      echo "$TITLE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
    else
      echo "No media playing"
    fi
  '';

  # Artist & Album
  musicSub = pkgs.writeShellScript "hyprlock-sub" ''
    ARTIST=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{artist}}' 2>/dev/null)
    ALBUM=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{album}}' 2>/dev/null)
    if [ -n "$ARTIST" ] || [ -n "$ALBUM" ]; then
      if [ -n "$ARTIST" ] && [ -n "$ALBUM" ]; then
        TEXT="$ARTIST — $ALBUM"
      elif [ -n "$ARTIST" ]; then
        TEXT="$ARTIST"
      else
        TEXT="$ALBUM"
      fi
      [ ''${#TEXT} -gt 27 ] && TEXT="''${TEXT:0:25}…"
      echo "$TEXT" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
    else
      echo "Playerctl idle"
    fi
  '';

  # Progress Bar & Time
  musicStatus = pkgs.writeShellScript "hyprlock-status" ''
    STATUS=$(${pkgs.playerctl}/bin/playerctl status 2>/dev/null)
    if [ "$STATUS" = "Playing" ]; then ICON="󰐊"; elif [ "$STATUS" = "Paused" ]; then ICON="󰏤"; else ICON="󰓛"; fi

    POS_STR=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{duration(position)}} / {{duration(mpris:length)}}' 2>/dev/null || true)
    POS_US=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{position}}' 2>/dev/null || echo 0)
    LEN_US=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{mpris:length}}' 2>/dev/null || echo 0)

    if [ -n "$POS_STR" ] && [ "$LEN_US" -gt 0 ] 2>/dev/null; then
      PCT=$(( POS_US * 100 / LEN_US ))
      BAR_LEN=8
      FILLED=$(( PCT * BAR_LEN / 100 ))
      UNFILLED=$(( BAR_LEN - FILLED ))
      [ "$FILLED" -gt 0 ] && BF=$(printf '━%.0s' $(seq 1 $FILLED)) || BF=""
      [ "$UNFILLED" -gt 0 ] && BU=$(printf '─%.0s' $(seq 1 $UNFILLED)) || BU=""
      BAR="''${BF}●''${BU}"
      echo "$ICON  $POS_STR  $BAR"
    elif [ -n "$POS_STR" ]; then
      echo "$ICON  $POS_STR"
    else
      echo "$ICON  Idle"
    fi
  '';

  # Player & Audio Output Volume
  musicExtra = pkgs.writeShellScript "hyprlock-musicextra" ''
    if [ "$(${pkgs.pamixer}/bin/pamixer --get-mute 2>/dev/null)" = "true" ]; then
      VOL="󰝟 Muted"
    else
      V=$(${pkgs.pamixer}/bin/pamixer --get-volume 2>/dev/null || echo 0)
      VOL="󰕾 ''${V}%"
    fi
    PLAYER=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{playerName}}' 2>/dev/null)
    PLAYER=''${PLAYER:-"Media"}
    echo "$PLAYER  •  $VOL"
  '';

  # CPU Temp & Load (<0.1ms via /sys & /proc)
  cpuScript = pkgs.writeShellScript "hyprlock-cpu" ''
    LOAD=$(awk '{printf "%.2f", $1}' /proc/loadavg)
    TEMP=""
    for t in /sys/class/thermal/thermal_zone*/temp; do
      if [ -f "$t" ]; then
        V=$(cat "$t" 2>/dev/null || echo 0)
        if [ "$V" -gt 10000 ] 2>/dev/null; then
          TEMP="$(( V / 1000 ))°C"
          break
        fi
      fi
    done
    if [ -n "$TEMP" ]; then
      echo "󰻠  CPU $TEMP  •  Load $LOAD"
    else
      echo "󰻠  CPU Load $LOAD"
    fi
  '';

  # Instant Memory (GiB & %)
  memScript = pkgs.writeShellScript "hyprlock-mem" ''
    ${pkgs.procps}/bin/free -b | awk '/^Mem:/ {
      used = $3 / 1024 / 1024 / 1024;
      total = $2 / 1024 / 1024 / 1024;
      pct = ($3 / $2) * 100;
      printf "󰍛  %.1f / %.1f GiB (%.0f%%)", used, total, pct;
    }'
  '';

  # Root Disk Usage
  diskScript = pkgs.writeShellScript "hyprlock-disk" ''
    ${pkgs.coreutils}/bin/df -h / | awk 'NR==2 {printf "󰋊  / : %s / %s (%s)", $3, $2, $5}'
  '';

  # NixOS Gen & Uptime
  nixUptimeScript = pkgs.writeShellScript "hyprlock-nixuptime" ''
    GEN=$(readlink /nix/var/nix/profiles/system 2>/dev/null | grep -oE '[0-9]+' | tail -n 1)
    GEN=''${GEN:-"Flake"}
    UPTIME=$(awk '{printf "%dh %dm", $1/3600, ($1%3600)/60}' /proc/uptime)
    echo "󱄅  Gen #$GEN  •  󰅐  $UPTIME"
  '';

  # Top-Left: Distro & Kernel
  topLeftScript = pkgs.writeShellScript "hyprlock-topleft" ''
    KERNEL=$(uname -r | cut -d'-' -f1)
    echo "󱄅  NixOS  •  Linux $KERNEL"
  '';

  # Top-Right: Battery (if Laptop) or Hostname & Arch
  topRightScript = pkgs.writeShellScript "hyprlock-topright" ''
    BAT=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n 1)
    STATUS=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n 1)
    if [ -n "$BAT" ]; then
      [ "$STATUS" = "Charging" ] && ICON="󰂄" || ICON="󰁹"
      echo "$ICON  $BAT% ($STATUS)"
    else
      echo "󰌢  $(hostname)  •  x86_64"
    fi
  '';

  # Instant Caps Lock status
  capsLockScript = pkgs.writeShellScript "hyprlock-capslock" ''
    if grep -q 1 /sys/class/leds/*capslock*/brightness 2>/dev/null; then
      echo "󰌾  CAPS LOCK ACTIVE"
    else
      echo ""
    fi
  '';
in
{
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = true;
        immediate_render = true;
        text_trim = true;
      };

      background = [
        {
          monitor = "";
          path = "${inputs.wallpaper}/image/nix-flake-gruvbox.png";
          blur_passes = 3;
          blur_size = 7;
          noise = 0.015;
          contrast = 0.88;
          brightness = 0.75;
          vibrancy = 0.2;
        }
      ];

      # ==========================================
      # GLASS CONTAINERS (zindex = 0)
      # ==========================================
      shape = [
        # Top-Left: System Spec Pill (245px width - snug for Linux kernel text)
        {
          monitor = "";
          size = "245, 44";
          color = "rgba(20, 20, 20, 0.82)";
          rounding = 12;
          border_size = 1;
          border_color = "rgba(235, 219, 178, 0.28)";
          shadow_passes = 0;
          zindex = 0;

          position = "40, -40";
          halign = "left";
          valign = "top";
        }

        # Top-Right: Power / Host Pill (205px width - snug for hostname)
        {
          monitor = "";
          size = "205, 44";
          color = "rgba(20, 20, 20, 0.82)";
          rounding = 12;
          border_size = 1;
          border_color = "rgba(235, 219, 178, 0.28)";
          shadow_passes = 0;
          zindex = 0;

          position = "-40, -40";
          halign = "right";
          valign = "top";
        }

        # Bottom-Left: Media Hub (420px width)
        {
          monitor = "";
          size = "420, 136";
          color = "rgba(20, 20, 20, 0.82)";
          rounding = 18;
          border_size = 2;
          border_color = "rgba(215, 153, 33, 0.75)"; # Gruvbox Gold
          shadow_passes = 0;
          zindex = 0;

          position = "40, 40";
          halign = "left";
          valign = "bottom";
        }

        # Bottom-Right: System Telemetry Hub (300px width)
        {
          monitor = "";
          size = "300, 136";
          color = "rgba(20, 20, 20, 0.82)";
          rounding = 18;
          border_size = 2;
          border_color = "rgba(215, 153, 33, 0.75)"; # Gruvbox Gold
          shadow_passes = 0;
          zindex = 0;

          position = "-40, 40";
          halign = "right";
          valign = "bottom";
        }
      ];

      # ==========================================
      # ALBUM ART (zindex = 1)
      # ==========================================
      image = [
        {
          monitor = "";
          path = "${blankPng}";
          size = 112;
          rounding = 12;
          border_size = 0;
          reload_time = 2;
          reload_cmd = "${fetchCover}";
          zindex = 1;

          position = "52, 52";
          halign = "left";
          valign = "bottom";
        }
      ];

      # ==========================================
      # LABELS (zindex = 1)
      # ==========================================
      label = [
        # --- TOP-LEFT CARD ---
        {
          monitor = "";
          text = "cmd[update:18000000] ${topLeftScript}";
          text_align = "left";
          color = "rgb(235, 219, 178)";
          font_size = 12;
          font_family = "Noto Nerd Font Bold";
          shadow_passes = 0;
          zindex = 1;

          position = "54, -53";
          halign = "left";
          valign = "top";
        }

        # --- TOP-RIGHT CARD ---
        {
          monitor = "";
          text = "cmd[update:10000] ${topRightScript}";
          text_align = "right";
          color = "rgb(235, 219, 178)";
          font_size = 12;
          font_family = "Noto Nerd Font Bold";
          shadow_passes = 0;
          zindex = 1;

          position = "-54, -53";
          halign = "right";
          valign = "top";
        }

        # --- CENTER HERO: CLOCK & DATE ---
        {
          monitor = "";
          text = "$TIME";
          text_align = "center";
          color = "rgb(255, 255, 255)";
          font_size = 140;
          font_family = "Fira Code Nerd Font Bold";
          shadow_passes = 0;
          zindex = 1;

          position = "0, 24.5%";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] echo "<b>$(date +'%A, %d. %B %Y')</b>"'';
          text_align = "center";
          color = "rgb(250, 189, 47)"; # Vibrant Gold
          font_size = 23;
          font_family = "Noto Nerd Font";
          shadow_passes = 0;
          zindex = 1;

          position = "0, 14%";
          halign = "center";
          valign = "center";
        }

        # --- CENTER: CAPS LOCK ALERT ---
        {
          monitor = "";
          text = "cmd[update:250] ${capsLockScript}";
          text_align = "center";
          color = "rgb(234, 105, 98)"; # Alert Red
          font_size = 13;
          font_family = "Noto Nerd Font Bold";
          shadow_passes = 0;
          zindex = 1;

          position = "0, 3.5%";
          halign = "center";
          valign = "center";
        }

        # --- CENTER AUTH: USER ICON & NAME ---
        {
          monitor = "";
          text = "󰌾   $USER";
          text_align = "center";
          color = "rgb(255, 255, 255)";
          font_size = 24;
          font_family = "Noto Nerd Font Bold";
          shadow_passes = 0;
          zindex = 1;

          position = "0, -3.5%";
          halign = "center";
          valign = "center";
        }

        # --- BOTTOM-LEFT: MEDIA PLAYER LABELS ---
        # Fallback music icon behind cover
        {
          monitor = "";
          text = "󰎈";
          color = "rgba(215, 153, 33, 0.4)";
          font_size = 46;
          font_family = "Noto Nerd Font";
          shadow_passes = 0;
          zindex = 1;

          position = "86, 88";
          halign = "left";
          valign = "bottom";
        }
        # Title
        {
          monitor = "";
          text = "cmd[update:1000] ${musicTitle}";
          text_align = "left";
          color = "rgb(255, 255, 255)";
          font_size = 14;
          font_family = "Noto Nerd Font Bold";
          shadow_passes = 0;
          zindex = 1;

          position = "176, 138";
          halign = "left";
          valign = "bottom";
        }
        # Artist — Album
        {
          monitor = "";
          text = "cmd[update:1000] ${musicSub}";
          text_align = "left";
          color = "rgb(235, 219, 178)";
          font_size = 12;
          font_family = "Noto Nerd Font";
          shadow_passes = 0;
          zindex = 1;

          position = "176, 114";
          halign = "left";
          valign = "bottom";
        }
        # Progress Bar & Time
        {
          monitor = "";
          text = "cmd[update:1000] ${musicStatus}";
          text_align = "left";
          color = "rgb(250, 189, 47)"; # Vibrant Gold
          font_size = 11;
          font_family = "Noto Nerd Font";
          shadow_passes = 0;
          zindex = 1;

          position = "176, 90";
          halign = "left";
          valign = "bottom";
        }
        # Player & Volume
        {
          monitor = "";
          text = "cmd[update:1000] ${musicExtra}";
          text_align = "left";
          color = "rgb(189, 174, 147)";
          font_size = 11;
          font_family = "Noto Nerd Font";
          shadow_passes = 0;
          zindex = 1;

          position = "176, 66";
          halign = "left";
          valign = "bottom";
        }

        # --- BOTTOM-RIGHT: SYSTEM TELEMETRY LABELS (CENTER-ALIGNED) ---
        # CPU Temp & Load
        {
          monitor = "";
          text = "cmd[update:2000] ${cpuScript}";
          text_align = "center";
          color = "rgb(255, 255, 255)";
          font_size = 12;
          font_family = "Noto Nerd Font Bold";
          shadow_passes = 0;
          zindex = 1;

          position = "-76, 138";
          halign = "right";
          valign = "bottom";
        }
        # Memory (GiB & %)
        {
          monitor = "";
          text = "cmd[update:2000] ${memScript}";
          text_align = "center";
          color = "rgb(250, 189, 47)"; # Vibrant Gold
          font_size = 11;
          font_family = "Noto Nerd Font";
          shadow_passes = 0;
          zindex = 1;

          position = "-76, 114";
          halign = "right";
          valign = "bottom";
        }
        # Disk Space (Root /)
        {
          monitor = "";
          text = "cmd[update:10000] ${diskScript}";
          text_align = "center";
          color = "rgb(235, 219, 178)";
          font_size = 11;
          font_family = "Noto Nerd Font";
          shadow_passes = 0;
          zindex = 1;

          position = "-76, 90";
          halign = "right";
          valign = "bottom";
        }
        # NixOS Gen & System Uptime
        {
          monitor = "";
          text = "cmd[update:10000] ${nixUptimeScript}";
          text_align = "center";
          color = "rgb(189, 174, 147)";
          font_size = 11;
          font_family = "Noto Nerd Font";
          shadow_passes = 0;
          zindex = 1;

          position = "-76, 66";
          halign = "right";
          valign = "bottom";
        }
      ];

      # ==========================================
      # PASSWORD INPUT PILL (zindex = 2)
      # ==========================================
      input-field = [
        {
          monitor = "";
          size = "420, 60";
          outline_thickness = 2;
          rounding = 30;

          dots_size = 0.24;
          dots_spacing = 0.25;
          dots_center = true;
          dots_rounding = -1;

          outer_color = "rgb(215, 153, 33)"; # Solid Accent Rim
          inner_color = "rgba(20, 20, 20, 0.9)";
          font_color = "rgb(255, 255, 255)";
          fade_on_empty = false;

          check_color = "rgb(184, 187, 38)"; # Gruvbox Green
          fail_color = "rgb(204, 36, 29)"; # Gruvbox Red
          fail_text = "<i>Incorrect ($ATTEMPTS)</i>";

          placeholder_text = ''<i><span foreground="##bdae93">Password...</span></i>'';
          shadow_passes = 0;
          zindex = 2;

          position = "0, -11.5%";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
