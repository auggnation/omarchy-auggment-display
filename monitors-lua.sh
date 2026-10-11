#!/bin/bash

# Owns one marked block at the end of ~/.config/hypr/monitors.lua.
#   monitors-lua.sh write < lines   replace the block with the hl.monitor lines on stdin
#   monitors-lua.sh remove          delete the block
#   monitors-lua.sh read            print the block body
# Everything outside the markers is left byte-for-byte intact.

set -euo pipefail

file="${MONITORS_LUA:-$HOME/.config/hypr/monitors.lua}"
begin="-- BEGIN io.github.auggnation.auggment-display (managed by the Display panel, do not edit)"
end="-- END io.github.auggnation.auggment-display"

without_block() {
  [[ -f $file ]] || return 0
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping
  ' "$file"
}

case "${1:-}" in
read)
  [[ -f $file ]] || exit 0
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { inside = 1; next }
    $0 == end { inside = 0 }
    inside
  ' "$file"
  ;;
write)
  body="$(cat)"
  tmp="$(mktemp "$file.XXXXXX")"
  {
    without_block | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
    printf '\n%s\n%s\n%s\n' "$begin" "$body" "$end"
  } >"$tmp"
  mv "$tmp" "$file"
  ;;
remove)
  [[ -f $file ]] || exit 0
  tmp="$(mktemp "$file.XXXXXX")"
  without_block | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp"
  mv "$tmp" "$file"
  ;;
*)
  echo "usage: monitors-lua.sh read|write|remove" >&2
  exit 1
  ;;
esac
