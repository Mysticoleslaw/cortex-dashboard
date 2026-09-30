#!/usr/bin/env python3
"""Renders usage heatmap with full-year GitHub-style grid and bar charts."""

import json
import os
from datetime import datetime, timedelta
from collections import defaultdict

HISTORY_FILE = os.path.expanduser("~/.claude/usage-history.tsv")
ACTIVITY_FILE = os.path.expanduser("~/.claude/activity-minutes.log")
GAP_FILL_MIN = 5  # idle gaps up to this long between active minutes still count
CONFIG_FILE = os.path.expanduser("~/.claude/cortex-config.json")


def load_config():
    """Load activity sub-toggles from config."""
    defaults = {"1d": True, "1w": True, "1mo": True, "year": True}
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE) as f:
                cfg = json.load(f)
            return {k: cfg.get("activity", {}).get(k, True) for k in defaults}
        except (json.JSONDecodeError, KeyError):
            pass
    return defaults

RESET = "\033[0m"
DIM = "\033[90m"
WHITE = "\033[1;37m"
CYAN = "\033[36m"
GREEN = "\033[32m"

C0 = "\033[38;5;237m"
C1 = "\033[38;5;22m"
C2 = "\033[38;5;28m"
C3 = "\033[38;5;34m"
C4 = "\033[38;5;46m"
COLORS = [C0, C1, C2, C3, C4]

BARS = [" ", "▁", "▂", "▃", "▅", "▆", "█"]


