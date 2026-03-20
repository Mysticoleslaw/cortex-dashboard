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
    ("usage",    "Usage (lines, tokens, cache, burn)"),
    ("disk",     "Disk usage"),
    ("pwd",      "Working directory + git status"),
    ("memory",   "Memory file counts"),
    ("activity", "Activity heatmap (1d, 1w, 1mo, year)"),
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
    # sections + sep + activity subs + sep + presets
    total_items = len(SECTIONS) + 1 + len(ACTIVITY_SUBS) + 1 + len(PRESETS)
    sep1 = len(SECTIONS)              # first separator (after sections)
    sep2 = sep1 + 1 + len(ACTIVITY_SUBS)  # second separator (after activity subs)
    modified = False
    message = ""

    while True:
        stdscr.clear()
        height, width = stdscr.getmaxyx()

        # Title
        title = "── CORTEX · Config ──"
        stdscr.addstr(1, 2, title, curses.color_pair(7) | curses.A_BOLD)

        # Sections header
        stdscr.addstr(3, 4, "SECTIONS", curses.color_pair(1) | curses.A_BOLD)
        y = 5

        for i, (key, label) in enumerate(SECTIONS):
            is_on = config.get("sections", {}).get(key, True)
            val_str = "true" if is_on else "false"
            val_color = curses.color_pair(2) if is_on else curses.color_pair(3)

            if selected == i:
                # Highlighted row
                row = f"  {label:<45} {val_str:>8}"
                padded = row.ljust(width - 4)
                stdscr.addstr(y, 2, padded[:width-4], curses.color_pair(4) | curses.A_BOLD)
            else:
                stdscr.addstr(y, 4, f"{label:<45}", curses.color_pair(6))
                stdscr.addstr(y, 49, val_str, val_color)
            y += 1

        # Activity sub-toggles
        y += 1
        stdscr.addstr(y, 4, "ACTIVITY VIEWS", curses.color_pair(5) | curses.A_BOLD)
        y += 2

        for j, (sub_key, sub_label) in enumerate(ACTIVITY_SUBS):
            item_idx = sep1 + 1 + j
            is_on = config.get("activity", {}).get(sub_key, True)
            val_str = "true" if is_on else "false"
            val_color = curses.color_pair(2) if is_on else curses.color_pair(3)

            if selected == item_idx:
                row = f"  {sub_label:<45} {val_str:>8}"
                padded = row.ljust(width - 4)
                stdscr.addstr(y, 2, padded[:width-4], curses.color_pair(4) | curses.A_BOLD)
            else:
                stdscr.addstr(y, 4, f"{sub_label:<45}", curses.color_pair(6))
                stdscr.addstr(y, 49, val_str, val_color)
            y += 1

        # Presets
        y += 1
        stdscr.addstr(y, 4, "PRESETS", curses.color_pair(5) | curses.A_BOLD)
        y += 2

        for j, (preset_key, preset_label) in enumerate(PRESETS):
            item_idx = sep2 + 1 + j
            if selected == item_idx:
                row = f"  {preset_label:<45}"
                padded = row.ljust(width - 4)
                stdscr.addstr(y, 2, padded[:width-4], curses.color_pair(4) | curses.A_BOLD)
            else:
                stdscr.addstr(y, 4, preset_label, curses.color_pair(6))
            y += 1

        # Footer
        footer_y = min(y + 2, height - 3)
        if message:
            stdscr.addstr(footer_y, 4, message, curses.color_pair(2))
            footer_y += 1

        controls = "Space: toggle · Enter: save & exit · q: quit without saving"
        if footer_y < height - 1:
            stdscr.addstr(footer_y + 1, 4, controls, curses.color_pair(1))

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
            message = ""

        elif key == curses.KEY_DOWN or key == ord("j"):
            selected = min(total_items - 1, selected + 1)
            if selected == sep1:
                selected = sep1 + 1
            if selected == sep2:
                selected = sep2 + 1
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
                # Toggle activity sub-view
                sub_idx = selected - sep1 - 1
                sub_key = ACTIVITY_SUBS[sub_idx][0]
                current = config.get("activity", {}).get(sub_key, True)
                config.setdefault("activity", {})[sub_key] = not current
                state = "ON" if not current else "OFF"
                message = f"  {ACTIVITY_SUBS[sub_idx][1]} → {state}"
                modified = True
            elif selected > sep2:
                # Apply preset
                preset_idx = selected - sep2 - 1
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
