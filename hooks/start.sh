#!/usr/bin/env bash
# newleaf, SessionStart (new session, /clear, compaction): prints the lean
# working rules and this project's handoff note. Claude Code adds plain stdout
# to the new session's context. Prints nothing when there is nothing to add.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
input=$(cat)
proj=$(project_dir "$input")
[ "$(config rules "$proj")" = false ] || cat "$NEWLEAF_ROOT/rules.md"
note="$proj/.newleaf/handoff.md"
[ -s "$note" ] || exit 0
printf '\nHandoff note from the last session (.newleaf/handoff.md). It records what was decided: build on it, do not re-decide it.\n\n'
cat "$note"

# the note's front matter (written, branch, head) against the repo now
meta() { sed -n "1,/^---\$/{s/^$1:[[:space:]]*//p;}" "$note" | head -n 1 | tr -d '\r'; }
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
