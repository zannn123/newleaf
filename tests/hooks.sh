#!/usr/bin/env bash
# newleaf hook tests: every hook fed made-up hook input, transcripts and notes
# in a throwaway folder. No Claude Code, no network.   bash tests/hooks.sh
set -u
export LC_ALL=C   # the checks compare bytes, as the hooks do
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap '[ -d "$tmp" ] && rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CLAUDE_PROJECT_DIR="$tmp/proj" CLAUDE_PLUGIN_DATA="$tmp/data"
unset CLAUDE_PID   # each check below says which process it plays
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
mkdir -p "$proj/.newleaf/notes"
printf -- '---\nwritten: now\nbranch: %s\nhead: %s\n---\n## Next\nship it\n' "$branch" "$head" > "$proj/.newleaf/notes/me.md"
cp "$proj/.newleaf/notes/me.md" "$proj/.newleaf/handoff.md"
own() { printf '{"session_id":"me","source":"compact"}' | hook start; }
out=$(own)
check "start: the note, no drift at its own commit" '[[ $out == *"ship it"* && $out != *"Since the note"* && $out != *"Lean working"* ]]'
g commit -q --allow-empty -m two && g commit -q --allow-empty -m three
out=$(own)
check "start: two commits later" '[[ $out == *"2 commits after the note ($head)"* ]]'
g checkout -q -b other
out=$(own)
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
tok() { printf '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":%s,"cached_input_tokens":0,"output_tokens":9,"reasoning_output_tokens":0,"total_tokens":%s},"last_token_usage":{"input_tokens":%s,"cached_input_tokens":0,"output_tokens":9,"reasoning_output_tokens":0,"total_tokens":%s},"model_context_window":272000}}}\n' "$1" "$1" "$1" "$1"; }
{ printf '{"type":"session_meta","payload":{"id":"x"}}\n'; tok 40000; printf '{"type":"event_msg","payload":{"type":"token_count","info":null}}\n'; tok 70000; } > "$tr"
check "guard (Codex log): under twice the start, silent" '[ -z "$(event c1 | hook guard)" ]'
tok 85000 >> "$tr"
check "guard (Codex log): at 2x it speaks" '[[ $(event c1 | hook guard) == *"85k"*"2x its start (40k)"* ]]'
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

# --- two sessions in one folder: neither gets the other's note --------------
rm -rf "$proj/.newleaf"
say() { printf '{"session_id":"%s","last_assistant_message":"<newleaf-note>\\n---\\nwritten: w\\nbranch: none\\nhead: none\\n---\\n## Next\\n%s\\n</newleaf-note>"}' "$1" "$3" | CLAUDE_PID=$2 hook save >/dev/null; }
begin() { printf '{"session_id":"%s","source":"%s"}' "$1" "$3" | CLAUDE_PID=$2 hook start; }
say A 111 task-a
say B 222 task-b
out=$(begin A 111 compact)
check "two sessions: A's compaction gets A's note, not B's" '[[ $out == *task-a* && $out != *task-b* ]]'
check "two sessions: it says where that note is" '[[ $out == *".newleaf/notes/A.md"* ]]'
out=$(begin B 222 compact)
check "two sessions: B's compaction gets B's note" '[[ $out == *task-b* && $out != *task-a* ]]'
out=$(begin A2 111 clear)
check "two sessions: A's /clear gets A's note, not B's" '[[ $out == *task-a* && $out != *task-b* && $out == *"build on it"* ]]'
out=$(begin B2 222 clear)
check "two sessions: B's /clear gets B's note" '[[ $out == *task-b* && $out != *task-a* ]]'
out=$(begin A2 111 compact)
check "two sessions: the note stays with the session /clear started" '[[ $out == *task-a* && $out != *task-b* ]]'
out=$(begin A3 111 clear)
check "two sessions: and through another /clear" '[[ $out == *task-a* && $out != *task-b* ]]'
out=$(begin C 333 startup)
check "a brand-new session gets one line about the note, not the note" '[[ $out == *"earlier session"* && $out == *".newleaf/handoff.md (written w, branch none, head none)"* && $out != *task-* && $out != *"build on it"* ]]'
check "and it is told the note may be other work" '[[ $out == *"other work"* ]]'
out=$(begin D 444 clear)
check "/clear with no note of its own: one line, not another session's note" '[[ $out == *"earlier session"* && $out != *task-* ]]'
out=$(begin E 555 compact)
check "a compaction with no note of its own: nothing about notes" '[[ $out != *handoff* && $out != *task-* ]]'
say B 222 task-b2
say B 222 task-b3
out=$(begin A3 111 compact)
check "B saving again and again leaves A's note alone" '[[ $out == *task-a* ]]'
say P 888 old-work
begin N 888 startup >/dev/null
out=$(begin N2 888 clear)
check "a reused process id does not bring back a dead process's note" '[[ $out != *old-work* ]]'
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45; do : > "$proj/.newleaf/notes/old$i.md"; done
say Q 999 newest
check "old notes are trimmed, the newest stays" '[ "$(ls "$proj/.newleaf/notes" | wc -l)" -le 40 ] && grep -q newest "$proj/.newleaf/notes/Q.md"'
check "the notes stay out of git" '[ -z "$(git -C "$proj" status --porcelain)" ]'

