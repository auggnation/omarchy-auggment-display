#!/bin/bash
# Regenerate hypridle.conf (screen-off only) from auggment settings and reload
# the daemon. Screensaver/lock stay owned by the omarchy shell.
CONFIG="$HOME/.config/auggment"

SCREEN=$(cat "$CONFIG/screen_off_timeout" 2>/dev/null || echo 600)
[[ -z $SCREEN || $SCREEN -le 0 ]] 2>/dev/null && SCREEN=600

mkdir -p "$HOME/.config/hypr"
cat > "$HOME/.config/hypr/hypridle.conf" <<EOF
general {
    lock_cmd = omarchy-system-lock
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
    ignore_dbus_inhibit = false
}

listener {
    timeout = $SCREEN
    on-timeout = hyprctl dispatch 'hl.dsp.dpms({action = "off"})'
    on-resume = hyprctl dispatch 'hl.dsp.dpms({action = "on"})'
}
EOF

systemctl --user restart hypridle.service 2>/dev/null
