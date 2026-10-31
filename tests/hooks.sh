#!/usr/bin/env bash
# newleaf hook tests: every hook fed made-up hook input, transcripts and notes
# in a throwaway folder. No Claude Code, no network.   bash tests/hooks.sh
set -u
export LC_ALL=C   # the checks compare bytes, as the hooks do
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap '[ -d "$tmp" ] && rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_PROJECT_DIR="$tmp/proj" CLAUDE_PLUGIN_DATA="$tmp/data"
proj=$CLAUDE_PROJECT_DIR
mkdir -p "$HOME/.claude" "$proj/.newleaf"
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }
hook() { bash "$here/hooks/$1.sh"; }
g() { git -C "$proj" -c user.name=t -c user.email=t@t "$@"; }

# --- start: rules, a note, its drift --------------------------------------
out=$(printf '{"source":"startup"}' | hook start)
check "start: the rules, no note" '[[ $out == *"Lean working rules"* && $out != *"Handoff note"* ]]'
printf '{"rules": false}\n' > "$proj/.newleaf/config.json"
out=$(printf '{}' | hook start)
check "start: rules off and no note print nothing" '[ -z "$out" ]'
g init -q && g commit -q --allow-empty -m one
head=$(g rev-parse --short HEAD) branch=$(g rev-parse --abbrev-ref HEAD)
printf -- '---\nwritten: now\nbranch: %s\nhead: %s\n---\n## Next\nship it\n' "$branch" "$head" > "$proj/.newleaf/handoff.md"
out=$(printf '{}' | hook start)
check "start: the note, no drift at its own commit" '[[ $out == *"ship it"* && $out != *"Since the note"* && $out != *"Lean working"* ]]'
g commit -q --allow-empty -m two && g commit -q --allow-empty -m three
out=$(printf '{}' | hook start)
check "start: two commits later" '[[ $out == *"2 commits after the note ($head)"* ]]'
g checkout -q -b other
out=$(printf '{}' | hook start)
check "start: another branch" '[[ $out == *"the note says $branch"* ]]'
rm -f "$proj/.newleaf/config.json"

# --- guard: twice the start, then each doubling, once each ----------------
call() { printf '{"type":"assistant","isSidechain":false,"message":{"model":"m","usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s,"output_tokens":9}}}\n' $(($1 - 5)); }
tr="$tmp/t.jsonl"
event() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$1" "$tr" "$proj"; }
{ call 50000; call 90000; } > "$tr"
check "guard: under twice the start, silent" '[ -z "$(event s1 | hook guard)" ]'
call 120000 >> "$tr"
out=$(event s1 | hook guard)
check "guard: at 2x it speaks" '[[ $out == *systemMessage*"120k"*"2x its start (50k)"* ]]'
check "guard: once per level" '[ -z "$(event s1 | hook guard)" ]'
call 210000 >> "$tr"
check "guard: again at 4x" '[[ $(event s1 | hook guard) == *"210k"* ]]'
check "guard: another session starts over" '[[ $(event s2 | hook guard) == *systemMessage* ]]'
printf '{"type":"system","subtype":"compact_boundary"}\n' >> "$tr"
check "guard: silent right after a compaction" '[ -z "$(event s3 | hook guard)" ]'
{ call 50000; call 120000; } > "$tr"
printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":900000}}}\n' >> "$tr"
check "guard: a subagent call is not the chat" '[[ $(event s4 | hook guard) == *"120k"* ]]'
printf '{"warn_at": 0}\n' > "$HOME/.claude/newleaf.json"
check "guard: warn_at 0 turns it off" '[ -z "$(event s5 | hook guard)" ]'
printf '{"warn_at": 500000}\n' > "$HOME/.claude/newleaf.json"
check "guard: warn_at raises the bar" '[ -z "$(event s6 | hook guard)" ]'
rm -f "$HOME/.claude/newleaf.json"
if command -v cygpath >/dev/null 2>&1; then
  native=$(cygpath -w "$tr" | sed 's/\\/\\\\/g')
  out=$(printf '{"session_id":"s7","transcript_path":"%s"}' "$native" | hook guard)
  check "guard: a native Windows path (C:\\...) works" '[[ $out == *systemMessage* ]]'
fi

# --- save: the note from the reply ----------------------------------------
cat > "$tmp/stop.json" <<'EOF'
{"session_id":"s1","hook_event_name":"Stop","last_assistant_message":"Here it is.\n\n<newleaf-note>\n---\nwritten: 2026-10-31T10:00:00+0800\nbranch: main\nhead: abc1234\n---\n## Next\nship \"it\" now \\ ok \u00e9 \ud83c\udf43 ✓\n</newleaf-note>\nSaved for the next session.","stop_hook_active":false}
EOF
rm -rf "$proj/.newleaf"
out=$(hook save < "$tmp/stop.json")
check "save: says it saved" '[[ $out == *systemMessage*"note saved"* ]]'
check "save: the note between the markers" '[ "$(sed -n 1p "$proj/.newleaf/handoff.md")" = "---" ] && grep -q "^head: abc1234$" "$proj/.newleaf/handoff.md"'
check "save: escapes undone" 'grep -qF "ship \"it\" now \\ ok é 🍃 ✓" "$proj/.newleaf/handoff.md"'
check "save: nothing after the closing marker" '! grep -q "Saved for" "$proj/.newleaf/handoff.md"'
check "save: the folder hides itself from git" '[ -z "$(git -C "$proj" status --porcelain)" ]'
hook save < "$tmp/stop.json" >/dev/null
check "save: the old note kept as handoff.prev.md" '[ -f "$proj/.newleaf/handoff.prev.md" ]'
out=$(printf '{"last_assistant_message":"Just a normal reply."}' | hook save)
check "save: a reply without a note does nothing" '[ -z "$out" ]'
printf '{"last_assistant_message":"<newleaf-note>\\n```\\n## Next\\nfenced\\n```\\n</newleaf-note>"}' | hook save >/dev/null
check "save: a code fence around the note is dropped" '[ "$(cat "$proj/.newleaf/handoff.md")" = "$(printf "## Next\nfenced")" ]'

echo "$fails failed"
exit "$fails"
