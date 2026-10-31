# Changelog

## 1.0.0 (2026-10-31)

First release.

- `/newleaf`: writes the handoff note in one reply; git facts are gathered before the model reads the skill.
- Stop hook saves the note to `.newleaf/handoff.md`, keeps the previous one, and hides the folder from git.
- Start hook loads the lean working rules and the note into every new session, `/clear` and compaction, and flags commits or a branch change since the note.
- Guard: speaks when a step re-sends 2x the chat's first step, again at 4x and 8x; `warn_at` setting.
- Plain bash hooks, no Python: tested on Windows (Git Bash), Ubuntu, Debian (mawk), Alpine (busybox awk) and macOS (CI).
- Measured: 86% fewer tokens per task on the same task with the same quality checks ([docs/proof](docs/proof)).
