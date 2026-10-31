# How the proof was measured

**Question.** Does newleaf cut the tokens a Claude Code task costs, without
changing what the task produces?

**Task.** One real request on a real production Flutter codebase (private):
"change the Download split button from the filled style to the line style,
both halves, and make the divider between them match". Same starting commit,
same prompt, same model (`claude-opus-5-5`), headless `claude -p` runs on
2026-10-31.

**Conditions.**

| Group | What ran |
| --- | --- |
| resumed session | A real session resumed at the moment its owner paused work (440k tokens of history), then given the task. This is the habit newleaf replaces. |
| fresh session, no plugin | A new session, nothing installed. |
| fresh + newleaf | A new session with newleaf: the lean working rules and a handoff note written by `/newleaf` from that same paused session. |
| handoff with /newleaf | The paused session, given `/newleaf`: what one handoff costs. |
| prototype rows | Earlier versions measured on the way (a 4-step handoff, the note without rules). Kept for completeness. |

**Tokens.** Read from each run's own Claude Code session log: for every API
call, everything it re-sent (fresh input + cache write + cache read) plus what
it wrote (output), each call counted once.

**Quality.** Every task run had to pass, from the code itself: the button's
both halves in the line style with the divider in the theme's line colour, no
colour literal added, changes only in the feature's folder, no new analyzer
issue, and the project's 97 report tests green. Handoff runs had to produce a
complete note (front matter, the five sections, under 60 lines, nothing
secret-looking).

**Results.** [`runs.csv`](runs.csv), one row per run. Draw the charts again
with `python docs/proof/figures.py`.

**Limits.** One codebase, one task type, headless runs (the interactive app
loads a few more tools on both sides). Your numbers will differ; measure your
own with `python tools/measure.py --days 7`.
