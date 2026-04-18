#!/usr/bin/env python3
"""Cortex Dashboard — Interactive Config TUI"""

import curses
import json
import os
import sys

CONFIG_PATH = os.path.expanduser("~/.claude/cortex-config.json")

SECTIONS = [
    ("loc",      "Location (city, time, weather)"),
    ("env",      "Environment (version, model, cost)"),
    ("context",  "Context window progress bar"),
    ("plan",     "Plan usage limits (5h + 7d)"),
    ("usage",    "Usage (lines, tokens, cache, burn)"),
    ("disk",     "Disk usage"),
    ("pwd",      "Working directory + git status"),
    ("memory",   "Memory file counts"),
    ("activity", "Activity heatmap (1d, 1w, 1mo, year)"),
]

PLAN_SUBS = [
    ("5h", "Plan: 5-hour rate limit bar"),
    ("7d", "Plan: 7-day rate limit bar"),
]

ACTIVITY_SUBS = [
    ("1d",   "Activity: Today (24h hourly bars)"),
    ("1w",   "Activity: This week (Sun-Sat)"),
    ("1mo",  "Activity: Last 30 days sparkline"),
    ("year", "Activity: 52-week contribution grid"),
]

PRESETS = [
    ("full",    "Enable all sections"),
    ("minimal", "Context + PWD only"),
    ("compact", "Context + Usage + PWD"),
    ("reset",   "Reset to defaults (all on)"),
]


def load_config():
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            return json.load(f)
    return {"sections": {key: True for key, _ in SECTIONS}}


def save_config(config):
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")


def apply_preset(config, preset):
    if preset == "full" or preset == "reset":
        for key, _ in SECTIONS:
            config["sections"][key] = True
    elif preset == "minimal":
        for key, _ in SECTIONS:
            config["sections"][key] = key in ("context", "pwd")
    elif preset == "compact":
        for key, _ in SECTIONS:
            config["sections"][key] = key in ("context", "usage", "pwd")


