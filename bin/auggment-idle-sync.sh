#!/bin/bash
# Regenerate the Auggment screen-off timer (hypridle) from the panel settings.
#
# Only manages ~/.config/hypr/hypridle.conf when it is absent or already marked
# as managed by Auggment. If the user has their own hypridle.conf, it is backed
# up to hypridle.conf.auggment.bak first (never silently discarded).
# Screensaver/lock stay owned by the Omarchy shell.
set -eu

CONFIG="$HOME/.config/auggment"
CONF="$HOME/.config/hypr/hypridle.conf"
MARKER="# Managed by Auggment Display (io.github.auggnation.auggment-display). Do not edit; the Display panel regenerates this file."

SCREEN=$(cat "$CONFIG/screen_off_timeout" 2>/dev/null || echo 600)
[[ -z $SCREEN || $SCREEN -le 0 ]] 2>/dev/null && SCREEN=600

mkdir -p "$HOME/.config/hypr"

if [[ -f $CONF ]] && ! grep -qF "Managed by Auggment Display" "$CONF"; then
  cp -p "$CONF" "$CONF.auggment.bak"
fi

old_umask=$(umask)
umask 077
tmp=$(mktemp "$(dirname "$CONF")/.hypridle.conf.XXXXXX")
umask "$old_umask"

cat > "$tmp" <<EOF
$MARKER
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

chmod 644 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$CONF"

systemctl --user restart hypridle.service 2>/dev/null || true
