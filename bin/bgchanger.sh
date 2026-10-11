#!/bin/bash
# Auggment background rotator.
#   bgchanger.sh          rotate on a loop (foreground/daemon use)
#   bgchanger.sh --once    rotate a single time and exit (driven by the panel Timer)
CONFIG="$HOME/.config/auggment"
HISTORY="$CONFIG/bg_history"
mkdir -p "$CONFIG"

rotate() {
  THEME_NAME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
  USER_BG="$HOME/.config/omarchy/backgrounds/$THEME_NAME/"
  THEME_BG="$HOME/.local/state/omarchy/current/theme/backgrounds/"

  mapfile -d '' -t BACKGROUNDS < <(
    find -L "$USER_BG" "$THEME_BG" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
         -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
      -print0 2>/dev/null | sort -z
  )
  TOTAL=${#BACKGROUNDS[@]}
  if (( TOTAL == 0 )); then
    omarchy-notification-send "No background was found for theme" -t 2000
    return
  fi

  # Remember the last K picks so we don't repeat too often.
  mapfile -t RECENT < "$HISTORY" 2>/dev/null
  K=$(( TOTAL / 2 ))
  (( K < 1 )) && K=1
  (( K > 10 )) && K=10

  CANDIDATES=()
  for b in "${BACKGROUNDS[@]}"; do
    skip=0
    for r in "${RECENT[@]}"; do
      [[ $b == "$r" ]] && { skip=1; break; }
    done
    (( skip == 0 )) && CANDIDATES+=("$b")
  done
  (( ${#CANDIDATES[@]} == 0 )) && CANDIDATES=("${BACKGROUNDS[@]}")

  PICK=${CANDIDATES[$((RANDOM % ${#CANDIDATES[@]}))]}

  omarchy-theme-bg-set "$PICK" >/dev/null 2>&1

  {
    printf '%s\n' "$PICK"
    for r in "${RECENT[@]}"; do
      [[ $r == "$PICK" ]] && continue
      printf '%s\n' "$r"
    done
  } | head -n "$K" > "$HISTORY.tmp"
  mv "$HISTORY.tmp" "$HISTORY"

  AUTO=$(cat "$CONFIG/auto_color_match" 2>/dev/null || echo 0)
  if [[ $AUTO == "1" ]]; then
    RETINT="$(dirname "$(readlink -f "$0")")/auggment-retint.sh"
    [[ -x $RETINT ]] || RETINT="$HOME/.local/bin/auggment-retint.sh"
    "$RETINT"
  fi
}

if [[ $1 == --once ]]; then
  rotate
  exit 0
fi

while true; do
  INTERVAL=$(cat "$CONFIG/bg_interval" 2>/dev/null)
  [[ -z $INTERVAL || $INTERVAL -le 0 ]] 2>/dev/null && INTERVAL=300
  sleep "$INTERVAL"
  rotate
done
