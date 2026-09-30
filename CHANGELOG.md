# Changelog

All notable changes to Cortex are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.3.0] — 2026-09-30

### Added
- **One-line install:** `curl -fsSL https://raw.githubusercontent.com/Mysticoleslaw/cortex-dashboard/Main/get.sh | bash`. It downloads into `~/.cortex-dashboard` (with git, or a tarball if git is missing) and runs `install.sh`. Re-run it to update. `CORTEX_REF` pins a branch or tag.
- `CORTEX_BIN_DIR` sets where the `cortex-config` shortcut goes (default `/usr/local/bin`).

### Fixed
- `uninstall.sh` respects `CORTEX_CACHE_DIR`, so the test suite no longer clears real caches in `/tmp`.

## [1.2.0] — 2026-09-30

Brings Cortex up to date with the Claude Code 2.1.2xx statusline data and fixes several long-standing bugs.

### Added
- **ENV:** reasoning effort level (`low` → `max`) and a ⚡fast badge when fast mode is on.
- **Header:** the session name, from `--name`, `/rename`, or the AI-generated title.
- **USAGE:** the prompt cache shows `warm 42m` / `cold`. The countdown turns yellow in the last 5 minutes so you can send the next prompt before the cache expires.
- **PLAN:** a SPEND bar for Claude apps gateway spend limits, with its own `plan.spend` toggle in the TUI and config.
- **PWD:** worktree name and the open PR/MR with its review state (✓ approved · … pending · ✗ changes requested · ◌ draft). The badge is Cmd/Ctrl+clickable in terminals with hyperlink support.
- **Refresh:** the installer sets `statusLine.refreshInterval: 30`, so the clock and countdowns stay current while idle. Existing statusLine options are preserved.
- **Tests:** `tests/run.sh` has 35 sandboxed checks and never touches your real `~/.claude`. CI runs them on Linux and macOS.
- `CLAUDE.md` with architecture notes for contributors.

### Changed
- **Activity heatmap measures active time.** A minute counts only when a session did work, so idle sessions no longer count and parallel sessions no longer stack. Short gaps (≤5 min) between active minutes are filled. Data lives in `~/.claude/activity-minutes.log`; older days fall back to the previous log, capped at 60 min/hour and 24h/day.
- **Burn rate** is cost per minute of Claude working (API time), so it no longer drifts down while a session sits idle.
- **Cache hit ratio** is session-wide (from `prompt_cache`) instead of the last API call only.
- **⚠ >200K** is shown only on 200K-window models; on 1M windows it was noise.
- **Tk ↓/↑** is documented as tokens in the context window. Claude Code reports these per response, not as a cumulative total.
- **Faster renders:** all fields are read in one `jq` pass and the config in one more (previously ~35 `jq` calls per render). A render takes about 0.1s.
- **Uninstall** also removes the config TUI, `/cortex` command, `cortex-config` symlink, and all caches, and keeps your config and logs.

### Fixed
- **Usage history was being erased.** Concurrent renders shared one temp file and overwrote each other. Writes are now locked, with a unique temp file per writer.
- **Git info leaked between sessions.** One global cache meant parallel sessions in different repos could show each other's branch. The cache is now per directory.
- **MEMORY counts were wrong** for memory files without a `<type>_` filename prefix. Files are now classified by their frontmatter `type:`.
- **SK count** counted every file under `skills/` and `agents/`. It now counts actual skills and agents.
- **PLAN bars** showed a fake 0% "resetting" when a window was missing from the data. The rows are now hidden.
- **Activity heatmap could flash empty** while being regenerated. It's now written atomically.
- Cache age checks work on Linux (GNU `stat`), not just macOS.

## [1.1.0] — 2026-04-17

### Added
- **PLAN section:** 5-hour and 7-day rate-limit bars with a reset countdown, toggleable independently.

### Changed
- Daily activity bars scale to a 24-hour ceiling; bar thresholds tuned (full bar at 8h daily, 60m hourly).

### Fixed
- Config TUI no longer breaks on tall layouts.

## [1.0.0] — 2026-03-20

- Initial release: LOC, ENV, CONTEXT, USAGE, DISK, PWD, MEMORY, and ACTIVITY sections, the `/cortex` slash command, and the interactive config TUI.
