#!/usr/bin/env bash
# newleaf, SessionStart (new session, /clear, compaction): prints the lean
# working rules and the handoff note that belongs to this session: its own after
# a compaction, the one its process saved before /clear. A brand-new session
# gets one line about the folder's latest note instead, since that note may be
# another session's other work. Claude Code adds plain stdout to the new
# session's context. Prints nothing when there is nothing to add.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
input=$(cat)
proj=$(project_dir "$input")
[ "$(config rules "$proj")" = false ] || cat "$NEWLEAF_ROOT/rules.md"

dir="$proj/.newleaf"
source=$(printf '%s' "$input" | json_str source)
sid=$(session_id "$input")
link="$dir/notes/pid-${CLAUDE_PID:-none}.link"
note=
case $source in
  compact)
    [ -z "$sid" ] || note="$dir/notes/$sid.md"
    ;;
  clear)
    # /clear keeps the process and starts a new session: the note moves to it
    if [ -s "$link" ]; then
      note="$dir/notes/$(cat "$link").md"
      if [ -s "$note" ] && [ -n "$sid" ] && cp -f "$note" "$dir/notes/$sid.md"; then
        note="$dir/notes/$sid.md"
        printf '%s' "$sid" > "$link"
      fi
    fi
    ;;
  startup | '')
    # a new process: anything under its id belonged to a dead one
    rm -f "$link"
    ;;
esac

# the note's front matter (written, branch, head)
meta() { sed -n "1,/^---\$/{s/^$1:[[:space:]]*//p;}" "$note" | head -n 1 | tr -d '\r'; }

if [ -z "$note" ] || [ ! -s "$note" ]; then
  # a running session that compacts keeps to its own work
  [ "$source" != compact ] || exit 0
  note="$dir/handoff.md"
  [ -s "$note" ] || exit 0
  facts=
  for key in written branch head; do
    value=$(meta "$key")
    [ -z "$value" ] || facts="$facts${facts:+, }$key $value"
  done
  printf '\nA handoff note from an earlier session is at .newleaf/handoff.md%s. It may be about other work: read it only if the user asks to continue that work, and otherwise ignore it.\n' "${facts:+ ($facts)}"
  exit 0
fi

label=.newleaf/handoff.md
cmp -s "$note" "$dir/handoff.md" || label=".newleaf/notes/${note##*/}"
printf '\nHandoff note from the last session (%s). It records what was decided: build on it, do not re-decide it.\n\n' "$label"
cat "$note"

# the note against the repo now
then_head=$(meta head) then_branch=$(meta branch)
now_head=$(git -C "$proj" rev-parse --short HEAD 2>/dev/null)
now_branch=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null)
drift=
if [ -n "$then_head" ] && [ "$then_head" != none ] && [ -n "$now_head" ] \
   && [ "${now_head#"$then_head"}" = "$now_head" ] && [ "${then_head#"$now_head"}" = "$then_head" ]; then
  count=$(git -C "$proj" rev-list --count "$then_head..HEAD" 2>/dev/null)
  drift="HEAD is now $now_head, ${count:+$count commits after the note ($then_head)}"
  [ -n "$count" ] || drift="HEAD is now $now_head, a different commit from the note ($then_head)"
fi
if [ -n "$then_branch" ] && [ "$then_branch" != none ] && [ -n "$now_branch" ] && [ "$then_branch" != "$now_branch" ]; then
  drift="${drift:+$drift; }the branch is now $now_branch (the note says $then_branch)"
fi
[ -z "$drift" ] || printf '\nSince the note: %s. Check git log before relying on its State.\n' "$drift"