rm -rf "$proj/.newleaf"
for s in startup clear compact; do begin Z 777 "$s" >/dev/null; done
check "a folder with no note stays untouched" '[ ! -e "$proj/.newleaf" ]'

# one session: /newleaf then /clear gives the model the same bytes the token proof measured
say S 666 only-note
out=$(begin S2 666 clear)
want=$(cat "$here/rules.md"; printf '\nHandoff note from the last session (.newleaf/handoff.md). It records what was decided: build on it, do not re-decide it.\n\n---\nwritten: w\nbranch: none\nhead: none\n---\n## Next\nonly-note\n')
check "one session: /clear gives the same bytes as the measured runs" '[ "$out" = "$want" ]'

# --- the skill's facts run anywhere: Claude Code stops the skill if one fails -
plain="$tmp/plain"
mkdir -p "$plain"
facts=$(sed -n 's/.*!`\(.*\)`.*/\1/p' "$here/skills/newleaf/SKILL.md")
check "skill: it has fact commands" '[ "$(printf "%s\n" "$facts" | grep -c .)" -ge 5 ]'
check "skill: every fact command exits 0 outside a git repo" 'while IFS= read -r c; do (cd "$plain" && GIT_CEILING_DIRECTORIES="$tmp" bash -c "$c" >/dev/null 2>&1) || exit 1; done <<< "$facts"'
check "skill: and inside one" 'while IFS= read -r c; do (cd "$proj" && bash -c "$c" >/dev/null 2>&1) || exit 1; done <<< "$facts"'

# --- the two plugin layouts ------------------------------------------------
check "Claude Code hooks file names the three scripts" 'for s in start guard save; do grep -q "hooks/$s.sh" "$here/hooks/hooks.json" || exit 1; done'
check "Codex hooks file: same scripts, no Claude-only keys" 'for s in start guard save; do grep -q "hooks/$s.sh" "$here/hooks/codex-hooks.json" || exit 1; done; ! grep -q "\"shell\"" "$here/hooks/codex-hooks.json"'
check "Codex manifest points at files that exist" '[ -d "$here/skills/newleaf" ] && [ -f "$here/hooks/codex-hooks.json" ] && grep -q "\"./hooks/codex-hooks.json\"" "$here/.codex-plugin/plugin.json"'
check "both manifests carry the same version" '[ "$(grep -o "\"version\": *\"[^\"]*\"" "$here/.claude-plugin/plugin.json")" = "$(grep -o "\"version\": *\"[^\"]*\"" "$here/.codex-plugin/plugin.json")" ]'
for py in python3 python; do
  if "$py" -c '' 2>/dev/null; then
    check "every JSON file parses" '"$py" -c "import json,sys; [json.load(open(f, encoding=\"utf-8\")) for f in sys.argv[1:]]" "$here"/.claude-plugin/*.json "$here"/.codex-plugin/*.json "$here"/hooks/*.json'
    break
  fi
done

echo "$fails failed"
exit "$fails"
