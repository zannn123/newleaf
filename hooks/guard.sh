#!/usr/bin/env bash
# newleaf, UserPromptSubmit: how much does every step of this chat re-send now,
# against what it re-sent at its start? A handoff costs one call, so once a
# step re-sends twice the start, handing off and clearing pays for itself
# within the next request (any request of two or more calls). Says so once at
# 2x, again at 4x, 8x and so on; silent otherwise, and right after a
# compaction. `warn_at` (tokens, 0 = off) in the settings replaces the 2x.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
input=$(cat)
tp=$(unix_path "$(printf '%s' "$input" | json_str transcript_path)")
[ -f "$tp" ] || exit 0
proj=$(project_dir "$input")
warn=$(config warn_at "$proj")
[ "$warn" = 0 ] && exit 0

start=$(head -c 4194304 "$tp" | calls | grep -v reset | head -n 1)
now=$(tail -c 1048576 "$tp" | calls | tail -n 1)
[ -n "$now" ] || now=$(tail -c 16777216 "$tp" | calls | tail -n 1)
case $now in '' | reset) exit 0 ;; esac
[ -n "$start" ] || exit 0
limit=${warn:-$((2 * start))}
[ "$now" -ge "$limit" ] || exit 0

level=0 step=$limit
while [ $((step * 2)) -le "$now" ]; do step=$((step * 2)) level=$((level + 1)); done
state_dir=$(unix_path "${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}")
mkdir -p "$state_dir" 2>/dev/null
sid=$(session_id "$input")
state="$state_dir/newleaf-guard-${sid:-none}"
shown=$(cat "$state" 2>/dev/null)
[ -n "$shown" ] && [ "$shown" -ge "$level" ] && exit 0
printf '%s' "$level" > "$state" 2>/dev/null

k() { printf '%sk' $((($1 + 500) / 1000)); }
printf '{"systemMessage": "newleaf: every step of this chat now re-sends %s tokens, %sx its start (%s). Type /newleaf, then /clear: the next session starts small with the note."}\n' \
  "$(k "$now")" "$((now / start))" "$(k "$start")"
