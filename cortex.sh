#!/bin/bash
# Cortex — Claude Code Dashboard
# https://github.com/Mysticoleslaw/cortex-dashboard

input=$(cat)

# ── Config ──
CORTEX_CONFIG="$HOME/.claude/cortex-config.json"
section_enabled() {
    local section="$1"
    if [ -f "$CORTEX_CONFIG" ]; then
        local val=$(jq -r "if .sections.${section} == false then \"false\" else \"true\" end" "$CORTEX_CONFIG" 2>/dev/null)
        [ "$val" = "true" ]
    else
        return 0  # default: all enabled
    fi
}

# ── Colors ──
C='\033[36m'      # cyan
G='\033[32m'      # green
Y='\033[33m'      # yellow
R='\033[31m'      # red
W='\033[1;37m'    # bold white
D='\033[90m'      # dim/gray
M='\033[35m'      # magenta
B='\033[34m'      # blue
RESET='\033[0m'

# ── Usage history logging ──
HISTORY_FILE="$HOME/.claude/usage-history.tsv"
log_usage() {
    local sid=$(echo "$1" | jq -r '.session_id // "unknown"')
    local dur_ms=$(echo "$1" | jq -r '.cost.total_duration_ms // 0')
    local cost=$(echo "$1" | jq -r '.cost.total_cost_usd // 0')
    local dur_min=$(awk "BEGIN { printf \"%.1f\", $dur_ms / 60000 }")
    local today=$(date +%Y-%m-%d)
    local hour=$(date +%H)

    # Create file with header if needed
    [ -f "$HISTORY_FILE" ] || echo "# date	hour	session_id	duration_min	cost" > "$HISTORY_FILE"

    # Upsert: remove old entry for this session, append new one
    if grep -q "$sid" "$HISTORY_FILE" 2>/dev/null; then
        grep -v "$sid" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    fi
    echo "${today}	${hour}	${sid}	${dur_min}	${cost}" >> "$HISTORY_FILE"
}

# Log in background to avoid blocking
log_usage "$input" &

# ── Extract data ──
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
VERSION=$(echo "$input" | jq -r '.version // "?"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // "."')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
LINES_ADD=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_DEL=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
TOTAL_IN=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
TOTAL_OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
EXCEEDS_200K=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')

# ── Header ──
printf '%b' "${D}──${RESET} ${C}${W}CORTEX${RESET} ${D}·${RESET} ${D}by Claude${RESET} ${D}──────────────────────────────────────${RESET}\n"

# ── LOC: Location + Time + Weather ──
if section_enabled loc; then
WEATHER_CACHE="/tmp/claude-statusline-weather"
WEATHER_MAX_AGE=1800  # 30 minutes

if [ ! -f "$WEATHER_CACHE" ] || [ $(($(date +%s) - $(stat -f %m "$WEATHER_CACHE" 2>/dev/null || stat -c %Y "$WEATHER_CACHE" 2>/dev/null || echo 0))) -gt $WEATHER_MAX_AGE ]; then
    # Fetch weather silently, don't block if it fails
    WEATHER_RAW=$(curl -s --max-time 2 "wttr.in/?format=%l|%t|%C" 2>/dev/null)
    if [ -n "$WEATHER_RAW" ] && [[ "$WEATHER_RAW" != *"Unknown"* ]] && [[ "$WEATHER_RAW" != *"Sorry"* ]]; then
        echo "$WEATHER_RAW" > "$WEATHER_CACHE"
    else
        echo "Unknown|?|?" > "$WEATHER_CACHE"
    fi
fi

IFS='|' read -r W_LOC W_TEMP W_COND < "$WEATHER_CACHE"
W_LOC=$(echo "$W_LOC" | sed 's/^ *//;s/ *$//')
W_TEMP=$(echo "$W_TEMP" | sed 's/^ *//;s/ *$//')
W_COND=$(echo "$W_COND" | sed 's/^ *//;s/ *$//')
CURRENT_TIME=$(date +%H:%M)

printf '%b' "${D}LOC:${RESET} ${W}${W_LOC}${RESET} ${D}|${RESET} ${C}${CURRENT_TIME}${RESET} ${D}|${RESET} ${Y}${W_TEMP}${RESET} ${W_COND}\n"
fi

