# Power menu (SUPER+M). Log out, reboot and power off go through
# hyprshutdown, which closes apps gracefully before Hyprland exits.
# Wrapped by writeShellApplication (errexit, nounset, pipefail, shellcheck).

choice=$(printf '%s\n' "Lock" "Suspend" "Log out" "Reboot" "Power off" |
  rofi -dmenu -i -no-custom -p "Power") || exit 0

case $choice in
"Lock") loginctl lock-session ;;
"Suspend") systemctl suspend ;;
"Log out") hyprshutdown --top-label "Logging out..." ;;
"Reboot") hyprshutdown --top-label "Restarting..." --post-cmd "systemctl reboot" ;;
"Power off") hyprshutdown --top-label "Shutting down..." --post-cmd "systemctl poweroff" ;;
esac
