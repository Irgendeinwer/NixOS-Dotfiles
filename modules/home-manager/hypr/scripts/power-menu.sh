# Power menu (SUPER+M). Log out, reboot and power off go through
# hyprshutdown, which closes apps gracefully before Hyprland exits.
# Wrapped by writeShellApplication (errexit, nounset, pipefail, shellcheck).

# The default rofi theme is the app icon grid; text menus get a plain
# list layout on top of it via -theme-str.
list_theme='window { width: 460px; height: 320px; }
listview { columns: 1; lines: 5; fixed-height: false; }
element { orientation: horizontal; children: [ element-text ]; padding: 10px 14px; }
element-text { horizontal-align: 0.0; margin: 0px; }'

choice=$(printf '%s\n' "Lock" "Suspend" "Log out" "Reboot" "Power off" |
  rofi -dmenu -i -no-custom -p "Power" -theme-str "$list_theme") || exit 0

case $choice in
"Lock") loginctl lock-session ;;
"Suspend") systemctl suspend ;;
"Log out") hyprshutdown --top-label "Logging out..." ;;
"Reboot") hyprshutdown --top-label "Restarting..." --post-cmd "systemctl reboot" ;;
"Power off") hyprshutdown --top-label "Shutting down..." --post-cmd "systemctl poweroff" ;;
esac