# ── ENV info ──
if section_enabled env; then
COST_FMT=$(printf '$%.2f' "$COST")

if [ "$CTX_SIZE" -ge 1000000 ]; then CTX_LABEL="1M"
elif [ "$CTX_SIZE" -ge 200000 ]; then CTX_LABEL="200K"
else CTX_LABEL="${CTX_SIZE}"; fi

# Count skills and hooks
SK_COUNT=$(find ~/.claude/skills ~/.claude/agents 2>/dev/null | wc -l | tr -d ' ')
HOOK_COUNT=$(echo "$input" | jq '[.hooks // {} | to_entries[].value[]?.hooks // [] | length] | add // 0' 2>/dev/null || echo "0")
# Fallback: count hooks from settings
if [ "$HOOK_COUNT" = "0" ] || [ "$HOOK_COUNT" = "null" ]; then
    HOOK_COUNT=$(jq '[.. | .hooks? // empty | arrays | length] | add // 0' ~/.claude/settings.json 2>/dev/null || echo "?")
fi

printf '%b' "${D}ENV:${RESET} CC:${C}${VERSION}${RESET} ${D}|${RESET} ${W}${MODEL}${RESET} ${D}(${CTX_LABEL})${RESET} ${D}|${RESET} SK: ${C}${SK_COUNT}${RESET} ${D}|${RESET} Hooks: ${C}${HOOK_COUNT}${RESET} ${D}|${RESET} ${Y}${COST_FMT}${RESET}\n"
fi

# ── CONTEXT bar ──
if section_enabled context; then
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$R"; DOT="${R}●${RESET}"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$Y"; DOT="${Y}●${RESET}"
else BAR_COLOR="$G"; DOT="${B}●${RESET}"; fi

BAR_WIDTH=40
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v FILL "%${FILLED}s" && BAR="${FILL// /━}"
[ "$EMPTY" -gt 0 ] && printf -v PAD "%${EMPTY}s" && BAR="${BAR}${PAD// /╌}"

printf '%b' "${DOT} ${D}CONTEXT:${RESET} ${BAR_COLOR}${BAR}${RESET} ${W}${PCT}%${RESET}\n"
fi

# ── PLAN usage limits ──
if section_enabled plan; then
HAS_RATE_LIMITS=$(echo "$input" | jq -r 'if .rate_limits then "true" else "false" end')
if [ "$HAS_RATE_LIMITS" = "true" ]; then
    NOW=$(date +%s)
    PLAN_BAR_WIDTH=40

    render_plan_bar() {
        local label="$1" pct="$2" resets_at="$3"
        local pct_int=${pct%.*}
        [ -z "$pct_int" ] && pct_int=0

        local color dot
        if [ "$pct_int" -ge 90 ]; then color="$R"; dot="${R}●${RESET}"
        elif [ "$pct_int" -ge 70 ]; then color="$Y"; dot="${Y}●${RESET}"
        else color="$G"; dot="${B}●${RESET}"; fi

        local filled=$((pct_int * PLAN_BAR_WIDTH / 100))
        local empty=$((PLAN_BAR_WIDTH - filled))
        local bar=""
        [ "$filled" -gt 0 ] && printf -v f "%${filled}s" && bar="${f// /━}"
        [ "$empty" -gt 0 ]  && printf -v p "%${empty}s"  && bar="${bar}${p// /╌}"

        local secs=$((resets_at - NOW))
        local reset_str
        if [ "$secs" -le 0 ]; then
            reset_str="resetting"
        elif [ "$secs" -lt 3600 ]; then
            reset_str="in $((secs / 60))m"
        elif [ "$secs" -lt 86400 ]; then
            reset_str="in $((secs / 3600))h $(((secs % 3600) / 60))m"
        else
            reset_str="in $((secs / 86400))d $(((secs % 86400) / 3600))h"
        fi

        printf '%b' "${dot} ${D}${label}:${RESET} ${color}${bar}${RESET} ${W}${pct_int}%${RESET} ${D}· resets ${reset_str}${RESET}\n"
    }

    P5_PCT=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // 0')
    P5_RESET=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
    P7_PCT=$(echo "$input"   | jq -r '.rate_limits.seven_day.used_percentage // 0')
    P7_RESET=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0')

    render_plan_bar "PLAN 5h" "$P5_PCT" "$P5_RESET"
    render_plan_bar "PLAN 7d" "$P7_PCT" "$P7_RESET"
