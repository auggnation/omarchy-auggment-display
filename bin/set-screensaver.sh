#!/bin/bash
# Safely update idle.screensaver in the Omarchy shell config.
#
# Writes through a private, same-directory temp file (mode 0600, never a
# world-readable /tmp path) and preserves the original file's mode and owner,
# so it neither leaks private widget settings nor changes the file's
# permissions. Only the single idle.screensaver key is touched.
set -euo pipefail

val=${1:-}
[[ $val =~ ^[0-9]+$ ]] || { echo "usage: set-screensaver.sh <seconds>" >&2; exit 2; }

f="$HOME/.config/omarchy/shell.json"
[[ -f $f ]] || exit 0

dir=$(dirname "$f")
old_umask=$(umask)
umask 077
tmp=$(mktemp "$dir/.shell.json.XXXXXX")
umask "$old_umask"
trap 'rm -f "$tmp"' EXIT

jq --argjson v "$val" '.idle.screensaver = $v' "$f" > "$tmp"

# Match the existing file's permissions/owner so the atomic replace is invisible.
chmod --reference="$f" "$tmp" 2>/dev/null || true
chown --reference="$f" "$tmp" 2>/dev/null || true

mv -f "$tmp" "$f"
trap - EXIT