def main(stdscr):
    curses.curs_set(0)
    curses.use_default_colors()

    # Init color pairs
    curses.init_pair(1, curses.COLOR_CYAN, -1)     # header/selected
    curses.init_pair(2, curses.COLOR_GREEN, -1)     # true
    curses.init_pair(3, curses.COLOR_RED, -1)       # false
    curses.init_pair(4, curses.COLOR_BLACK, curses.COLOR_CYAN)  # highlight bar
    curses.init_pair(5, curses.COLOR_YELLOW, -1)    # preset labels
    curses.init_pair(6, curses.COLOR_WHITE, -1)     # dim
    curses.init_pair(7, curses.COLOR_MAGENTA, -1)   # title

    config = load_config()
    selected = 0
    # sections + sep + plan subs + sep + activity subs + sep + presets
    total_items = (
        len(SECTIONS) + 1 + len(PLAN_SUBS) + 1 + len(ACTIVITY_SUBS) + 1 + len(PRESETS)
    )
    sep1 = len(SECTIONS)                          # separator before PLAN_SUBS
    sep2 = sep1 + 1 + len(PLAN_SUBS)              # separator before ACTIVITY_SUBS
    sep3 = sep2 + 1 + len(ACTIVITY_SUBS)          # separator before PRESETS
    modified = False
    message = ""

    while True:
        stdscr.clear()
        height, width = stdscr.getmaxyx()

        def safe_addstr(yy, xx, text, attr=0):
            if yy < 0 or yy >= height - 1 or xx < 0 or xx >= width:
                return
            try:
                stdscr.addstr(yy, xx, text[: max(0, width - xx - 1)], attr)
            except curses.error:
                pass

        # Title
        safe_addstr(1, 2, "── CORTEX · Config ──", curses.color_pair(7) | curses.A_BOLD)

        # Sections header
        safe_addstr(3, 4, "SECTIONS", curses.color_pair(1) | curses.A_BOLD)
        y = 5

        for i, (key, label) in enumerate(SECTIONS):
            is_on = config.get("sections", {}).get(key, True)
            val_str = "true" if is_on else "false"
            val_color = curses.color_pair(2) if is_on else curses.color_pair(3)

            if selected == i:
                row = f"  {label:<45} {val_str:>8}"
                safe_addstr(y, 2, row.ljust(width - 4), curses.color_pair(4) | curses.A_BOLD)
            else:
                safe_addstr(y, 4, f"{label:<45}", curses.color_pair(6))
                safe_addstr(y, 49, val_str, val_color)
            y += 1

        # Plan sub-toggles
        y += 1
        safe_addstr(y, 4, "PLAN BARS", curses.color_pair(5) | curses.A_BOLD)
        y += 1

        for j, (sub_key, sub_label) in enumerate(PLAN_SUBS):
            item_idx = sep1 + 1 + j
            is_on = config.get("plan", {}).get(sub_key, True)
            val_str = "true" if is_on else "false"
            val_color = curses.color_pair(2) if is_on else curses.color_pair(3)

            if selected == item_idx:
                row = f"  {sub_label:<45} {val_str:>8}"
                safe_addstr(y, 2, row.ljust(width - 4), curses.color_pair(4) | curses.A_BOLD)
            else:
                safe_addstr(y, 4, f"{sub_label:<45}", curses.color_pair(6))
                safe_addstr(y, 49, val_str, val_color)
            y += 1

        # Activity sub-toggles
        y += 1
        safe_addstr(y, 4, "ACTIVITY VIEWS", curses.color_pair(5) | curses.A_BOLD)
        y += 1

        for j, (sub_key, sub_label) in enumerate(ACTIVITY_SUBS):
            item_idx = sep2 + 1 + j
            is_on = config.get("activity", {}).get(sub_key, True)
            val_str = "true" if is_on else "false"
            val_color = curses.color_pair(2) if is_on else curses.color_pair(3)

            if selected == item_idx:
                row = f"  {sub_label:<45} {val_str:>8}"
                safe_addstr(y, 2, row.ljust(width - 4), curses.color_pair(4) | curses.A_BOLD)
            else:
                safe_addstr(y, 4, f"{sub_label:<45}", curses.color_pair(6))
                safe_addstr(y, 49, val_str, val_color)
            y += 1

        # Presets
        y += 1
        safe_addstr(y, 4, "PRESETS", curses.color_pair(5) | curses.A_BOLD)
        y += 1

        for j, (preset_key, preset_label) in enumerate(PRESETS):
            item_idx = sep3 + 1 + j
            if selected == item_idx:
                row = f"  {preset_label:<45}"
                safe_addstr(y, 2, row.ljust(width - 4), curses.color_pair(4) | curses.A_BOLD)
            else:
                safe_addstr(y, 4, preset_label, curses.color_pair(6))
            y += 1

        # Footer
        footer_y = min(y + 1, height - 2)
        if message:
            safe_addstr(footer_y, 4, message, curses.color_pair(2))
            footer_y += 1

        safe_addstr(
            footer_y,
            4,
            "Space: toggle · Enter: save & exit · q: quit without saving",
            curses.color_pair(1),
        )

        stdscr.refresh()

        # Input
        key = stdscr.getch()

        if key == ord("q") or key == 27:  # q or Esc
            if modified:
                # Show unsaved warning
                message = "Unsaved changes! Press q again to discard, or Enter to save."
                stdscr.refresh()
                key2 = stdscr.getch()
                if key2 == ord("q") or key2 == 27:
                    break
                elif key2 == 10 or key2 == 13:
                    save_config(config)
                    break
                else:
                    message = ""
                    continue
            break

        elif key == curses.KEY_UP or key == ord("k"):
            selected = max(0, selected - 1)
            if selected == sep1:
                selected = sep1 - 1
            if selected == sep2:
                selected = sep2 - 1
            if selected == sep3:
                selected = sep3 - 1
            message = ""

        elif key == curses.KEY_DOWN or key == ord("j"):
            selected = min(total_items - 1, selected + 1)
            if selected == sep1:
                selected = sep1 + 1
            if selected == sep2:
                selected = sep2 + 1
            if selected == sep3:
                selected = sep3 + 1
            message = ""

        elif key == ord(" "):
            if selected < len(SECTIONS):
                # Toggle section
                sec_key = SECTIONS[selected][0]
                current = config.get("sections", {}).get(sec_key, True)
                config.setdefault("sections", {})[sec_key] = not current
                state = "ON" if not current else "OFF"
                message = f"  {SECTIONS[selected][1]} → {state}"
                modified = True
            elif sep1 < selected < sep2:
                # Toggle plan sub-bar
                sub_idx = selected - sep1 - 1
                sub_key = PLAN_SUBS[sub_idx][0]
                current = config.get("plan", {}).get(sub_key, True)
                config.setdefault("plan", {})[sub_key] = not current
                state = "ON" if not current else "OFF"
                message = f"  {PLAN_SUBS[sub_idx][1]} → {state}"
                modified = True
            elif sep2 < selected < sep3:
                # Toggle activity sub-view
                sub_idx = selected - sep2 - 1
                sub_key = ACTIVITY_SUBS[sub_idx][0]
                current = config.get("activity", {}).get(sub_key, True)
                config.setdefault("activity", {})[sub_key] = not current
                state = "ON" if not current else "OFF"
                message = f"  {ACTIVITY_SUBS[sub_idx][1]} → {state}"
                modified = True
            elif selected > sep3:
                # Apply preset
                preset_idx = selected - sep3 - 1
                preset_key = PRESETS[preset_idx][0]
                apply_preset(config, preset_key)
                message = f"  Applied preset: {PRESETS[preset_idx][1]}"
                modified = True

        elif key == 10 or key == 13:  # Enter
            save_config(config)
            break

    return modified


if __name__ == "__main__":
    changed = curses.wrapper(main)
    if changed:
        print("Cortex config saved. Changes take effect on next interaction.")
    else:
        print("No changes made.")