fi
fi

# ── USAGE + Cache + Burn rate ──
if section_enabled usage; then
MINS=$((DURATION_MS / 60000))
SECS=$(((DURATION_MS % 60000) / 1000))

# Cache hit ratio
CACHE_TOTAL=$((CACHE_READ + CACHE_CREATE + INPUT_TOKENS))
if [ "$CACHE_TOTAL" -gt 0 ]; then
    CACHE_PCT=$((CACHE_READ * 100 / CACHE_TOTAL))
    if [ "$CACHE_PCT" -ge 70 ]; then CACHE_COLOR="$G"
    elif [ "$CACHE_PCT" -ge 40 ]; then CACHE_COLOR="$Y"
    else CACHE_COLOR="$R"; fi
    CACHE_STR="${CACHE_COLOR}${CACHE_PCT}%${RESET}"
else
    CACHE_STR="${D}--${RESET}"
fi

# Burn rate (cost per minute)
if [ "$MINS" -gt 0 ]; then
    # Use awk for floating point division
    BURN=$(awk "BEGIN { printf \"%.3f\", $COST / $MINS }")
    BURN_STR="\$${BURN}/m"
else
    BURN_STR="--"
fi

# Exceeds 200K warning
WARN_200K=""
if [ "$EXCEEDS_200K" = "true" ]; then
    WARN_200K=" ${R}⚠ >200K${RESET}"
fi

# Format token counts (e.g. 152340 -> 152K)
fmt_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        awk "BEGIN { printf \"%.1fM\", $n / 1000000 }"
    elif [ "$n" -ge 1000 ]; then
        awk "BEGIN { printf \"%.0fK\", $n / 1000 }"
    else
        echo "$n"
    fi
}

TIN=$(fmt_tokens "$TOTAL_IN")
TOUT=$(fmt_tokens "$TOTAL_OUT")

printf '%b' "${Y}▪${RESET} ${Y}USAGE:${RESET} ${G}+${LINES_ADD}${RESET} ${R}-${LINES_DEL}${RESET} lines ${D}|${RESET} ⏱  ${W}${MINS}m ${SECS}s${RESET} ${D}|${RESET} Tk: ${C}↓${TIN}${RESET} ${M}↑${TOUT}${RESET} ${D}|${RESET} Cache: ${CACHE_STR} ${D}|${RESET} Burn: ${Y}${BURN_STR}${RESET}${WARN_200K}\n"
fi

# ── DISK usage ──
if section_enabled disk; then
DISK_CACHE="/tmp/claude-statusline-disk"
DISK_CACHE_AGE=60  # 1 minute

disk_cache_stale() {
    [ ! -f "$DISK_CACHE" ] || \
    [ $(($(date +%s) - $(stat -f %m "$DISK_CACHE" 2>/dev/null || echo 0))) -gt $DISK_CACHE_AGE ]
}

if disk_cache_stale; then
    DISK_INFO=$(df -h / 2>/dev/null | tail -1 | awk '{print $3 "|" $4 "|" $5}')
    echo "$DISK_INFO" > "$DISK_CACHE"
fi

IFS='|' read -r DISK_USED DISK_AVAIL DISK_PCT < "$DISK_CACHE"
DISK_PCT_NUM=$(echo "$DISK_PCT" | tr -d '%')

if [ "$DISK_PCT_NUM" -ge 90 ] 2>/dev/null; then DISK_COLOR="$R"
elif [ "$DISK_PCT_NUM" -ge 75 ] 2>/dev/null; then DISK_COLOR="$Y"
else DISK_COLOR="$G"; fi

printf '%b' "${G}▫${RESET} ${G}DISK:${RESET} ${DISK_COLOR}${DISK_PCT}${RESET} used ${D}(${DISK_USED}/${DISK_AVAIL} free)${RESET}\n"
fi

# ── PWD + Git ──
if section_enabled pwd; then
DIRNAME="${DIR##*/}"

