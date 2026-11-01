# Changelog

## 1.1.2 (2026-11-02)

- `/newleaf` works outside a git repository (a home folder, say). Its `git log` fact had no fallback, so it failed there and Claude Code stopped the skill with "Shell command failed". Every fact command now ends cleanly anywhere; `tests/hooks.sh` runs each one inside and outside a repo, and `tests/smoke.sh` saves a real note outside one.

## 1.1.1 (2026-10-31)

- Codex on Windows: Codex runs Windows hooks as `cmd.exe /C "<commandWindows>"`, where `$CLAUDE_PLUGIN_ROOT` never expands, so every hook failed there. Each Codex hook now has a `commandWindows` that runs `hooks/run.cmd`, which finds Git Bash (from `CLAUDE_CODE_GIT_BASH_PATH`, else next to your git) and runs the same bash hook, stdin and stdout passed through untouched.
- `tests/windows_cmd.py` runs the Codex hooks exactly that way (also in CI on Windows).

## 1.1.0 (2026-10-31)

- Codex (experimental): a Codex manifest, `.codex-plugin/plugin.json`, with the hooks in Codex's own schema (`hooks/codex-hooks.json`), running the same bash scripts. Codex reads this repo's `.claude-plugin/marketplace.json`.
- The guard also reads Codex's `token_count` log lines.
- `/newleaf` tells the model to run the git facts itself where a tool does not fill them in.

## 1.0.0 (2026-10-31)

First release.

- `/newleaf`: writes the handoff note in one reply; git facts are gathered before the model reads the skill.
- Stop hook saves the note to `.newleaf/handoff.md`, keeps the previous one, and hides the folder from git.
- Start hook loads the lean working rules and the note into every new session, `/clear` and compaction, and flags commits or a branch change since the note.
- Guard: speaks when a step re-sends 2x the chat's first step, again at 4x and 8x; `warn_at` setting.
- Plain bash hooks, no Python: tested on Windows (Git Bash), Ubuntu, Debian (mawk), Alpine (busybox awk) and macOS (CI).
- Measured: 86% fewer tokens per task on the same task with the same quality checks ([docs/proof](docs/proof)).
