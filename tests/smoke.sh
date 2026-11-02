#!/usr/bin/env bash
# Proves newleaf works end to end with real Claude Code, in a throwaway git repo:
#   1 the guard speaks at twice a chat's start and stays silent below it
#   2 a brand-new session gets the rules and one line about the note, not the note;
#     asked to continue, it reads the note (small Haiku calls)
#   3 /newleaf writes the note in one reply; the Stop hook saves it, hidden from git
#   4 the same outside a git repo
# tests/two_sessions.py covers /clear and sessions side by side.
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

# 2 start hook: a brand-new session hears of the note (with a random marker) but does not get it
marker="MARK-$RANDOM$RANDOM"
mkdir -p "$repo/.newleaf"
printf -- '---\nwritten: smoke\nbranch: none\nhead: none\n---\n## Next\n%s\n' "$marker" > "$repo/.newleaf/handoff.md"
reply=$(cd "$repo" && printf '%s' "Use no tools. Reply with three words: YES or NO for whether you see 'Lean working rules'; YES or NO for whether you are told of a handoff note at .newleaf/handoff.md; then the text of the note's '## Next' section if it is in your context, else NONE." \
  | MSYS_NO_PATHCONV=1 claude -p --model haiku "${extra[@]}" --no-session-persistence 2>/dev/null)
case $reply in
  *"$marker"*) fail "2a a new session got the note itself (reply: $reply)" ;;
  *YES*YES*NONE*) pass "2a a new session: the rules and one line about the note, not the note" ;;
  *) fail "2a start hook (reply: $reply)" ;;
esac
reply=$(cd "$repo" && printf '%s' "Continue the work from the handoff note: read it and reply with only the text of its '## Next' section." \
  | MSYS_NO_PATHCONV=1 claude -p --model haiku --allowedTools Read "${extra[@]}" --no-session-persistence 2>/dev/null)
case $reply in *"$marker"*) pass "2b asked to continue, it reads the note" ;; *) fail "2b did not read the note (reply: ${reply:0:200})" ;; esac
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

# 4 /newleaf in a folder that is not a git repo (a home folder, say)
plain="$tmp/plain"
mkdir -p "$plain"
reply=$(cd "$plain" && printf '%s' '/newleaf' | GIT_CEILING_DIRECTORIES="$tmp" MSYS_NO_PATHCONV=1 claude -p ${model:+--model "$model"} "${extra[@]}" --no-session-persistence 2>/dev/null)
if [ -s "$plain/.newleaf/handoff.md" ] && grep -q '^## Next' "$plain/.newleaf/handoff.md"; then
  pass "4 /newleaf outside a git repo: the note is saved"
else
  fail "4 /newleaf outside a git repo (reply: ${reply:0:200})"
fi

echo "$fails failed"
exit "$fails"
