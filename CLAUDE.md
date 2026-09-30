# Cortex — Claude Code Dashboard

A multi-line statusline dashboard for the Claude Code CLI. Claude Code pipes session JSON to the script on stdin and displays whatever it prints.

## Stack

- `cortex.sh`: the dashboard (bash + `jq`). Installed as `~/.claude/statusline-command.sh`.
- `usage-heatmap.py`: the ACTIVITY section renderer (python3, stdlib only).
- `cortex-config-tui.py`: curses config screen (`cortex-config`). Its lists (`SECTIONS`, `PLAN_SUBS`, `ACTIVITY_SUBS`) drive the UI generically.
- `cortex-command.md`: the `/cortex` slash command, installed to `~/.claude/commands/cortex.md`.
- `get.sh`: the `curl … | bash` one-liner. Installs the latest release tag (or `CORTEX_REF`) into `~/.cortex-dashboard` and runs `install.sh`. Keep its body inside `main()` so a truncated download never runs a partial script.
- `cortex-cli.sh`: the `cortex` command (update / rollback / use / version / versions), installed to `~/.claude/cortex-cli.sh`. Versions come from `git ls-remote` tags `vX.Y.Z`. Wrapped in `main(); exit` because `install.sh` replaces it mid-run.
- `install.sh` / `uninstall.sh`: copy files into `~/.claude` and set/remove `statusLine` in `settings.json` (with `refreshInterval: 30`).

## Architecture

- **One jq pass.** All payload fields are extracted in a single `jq` call at the top of `cortex.sh` and `eval`'d as shell-quoted variables (`sh()` helper, `@sh`). Add new fields there, not with extra `jq` calls: the script runs every 30s in every session.
- **Config is read once** into `$DISABLED` (" disk plan.7d "); use `section_enabled` / `subsection_enabled`. Missing keys mean enabled.
- **Caches** live in `$CACHE_DIR` (`CORTEX_CACHE_DIR`, default `/tmp`) as `claude-statusline-*`: weather 30 min, disk 1 min, git 5s **per directory** (cksum of the dir), heatmap 30s (written to a temp file, then `mv`). Use `cache_stale <file> <seconds>`.
- **Two data logs in `~/.claude`:**
  - `usage-history.tsv`: one row per session (duration, cost), upserted under a `mkdir` lock with a `mktemp` file. Concurrent renders are normal, so never rewrite it without the lock.
  - `activity-minutes.log`: one `YYYY-MM-DD HH:MM` line per minute in which any session did work (cost or API time changed, tracked in `$CACHE_DIR/claude-statusline-sess-<id>`). The heatmap uses it (gap-fills ≤5 min) and falls back to capped `usage-history.tsv` data for days before it existed.
- Statusline field reference: https://code.claude.com/docs/en/statusline. Fields can be absent: render nothing rather than a fake 0.

## Releasing

Users only get what's released. `get.sh`, `cortex update`, and the header notice all follow the latest `vX.Y.Z` tag, not `Main`.

1. Bump `VERSION` (e.g. `v1.4.0`) and add a `CHANGELOG.md` section in the same PR.
2. After merging, publish a GitHub Release tagged exactly `VERSION` on the merge commit, with that changelog section as the notes.
3. Never delete or move a published tag: `cortex rollback` depends on them.

## Commands

```bash
./tests/run.sh      # full suite: sandboxed HOME + cache dir, never touches real ~/.claude
bash install.sh     # install into ~/.claude (keeps existing cortex-config.json)
```

CI (`.github/workflows/test.yml`) runs syntax checks and the suite on ubuntu-latest and macos-latest.

## Conventions and gotchas

- The default branch is **`Main`** (capital M). PRs target `Main`; squash-merge.
- Keep the script portable across macOS (BSD) and Linux (GNU): `file_mtime` branches on `uname`; avoid `sed -i`, GNU-only flags, and `awk` features mawk lacks (e.g. `nextfile`).
- Anything interpolated into output from the payload must be treated as untrusted. Strip control characters before emitting it inside escape sequences (see the OSC 8 PR link).
- Anything that writes outside `~/.claude` must honor an env override (`CORTEX_CACHE_DIR`, `CORTEX_BIN_DIR`, `CORTEX_DIR`) so tests can sandbox it. The suite must never touch real `/tmp` caches or `/usr/local/bin`.
- Tests compare rendered countdowns as text. Give fixture timestamps a little slack (e.g. `NOW + 2550` for "42m"), or a render landing a second later flakes.
- Color thresholds: context/plan 70/90%, cache hit 70/40%, disk 75/90%. The dot is blue when healthy.
- After changing a section, update the README's "Reading the Dashboard" tables and, if it's a new toggle, the TUI lists, `cortex-config.default.json`, and `cortex-command.md`.
- Test changes live with `bash install.sh` from the working tree; running sessions pick up the new script on their next refresh.
