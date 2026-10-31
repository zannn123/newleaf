#!/usr/bin/env bash
# Proves newleaf works end to end with real Claude Code, in a throwaway git repo:
#   1 the guard speaks at twice a chat's start and stays silent below it
#   2 the start hook puts a marker note and the rules before the model (one small Haiku call)
#   3 /newleaf writes the note in one reply; the Stop hook saves it, hidden from git
# Usage: bash tests/smoke.sh [plugin dir to test instead of the installed plugin]
# NEWLEAF_SMOKE_MODEL picks the model for step 3 (default: your default model).
set -uo pipefail
export LC_ALL=C
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
dev=${1-}
root=${dev:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
extra=()
[ -n "$dev" ] && extra=(--plugin-dir "$(native "$dev")")
model=${NEWLEAF_SMOKE_MODEL-}
tmp=$(mktemp -d)
trap '[ -d "$tmp" ] && rm -rf -- "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q && git -C "$repo" -c user.name=smoke -c user.email=smoke@local commit -q --allow-empty -m init
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
call() { printf '{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":%s,"output_tokens":1}}}\n' "$1"; }

# 1 guard, on a made-up transcript (outside the repo, with its own state folder)
{ call 50000; call 120000; } > "$tmp/t.jsonl"
guard() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$1" "$(native "$tmp/t.jsonl")" "$(native "$repo")" \
  | CLAUDE_PLUGIN_DATA="$tmp/data" bash "$root/hooks/guard.sh"; }
case $(guard smoke-a) in *systemMessage*) pass "1a guard speaks at 2x a chat's start" ;; *) fail "1a guard silent at 2x" ;; esac
{ call 50000; call 90000; } > "$tmp/t.jsonl"
if [ -z "$(guard smoke-b)" ]; then pass "1b guard silent below 2x"; else fail "1b guard spoke below 2x"; fi

# 2 start hook: a note with a random marker reaches the model, with the rules
marker="MARK-$RANDOM$RANDOM"
mkdir -p "$repo/.newleaf"
printf -- '---\nwritten: smoke\nbranch: none\nhead: none\n---\n## Next\n%s\n' "$marker" > "$repo/.newleaf/handoff.md"
reply=$(cd "$repo" && printf '%s' "Reply with two words: the word after '## Next' in the handoff note in your context (NONE if there is no note), then YES or NO for whether you see 'Lean working rules'." \
  | MSYS_NO_PATHCONV=1 claude -p --model haiku "${extra[@]}" --no-session-persistence 2>/dev/null)
case $reply in *"$marker"*YES*) pass "2 start hook: the note and the rules reached the model" ;; *) fail "2 start hook (reply: $reply)" ;; esac
rm -rf "$repo/.newleaf"

# 3 /newleaf: one reply with the note, saved by the Stop hook
reply=$(cd "$repo" && printf '%s' '/newleaf' | MSYS_NO_PATHCONV=1 claude -p ${model:+--model "$model"} "${extra[@]}" --no-session-persistence 2>/dev/null)
note="$repo/.newleaf/handoff.md"
heads=$(grep -cE '^## (Rules in play|Decided|State|Next|Open)$' "$note" 2>/dev/null)
if [ -s "$note" ] && [ "$(sed -n 1p "$note")" = "---" ] && grep -q '^head: ' "$note" && [ "$heads" = 5 ]; then
  pass "3a /newleaf: the Stop hook saved a complete note"
else
  fail "3a /newleaf: no note or an incomplete one (reply: ${reply:0:200})"
fi
if [ -f "$repo/.newleaf/.gitignore" ] && [ -z "$(git -C "$repo" status --porcelain)" ]; then
  pass "3b the note folder stays out of git"
else
  fail "3b the note folder shows in git status: $(git -C "$repo" status --porcelain | head -3 | tr '\n' ' ')"
fi

echo "$fails failed"
exit "$fails"
