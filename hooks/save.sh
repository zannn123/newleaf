#!/usr/bin/env bash
# newleaf, Stop: when the reply carries a handoff note between <newleaf-note>
# markers (the /newleaf skill writes one), saves it to .newleaf/handoff.md,
# keeps the old one as handoff.prev.md, and adds a .gitignore that keeps the
# folder out of git. Claude Code passes the reply as last_assistant_message.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
input=$(cat)
msg=$(printf '%s' "$input" | json_str last_assistant_message)
case $msg in *'<newleaf-note>'*'</newleaf-note>'*) ;; *) exit 0 ;; esac

# the lines between the markers, without a wrapping code fence or blank edges
note=$(printf '%s\n' "$msg" | LC_ALL=C awk '
  !on && (p = index($0, "<newleaf-note>")) { on = 1; $0 = substr($0, p + 14) }
  on && (q = index($0, "</newleaf-note>")) { line[++n] = substr($0, 1, q - 1); done = 1; exit }
  on { line[++n] = $0 }
  END {
    if (!done) exit 1
    a = 1; while (a <= n && line[a] ~ /^[ \t\r]*(```.*)?$/) a++
    b = n; while (b >= a && line[b] ~ /^[ \t\r]*(```.*)?$/) b--
    for (i = a; i <= b; i++) print line[i]
  }')
[ -n "$note" ] || exit 0

dir="$(project_dir "$input")/.newleaf"
mkdir -p "$dir" || exit 0
[ -f "$dir/.gitignore" ] || printf '# newleaf: keep handoff notes out of git\n*\n' > "$dir/.gitignore"
[ -f "$dir/handoff.md" ] && mv -f "$dir/handoff.md" "$dir/handoff.prev.md"
printf '%s\n' "$note" > "$dir/handoff.md"
printf '{"systemMessage": "newleaf: note saved to .newleaf/handoff.md (%s lines). Type /clear to continue in a fresh session that starts with it."}\n' \
  "$(printf '%s\n' "$note" | wc -l | tr -d ' ')"
