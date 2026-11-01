---
name: newleaf
description: Turn over a new leaf. Writes a handoff note of where the work stands, so /clear starts a fresh, small session that keeps the thread. Use when the user types /newleaf, asks to hand off or start fresh, or when newleaf says the chat has grown.
allowed-tools: Bash(git:*), Bash(date:*), Bash(head:*), Bash(echo:*)
---

Facts, gathered just now:
- date: !`date '+%Y-%m-%dT%H:%M:%S%z'`
- branch: !`git rev-parse --abbrev-ref HEAD 2>/dev/null || echo none`
- head: !`git rev-parse --short HEAD 2>/dev/null || echo none`
- changed files: !`git status --short 2>/dev/null | head -20`
- recent commits: !`git log --oneline -5 2>/dev/null || echo none`

If a fact above still shows its command instead of a value (some tools do not run these), run those commands yourself in one shell call first.

Write the handoff note now, in this one reply, with no other tool calls. Put it between the two marker lines exactly as shown, with no code fence around it: newleaf saves what is between them to `.newleaf/handoff.md` and loads it into the next session.

<newleaf-note>
---
written: <date from the facts>
branch: <branch from the facts>
head: <head from the facts>
---
## Rules in play
The user's rules this work depends on that CLAUDE.md and memory do not already hold, one line each, in their words where possible.
## Decided
Decisions made in this conversation, each with its reason in a few words, including what was decided against.
## State
Done and verified (commits, test results); in progress (files touched, uncommitted changes); not started.
## Next
The exact next step.
## Open
Questions only the user can answer.
</newleaf-note>

After the closing marker, one line: `Saved for the next session. Type /clear to continue fresh.`

Rules for the note:
- Only facts from this conversation and the facts above. Mark anything not verified "(unverified)". No new ideas, no plans the user did not agree to.
- Under 60 lines. Leave a section with "none" rather than padding it.
- No secrets, keys, passwords or personal data.
