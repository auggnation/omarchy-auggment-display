#!/bin/bash
# Auto color match: derive the theme palette from the current wallpaper with
# pywal and push it live to the shell. Also keeps the source theme's colors.toml
# in sync so a later full theme refresh keeps this palette.
set -u

THEME_SRC="$HOME/.config/omarchy/themes/auggment"
STATE="$HOME/.local/state/omarchy/current/theme"
BG=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null)
[[ -n $BG && -f $BG ]] || exit 0

WAL_BIN=$(command -v wal || echo "$HOME/.local/bin/wal")
"$WAL_BIN" -n -i "$BG" >/dev/null 2>&1
WAL="$HOME/.cache/wal/colors.json"
[[ -f $WAL ]] || exit 0

OUT=$(mktemp)
python3 - "$WAL" > "$OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
c, sp = d["colors"], d["special"]

def h(x):
    x = x.strip()
    return x if x.startswith("#") else "#" + x

def darken(hexc, f):
    hh = hexc.lstrip("#")
    r, g, b = (int(hh[i:i+2], 16) for i in (0, 2, 4))
    return "#%02x%02x%02x" % (int(r * f), int(g * f), int(b * f))

bg = h(sp.get("background") or c["color0"])
fg = h(sp.get("foreground") or c["color7"])

rows = [
    ("mode", "dark"),
    ("accent", h(c["color4"])),
    ("selection", h(c["color8"])),
    ("muted", darken(h(c["color8"]), 0.8)),
    ("background", bg),
    ("dark_background", darken(bg, 0.9)),
    ("darker_background", darken(bg, 0.8)),
    ("lighter_background", h(c["color8"])),
    ("foreground", fg),
    ("dark_foreground", darken(fg, 0.6)),
    ("light_foreground", h(c["color7"])),
    ("bright_foreground", h(c["color15"])),
    ("red", h(c["color1"])),
    ("yellow", h(c["color3"])),
    ("orange", h(c["color9"])),
    ("green", h(c["color2"])),
    ("cyan", h(c["color6"])),
    ("blue", h(c["color4"])),
    ("magenta", h(c["color5"])),
    ("brown", darken(h(c["color1"]), 0.7)),
    ("bright_red", h(c["color9"])),
    ("bright_yellow", h(c["color11"])),
    ("bright_green", h(c["color10"])),
    ("bright_cyan", h(c["color14"])),
    ("bright_blue", h(c["color12"])),
]
print('\n'.join('%s = "%s"' % (k, v) for k, v in rows))
PY

[[ -s $OUT ]] || { rm -f "$OUT"; exit 0; }

mkdir -p "$THEME_SRC" "$STATE"
cp "$OUT" "$THEME_SRC/colors.toml"
cp "$OUT" "$STATE/colors.toml"
rm -f "$OUT"

if [[ -f "$STATE/shell.toml" ]]; then
  col=$(base64 -w0 "$STATE/colors.toml")
  shl=$(base64 -w0 "$STATE/shell.toml")
  omarchy-shell shell applyTheme "$col" "$shl" >/dev/null 2>&1
fi

# Retint window borders live (the theme's hyprland.lua is otherwise only read
# on reload/login).
if [[ -f "$STATE/hyprland.lua" ]]; then
  accent=$(grep -m1 '^accent' "$STATE/colors.toml" | cut -d'"' -f2)
  inactive=$(grep -m1 '^muted' "$STATE/colors.toml" | cut -d'"' -f2)
  inactive=${inactive#\#}
  if [[ -n $accent ]]; then
    sed -i "s|local active_border_color = \"#[0-9a-fA-F]*\"|local active_border_color = \"$accent\"|" "$STATE/hyprland.lua"
  fi
  if [[ -n $inactive ]]; then
    sed -i "s|local inactive_border_color = \"rgba([0-9a-fA-F]*aa)\"|local inactive_border_color = \"rgba(${inactive}aa)\"|" "$STATE/hyprland.lua"
  fi
  hyprctl reload >/dev/null 2>&1
fi
