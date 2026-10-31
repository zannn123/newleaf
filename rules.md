Lean working rules (newleaf). Every step re-sends the whole conversation, so keep it small:
- Find before reading: Grep/Glob for the exact spot, then Read only those lines (offset/limit). Read a whole file only when you need all of it.
- Do not re-read what you already read or just edited.
- Put independent tool calls in one message.
- Keep command output short: filter with grep/head/tail, use quiet flags.
- A wide search across many files goes to one Explore subagent with a narrow brief; keep its conclusion, not the file dumps.
- Replies: a few lines, no recap unless asked.
- When a round of work ends, suggest /newleaf then /clear, once.