# Cache git info (5s TTL)
GIT_CACHE="/tmp/claude-statusline-git-cache"
GIT_CACHE_AGE=5

git_cache_stale() {
    [ ! -f "$GIT_CACHE" ] || \
    [ $(($(date +%s) - $(stat -f %m "$GIT_CACHE" 2>/dev/null || stat -c %Y "$GIT_CACHE" 2>/dev/null || echo 0))) -gt $GIT_CACHE_AGE ]
}

if git_cache_stale; then
    if git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
        BRANCH=$(git -C "$DIR" --no-optional-locks branch --show-current 2>/dev/null)
        MODIFIED=$(git -C "$DIR" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        # Commits ahead of remote
        AHEAD=$(git -C "$DIR" --no-optional-locks rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
        echo "$BRANCH|$MODIFIED|$AHEAD" > "$GIT_CACHE"
    else
        echo "||" > "$GIT_CACHE"
    fi
fi

IFS='|' read -r BRANCH MODIFIED AHEAD < "$GIT_CACHE"

GIT_INFO=""
if [ -n "$BRANCH" ]; then
    GIT_INFO="${D}|${RESET} Branch: ${M}${BRANCH}${RESET}"
    GIT_INFO="${GIT_INFO} ${D}|${RESET} Age: ${C}${MINS}m${RESET}"
    GIT_INFO="${GIT_INFO} ${D}|${RESET} Mod: ${Y}${MODIFIED}${RESET}"
    [ "$AHEAD" -gt 0 ] 2>/dev/null && GIT_INFO="${GIT_INFO} ${D}|${RESET} Sync: ${G}↑${AHEAD}${RESET}"
fi

printf '%b' "${C}◆${RESET} ${C}PWD:${RESET} ${W}${DIRNAME}${RESET} ${GIT_INFO}\n"
fi

# ── MEMORY ──
if section_enabled memory; then
MEM_DIR="$HOME/.claude/projects"
if [ -d "$MEM_DIR" ]; then
    # Count .md files across all project memory dirs (excluding MEMORY.md index files)
    MEM_TOTAL=$(find "$MEM_DIR" -name "*.md" ! -name "MEMORY.md" 2>/dev/null | wc -l | tr -d ' ')
    # Count by type if possible
    MEM_USER=$(find "$MEM_DIR" -name "user_*.md" 2>/dev/null | wc -l | tr -d ' ')
    MEM_FEEDBACK=$(find "$MEM_DIR" -name "feedback_*.md" 2>/dev/null | wc -l | tr -d ' ')
    MEM_PROJECT=$(find "$MEM_DIR" -name "project_*.md" 2>/dev/null | wc -l | tr -d ' ')
    MEM_REF=$(find "$MEM_DIR" -name "reference_*.md" 2>/dev/null | wc -l | tr -d ' ')

    printf '%b' "${M}◉${RESET} ${M}MEMORY:${RESET} 📂 ${W}${MEM_TOTAL}${RESET} Total ${D}|${RESET} ${C}♦${MEM_USER}${RESET} User ${D}|${RESET} ${Y}♦${MEM_FEEDBACK}${RESET} Feedback ${D}|${RESET} ${G}♦${MEM_PROJECT}${RESET} Project ${D}|${RESET} ${M}♦${MEM_REF}${RESET} Ref\n"
fi
fi

# ── ACTIVITY heatmap ──
if section_enabled activity; then
HEATMAP_CACHE="/tmp/claude-statusline-heatmap"
HEATMAP_CACHE_AGE=30  # refresh every 30 seconds

heatmap_cache_stale() {
    [ ! -f "$HEATMAP_CACHE" ] || \
    [ $(($(date +%s) - $(stat -f %m "$HEATMAP_CACHE" 2>/dev/null || echo 0))) -gt $HEATMAP_CACHE_AGE ]
}

if heatmap_cache_stale && [ -f "$HOME/.claude/usage-heatmap.py" ]; then
    python3 "$HOME/.claude/usage-heatmap.py" > "$HEATMAP_CACHE" 2>/dev/null
fi

[ -f "$HEATMAP_CACHE" ] && cat "$HEATMAP_CACHE"
fi
