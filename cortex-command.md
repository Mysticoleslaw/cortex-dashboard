# Cortex Dashboard Manager

Manage the Cortex statusline dashboard sections and settings.

## Usage

- `/cortex` — show current config and all section statuses
- `/cortex settings` — open interactive config TUI in a new Terminal window
- `/cortex toggle <section>` — toggle a section on/off
- `/cortex on <section>` — enable a section
- `/cortex off <section>` — disable a section
- `/cortex reset` — reset all sections to enabled
- `/cortex minimal` — only show context + pwd
- `/cortex full` — enable all sections

## Available Sections

| Section | Key | What it shows |
|---------|-----|---------------|
| Location | `loc` | City, time, weather |
| Environment | `env` | CC version, model, skills, hooks, cost |
| Context | `context` | Context window progress bar |
| Plan | `plan` | Claude plan usage — 5h + 7d rate-limit bars with reset countdown |
| Usage | `usage` | Lines, duration, tokens, cache, burn rate |
| Disk | `disk` | Local disk usage |
| Working Dir | `pwd` | Directory, git branch, modified, sync |
| Memory | `memory` | Memory file counts by type |
| Activity | `activity` | Heatmap: 1d, 1w, 1mo, 52-week grid |

## Instructions

The config file is at `~/.claude/cortex-config.json`. Read it to show current state. Modify it with the requested changes using the Edit or Write tool.

### When the user runs `/cortex` with no args:
Read `~/.claude/cortex-config.json` and display the current config as a clean table showing which sections are ON/OFF.

### When the user runs `/cortex toggle <section>`:
1. Read `~/.claude/cortex-config.json`
2. Flip the boolean for `sections.<section>`
3. Write the updated config
4. Confirm: "Cortex: <section> is now ON/OFF"

### When the user runs `/cortex on <section>` or `/cortex off <section>`:
1. Read `~/.claude/cortex-config.json`
2. Set `sections.<section>` to true/false
3. Write the updated config
4. Confirm

### When the user runs `/cortex reset`:
Set all sections to `true` and write the config.

### When the user runs `/cortex minimal`:
Set all sections to `false` except `context` and `pwd`, then write the config.

### When the user runs `/cortex full`:
Set all sections to `true` and write the config.

### When the user runs `/cortex settings`:
Run this bash command to open the interactive TUI in a new Terminal window:
```bash
osascript -e "tell application \"Terminal\" to do script \"python3 $HOME/.claude/cortex-config-tui.py\""
```
Then confirm: "Cortex config TUI opened in a new window."

### Validation:
If the section key doesn't match one of: `loc`, `env`, `context`, `plan`, `usage`, `disk`, `pwd`, `memory`, `activity` — tell the user the valid options.

Changes take effect on the next Claude Code interaction (statusline auto-refreshes).