def load_activity():
    """Active minutes from activity-minutes.log, with short gaps filled.

    Each line is one minute ("YYYY-MM-DD HH:MM") in which any session did work.
    Gaps of up to GAP_FILL_MIN between active minutes count as active too, so
    time spent reading output or typing the next prompt isn't lost.
    """
    minutes = set()
    if os.path.exists(ACTIVITY_FILE):
        with open(ACTIVITY_FILE) as f:
            for line in f:
                try:
                    minutes.add(datetime.strptime(line.strip(), "%Y-%m-%d %H:%M"))
                except ValueError:
                    continue

    ordered = sorted(minutes)
    for prev, cur in zip(ordered, ordered[1:]):
        gap = int((cur - prev).total_seconds() // 60)
        if 1 < gap <= GAP_FILL_MIN:
            minutes.update(prev + timedelta(minutes=i) for i in range(1, gap))

    daily = defaultdict(float)
    hourly = defaultdict(float)
    for m in minutes:
        day = m.strftime("%Y-%m-%d")
        daily[day] += 1
        hourly[(day, m.hour)] += 1
    first_day = ordered[0].strftime("%Y-%m-%d") if ordered else None
    return daily, hourly, first_day


def load_usage():
    """Merge active-minute data with legacy per-session history.

    Days before the activity log existed fall back to usage-history.tsv, which
    records whole-session wall-clock time (inflated by idle and parallel
    sessions), so those values are capped at 60 min/hour and 24h/day.
    """
    daily, hourly, first_day = load_activity()
    legacy_daily, legacy_hourly = load_history()
    for day, mins in legacy_daily.items():
        if first_day is None or day < first_day:
            daily[day] = min(mins, 1440)
    for (day, h), mins in legacy_hourly.items():
        if first_day is None or day < first_day:
            hourly[(day, h)] = min(mins, 60)
    return daily, hourly


def load_history():
    daily = defaultdict(float)
    hourly = defaultdict(float)

    if not os.path.exists(HISTORY_FILE):
        return daily, hourly

    seen = {}
    with open(HISTORY_FILE) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 5:
                continue
            date_str, hour, sid, dur, cost = parts[:5]
            try:
                dur = float(dur)
                h = int(hour)
            except ValueError:
                continue

            if sid in seen:
                od, oh, odur = seen[sid]
                daily[od] -= odur
                hourly[(od, oh)] -= odur

            seen[sid] = (date_str, h, dur)
            daily[date_str] += dur
            hourly[(date_str, h)] += dur

    return daily, hourly


def intensity(minutes, thresholds=(5, 30, 90, 180)):
    if minutes <= 0:
        return 0
    for i, t in enumerate(thresholds, 1):
        if minutes <= t:
            return i
    return 4


def bar_level(minutes, thresholds=(1, 10, 30, 60, 120, 180)):
    if minutes <= 0:
        return 0
    for i, t in enumerate(thresholds, 1):
        if minutes <= t:
            return i
    return 6


def render():
    daily, hourly = load_usage()
    today = datetime.now().date()
    total_mins = sum(daily.values())
    total_hours = total_mins / 60
    active_days = sum(1 for v in daily.values() if v > 0)
    lines = []

    acfg = load_config()

    # ── Header ──
    lines.append(
        f"{GREEN}⌚{RESET} {GREEN}ACTIVITY:{RESET} "
        f"{WHITE}{total_hours:.0f}h{RESET} across "
        f"{WHITE}{active_days}{RESET} days"
    )

    # ── Bar chart rows ──
    today_str = today.strftime("%Y-%m-%d")

    if acfg["1d"]:
        row_1d = f"   {DIM}1d:{RESET} "
        has_today = False
        for h in range(24):
            m = hourly.get((today_str, h), 0)
            bl = bar_level(m, thresholds=(1, 10, 20, 30, 45, 60))
            color = COLORS[min(bl, 4)] if bl > 0 else C0
            row_1d += f"{color}{BARS[bl]}{RESET}"
            if bl > 0:
                has_today = True
        if has_today:
            row_1d += f"  {DIM}0h      12h      24h{RESET}"
        lines.append(row_1d)

    if acfg["1w"]:
        row_1w = f"   {DIM}1w:{RESET} "
        days_since_sunday = (today.weekday() + 1) % 7
        sunday = today - timedelta(days=days_since_sunday)
        for i in range(7):
            d = sunday + timedelta(days=i)
            mins = daily.get(d.strftime("%Y-%m-%d"), 0)
            bl = bar_level(mins, thresholds=(30, 180, 360, 720, 1080, 1440))
            color = COLORS[min(bl, 4)] if bl > 0 else C0
            day_lbl = d.strftime("%a")[0]
            if d > today:
                row_1w += f"{DIM}{day_lbl}{RESET} {C0}{BARS[0]}{RESET}  "
            else:
                row_1w += f"{DIM}{day_lbl}{RESET} {color}{BARS[bl]}{RESET}  "
        lines.append(row_1w)

    if acfg["1mo"]:
        row_1mo = f"  {DIM}1mo:{RESET} "
        for i in range(29, -1, -1):
            d = today - timedelta(days=i)
            mins = daily.get(d.strftime("%Y-%m-%d"), 0)
            bl = bar_level(mins, thresholds=(30, 180, 360, 720, 1080, 1440))
            if bl == 0:
                row_1mo += f"{C0}▁{RESET}"
            else:
                color = COLORS[min(bl, 4)]
                row_1mo += f"{color}{BARS[bl]}{RESET}"
        lines.append(row_1mo)

    if acfg["year"]:
        weeks = 52
        days_since_monday = today.weekday()
        end_of_week = today + timedelta(days=(6 - days_since_monday))
        start = end_of_week - timedelta(days=(weeks * 7) - 1)

        for dow in range(7):
            if dow == 0:
                label = "  Mon "
            elif dow == 2:
                label = "  Wed "
            elif dow == 4:
                label = "  Fri "
            else:
                label = "      "

            row = f"{DIM}{label}{RESET}"
            for week in range(weeks):
                d = start + timedelta(days=(week * 7) + dow)
                if d > today:
                    row += f"{C0}▪{RESET}"
                else:
                    mins = daily.get(d.strftime("%Y-%m-%d"), 0)
                    level = intensity(mins)
                    if level == 0:
                        row += f"{C0}▪{RESET}"
                    else:
                        row += f"{COLORS[level]}■{RESET}"
            lines.append(row)

        month_row = "      "
        last_month = ""
        for week in range(weeks):
            d = start + timedelta(days=week * 7)
            m = d.strftime("%b")
            if m != last_month:
                month_row += m[0]
                last_month = m
            else:
                month_row += " "
        lines.append(f"  {DIM}{month_row}{RESET}")

        legend = f"      {DIM}Less {RESET}"
        for i in range(5):
            c = "▪" if i == 0 else "■"
            legend += f"{COLORS[i]}{c}{RESET}"
        legend += f" {DIM}More{RESET}"
        lines.append(legend)

    return "\n".join(lines)


if __name__ == "__main__":
    print(render())
