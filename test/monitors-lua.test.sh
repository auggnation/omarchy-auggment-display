#!/bin/bash
# Round-trips the managed block through a scratch monitors.lua.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../monitors-lua.sh"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
export MONITORS_LUA="$dir/monitors.lua"

fail() { echo "FAIL: $1" >&2; exit 1; }

original='-- user stuff
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2 })
'
printf '%s' "$original" >"$MONITORS_LUA"

printf 'hl.monitor({ output = "desc:A", mode = "1x1@1.00", position = "0x0", scale = 1, transform = 0 })\n' | "$script" write
grep -q 'desc:A' "$MONITORS_LUA" || fail "block not written"
head -2 "$MONITORS_LUA" | diff - <(printf '%s' "$original") >/dev/null || fail "user content changed on write"
[[ "$("$script" read)" == 'hl.monitor({ output = "desc:A"'* ]] || fail "read did not return body"

printf 'hl.monitor({ output = "desc:B", disabled = true })\n' | "$script" write
grep -q 'desc:A' "$MONITORS_LUA" && fail "old block survived rewrite"
[[ "$(grep -c 'BEGIN io.github' "$MONITORS_LUA")" == 1 ]] || fail "duplicate markers"
[[ "$(grep -c '^$' "$MONITORS_LUA")" == 1 ]] || fail "blank lines accumulate on rewrite"

"$script" remove
diff <(printf '%s' "$original") "$MONITORS_LUA" >/dev/null || fail "remove did not restore the original file"
[[ -z "$("$script" read)" ]] || fail "read after remove should be empty"

rm "$MONITORS_LUA"
"$script" remove
"$script" read
printf 'x\n' | "$script" write
grep -q '^x$' "$MONITORS_LUA" || fail "write should create a missing file"

echo "ok"
