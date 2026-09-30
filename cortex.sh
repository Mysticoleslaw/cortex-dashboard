#!/bin/bash
# Cortex — Claude Code Dashboard
# https://github.com/Mysticoleslaw/cortex-dashboard

input=$(cat)
NOW=$(date +%s)
CACHE_DIR="${CORTEX_CACHE_DIR:-/tmp}"

# ── Config ──
# Read once: space-separated list of disabled keys, e.g. " disk plan.7d "
# (anything missing from the config counts as enabled)
CORTEX_CONFIG="$HOME/.claude/cortex-config.json"
DISABLED=" $(jq -r '[
    (.sections // {} | to_entries[] | select(.value == false) | .key),
    (.plan // {} | to_entries[] | select(.value == false) | "plan." + .key)
] | join(" ")' "$CORTEX_CONFIG" 2>/dev/null) "
section_enabled()    { [[ "$DISABLED" != *" $1 "* ]]; }
subsection_enabled() { [[ "$DISABLED" != *" $1.$2 "* ]]; }

# ── Cache helpers ──
# File modification time (BSD stat on macOS, GNU stat on Linux)
if [ "$(uname)" = "Darwin" ]; then
    file_mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }
else
    file_mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }
fi
cache_stale() {
    local file="$1" max_age="$2"
    [ ! -e "$file" ] || [ $((NOW - $(file_mtime "$file"))) -gt "$max_age" ]
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

# ── Extract data (single jq pass) ──
eval "$(echo "$input" | jq -r '
    def sh(v): (v // "" | tostring | @sh);
    "MODEL=\(sh(.model.display_name // "?"))",
    "VERSION=\(sh(.version // "?"))",
    "DIR=\(sh(.workspace.current_dir // .cwd // "."))",
    "SESSION_ID=\(sh(.session_id))",
    "SESSION_NAME=\(sh(.session_name))",
    "COST=\(sh(.cost.total_cost_usd // 0))",
    "DURATION_MS=\(sh(.cost.total_duration_ms // 0 | floor))",
    "API_MS=\(sh(.cost.total_api_duration_ms // 0 | floor))",
    "LINES_ADD=\(sh(.cost.total_lines_added // 0))",
    "LINES_DEL=\(sh(.cost.total_lines_removed // 0))",
    "PCT=\(sh(.context_window.used_percentage // 0 | floor))",
    "CTX_SIZE=\(sh(.context_window.context_window_size // 200000))",
    "CACHE_READ=\(sh(.context_window.current_usage.cache_read_input_tokens // 0))",
    "CACHE_CREATE=\(sh(.context_window.current_usage.cache_creation_input_tokens // 0))",
    "INPUT_TOKENS=\(sh(.context_window.current_usage.input_tokens // 0))",
    "TOTAL_IN=\(sh(.context_window.total_input_tokens // 0))",
    "TOTAL_OUT=\(sh(.context_window.total_output_tokens // 0))",
    "EXCEEDS_200K=\(sh(.exceeds_200k_tokens // false))",
    "EFFORT=\(sh(.effort.level))",
    "FAST_MODE=\(sh(.fast_mode // false))",
    "PC_HIT=\(sh(if .prompt_cache.hit_ratio != null then (.prompt_cache.hit_ratio * 100 | floor) else null end))",
    "PC_OBSERVED=\(sh(.prompt_cache.caching_observed // false))",
    "PC_WARM=\(sh(.prompt_cache.warm // false))",
    "PC_EXPIRES=\(sh(.prompt_cache.expires_at))",
    "P5_PCT=\(sh(.rate_limits.five_hour.used_percentage))",
    "P5_RESET=\(sh(.rate_limits.five_hour.resets_at))",
    "P7_PCT=\(sh(.rate_limits.seven_day.used_percentage))",
    "P7_RESET=\(sh(.rate_limits.seven_day.resets_at))",
    "PS_PCT=\(sh(.rate_limits.spend_limit.used_percentage))",
    "PS_RESET=\(sh(.rate_limits.spend_limit.resets_at))",
    "PR_NUM=\(sh(.pr.number))",
    "PR_URL=\(sh(.pr.url))",
    "PR_STATE=\(sh(.pr.review_state))",
    "PR_KIND=\(sh(.pr.kind))",
    "WORKTREE=\(sh(.worktree.name // .workspace.git_worktree))"
' 2>/dev/null)"

# ── Usage history logging ──
HISTORY_FILE="$HOME/.claude/usage-history.tsv"
HISTORY_LOCK="${HISTORY_FILE}.lock"
log_usage() {
    local sid="$1" dur_ms="$2" cost="$3"
    [ -n "$sid" ] || return 0
    local dur_min=$(awk "BEGIN { printf \"%.1f\", $dur_ms / 60000 }")

    # Concurrent renders (multiple sessions, refresh timer) must not clobber each
    # other: take a lock, skip this tick if busy, and recover from a stale lock.
    if ! mkdir "$HISTORY_LOCK" 2>/dev/null; then
        cache_stale "$HISTORY_LOCK" 10 || return 0
        rmdir "$HISTORY_LOCK" 2>/dev/null
        mkdir "$HISTORY_LOCK" 2>/dev/null || return 0
    fi

    local tmp
    if tmp=$(mktemp "${HISTORY_FILE}.XXXXXX"); then
        {
            if [ -f "$HISTORY_FILE" ]; then
                awk -F'\t' -v sid="$sid" '$3 != sid' "$HISTORY_FILE"
            else
                printf '# date\thour\tsession_id\tduration_min\tcost\n'
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%d)" "$(date +%H)" "$sid" "$dur_min" "$cost"
        } > "$tmp" && mv "$tmp" "$HISTORY_FILE"
        rm -f "$tmp"
    fi
    rmdir "$HISTORY_LOCK" 2>/dev/null
}

# ── Active-minute logging (drives the activity heatmap) ──
# A minute counts as active when any session did work in it (cost or API time
# moved since that session's last render). Idle sessions and refresh ticks don't
# count, and parallel sessions share one timeline instead of stacking.
ACTIVITY_LOG="$HOME/.claude/activity-minutes.log"
log_activity() {
    local sid="${1//[^A-Za-z0-9-]/}" cost="$2" api_ms="$3"
    [ -n "$sid" ] || return 0
    local state="$CACHE_DIR/claude-statusline-sess-$sid" sig="$cost|$api_ms" last=""
    [ -f "$state" ] && last=$(cat "$state")
    [ "$sig" = "$last" ] && return 0
    echo "$sig" > "$state"
    # First sight of a session that hasn't called the API yet isn't activity
    [ -z "$last" ] && [ "$api_ms" = "0" ] && return 0
    local minute=$(date '+%Y-%m-%d %H:%M')
    [ "$(tail -n 1 "$ACTIVITY_LOG" 2>/dev/null)" = "$minute" ] || echo "$minute" >> "$ACTIVITY_LOG"
}

# Log in background to avoid blocking
log_usage "$SESSION_ID" "$DURATION_MS" "$COST" &
log_activity "$SESSION_ID" "$COST" "$API_MS" &

# ── Formatting helpers ──
# Seconds → "42m", "1h 54m", "3d 4h"
fmt_countdown() {
    local secs="$1"
    if [ "$secs" -le 0 ]; then echo "now"
    elif [ "$secs" -lt 3600 ]; then echo "$((secs / 60))m"
    elif [ "$secs" -lt 86400 ]; then echo "$((secs / 3600))h $(((secs % 3600) / 60))m"
    else echo "$((secs / 86400))d $(((secs % 86400) / 3600))h"; fi
}

# Percentage → progress bar of a given width (clamped to 0-100%)
render_bar() {
    local pct="$1" width="$2"
    [ "$pct" -gt 100 ] && pct=100
    [ "$pct" -lt 0 ] && pct=0
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar="" f p
    [ "$filled" -gt 0 ] && printf -v f "%${filled}s" && bar="${f// /━}"
    [ "$empty" -gt 0 ]  && printf -v p "%${empty}s"  && bar="${bar}${p// /╌}"
    printf '%s' "$bar"
}

# Percentage → "<bar color>|<dot>" using the shared 70/90 thresholds
pct_colors() {
    if [ "$1" -ge 90 ]; then printf '%s|%s' "$R" "${R}●${RESET}"
    elif [ "$1" -ge 70 ]; then printf '%s|%s' "$Y" "${Y}●${RESET}"
    else printf '%s|%s' "$G" "${B}●${RESET}"; fi
}

# ── Header ──
HEADER_NAME=""
[ -n "$SESSION_NAME" ] && HEADER_NAME=" ${D}·${RESET} ${C}${SESSION_NAME}${RESET}"

# Update notice: ask GitHub for the latest release at most once a day, in the
# background (never blocks a render), and flag it when it's newer than installed
UPDATE_STR=""
if section_enabled updates; then
    UPDATE_CACHE="$CACHE_DIR/claude-statusline-update"
    RELEASES_API="https://api.github.com/repos/Mysticoleslaw/cortex-dashboard/releases/latest"
    if cache_stale "$UPDATE_CACHE" 86400; then
        : > "$UPDATE_CACHE"  # claim today's check so parallel renders don't all fetch
        (
            latest=$(curl -fsS --max-time 3 "$RELEASES_API" | jq -r '.tag_name // empty')
            [[ "$latest" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$latest" > "$UPDATE_CACHE"
        ) > /dev/null 2>&1 &
    fi
    INSTALLED=$(cat "$HOME/.claude/cortex-version" 2>/dev/null)
    LATEST=$(cat "$UPDATE_CACHE" 2>/dev/null)
    if [[ "$INSTALLED" =~ ^v[0-9] && "$LATEST" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && "$LATEST" != "$INSTALLED" ]] \
        && [ "$(printf '%s\n%s\n' "$INSTALLED" "$LATEST" | sort -V | tail -n 1)" = "$LATEST" ]; then
        UPDATE_STR=" ${Y}⬆ ${LATEST} available · cortex update${RESET}"
    fi
fi

printf '%b' "${D}──${RESET} ${C}${W}CORTEX${RESET} ${D}·${RESET} ${D}by Claude${RESET}${HEADER_NAME} ${D}──────────────────────────────────────${RESET}${UPDATE_STR}\n"

# ── LOC: Location + Time + Weather ──
if section_enabled loc; then
WEATHER_CACHE="$CACHE_DIR/claude-statusline-weather"
WEATHER_MAX_AGE=1800  # 30 minutes

if cache_stale "$WEATHER_CACHE" "$WEATHER_MAX_AGE"; then
    # Fetch weather silently, don't block if it fails
    WEATHER_RAW=$(curl -s --max-time 2 "https://wttr.in/?format=%l|%t|%C" 2>/dev/null)
    if [ -n "$WEATHER_RAW" ] && [[ "$WEATHER_RAW" != *"Unknown"* ]] && [[ "$WEATHER_RAW" != *"Sorry"* ]] && [[ "$WEATHER_RAW" != *"<"* ]]; then
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

# Model modifiers: reasoning effort + fast mode
MODEL_EXTRA=""
[ -n "$EFFORT" ] && MODEL_EXTRA=" ${D}·${RESET} ${C}${EFFORT}${RESET}"
[ "$FAST_MODE" = "true" ] && MODEL_EXTRA="${MODEL_EXTRA} ${Y}⚡fast${RESET}"

# Count installed skills (dirs with SKILL.md) and agents (*.md)
shopt -s nullglob
SK_FILES=(~/.claude/skills/*/SKILL.md ~/.claude/agents/*.md)
shopt -u nullglob
SK_COUNT=${#SK_FILES[@]}
HOOK_COUNT=$(jq '[.hooks // {} | .[][]?.hooks // [] | length] | add // 0' ~/.claude/settings.json 2>/dev/null || echo "?")

printf '%b' "${D}ENV:${RESET} CC:${C}${VERSION}${RESET} ${D}|${RESET} ${W}${MODEL}${RESET} ${D}(${CTX_LABEL})${RESET}${MODEL_EXTRA} ${D}|${RESET} SK: ${C}${SK_COUNT}${RESET} ${D}|${RESET} Hooks: ${C}${HOOK_COUNT}${RESET} ${D}|${RESET} ${Y}${COST_FMT}${RESET}\n"
fi

# ── CONTEXT bar ──
if section_enabled context; then
IFS='|' read -r BAR_COLOR DOT <<< "$(pct_colors "$PCT")"
printf '%b' "${DOT} ${D}CONTEXT:${RESET} ${BAR_COLOR}$(render_bar "$PCT" 40)${RESET} ${W}${PCT}%${RESET}\n"
fi

# ── PLAN usage limits ──
if section_enabled plan; then
render_plan_bar() {
    local label="$1" pct="$2" resets_at="$3"
    # Window absent from the JSON (free tier, cold start, no gateway) → skip
    [ -n "$pct" ] || return 0
    local pct_int=${pct%.*}
    [ -z "$pct_int" ] && pct_int=0

    local color dot
    IFS='|' read -r color dot <<< "$(pct_colors "$pct_int")"

    local reset_str=""
    if [ -n "$resets_at" ]; then
        local secs=$((resets_at - NOW))
        if [ "$secs" -le 0 ]; then reset_str=" ${D}· resetting${RESET}"
        else reset_str=" ${D}· resets in $(fmt_countdown "$secs")${RESET}"; fi
    fi

    printf '%b' "${dot} ${D}${label}:${RESET} ${color}$(render_bar "$pct_int" 40)${RESET} ${W}${pct_int}%${RESET}${reset_str}\n"
}

subsection_enabled plan 5h    && render_plan_bar "PLAN 5h" "$P5_PCT" "$P5_RESET"
subsection_enabled plan 7d    && render_plan_bar "PLAN 7d" "$P7_PCT" "$P7_RESET"
subsection_enabled plan spend && render_plan_bar "SPEND"   "$PS_PCT" "$PS_RESET"
fi

# ── USAGE + Cache + Burn rate ──
MINS=$((DURATION_MS / 60000))
if section_enabled usage; then
SECS=$(((DURATION_MS % 60000) / 1000))

# Cache hit ratio: session-wide from prompt_cache, else last API call
CACHE_PCT="$PC_HIT"
if [ -z "$CACHE_PCT" ]; then
    CACHE_TOTAL=$((CACHE_READ + CACHE_CREATE + INPUT_TOKENS))
    [ "$CACHE_TOTAL" -gt 0 ] && CACHE_PCT=$((CACHE_READ * 100 / CACHE_TOTAL))
fi
if [ -n "$CACHE_PCT" ]; then
    if [ "$CACHE_PCT" -ge 70 ]; then CACHE_COLOR="$G"
    elif [ "$CACHE_PCT" -ge 40 ]; then CACHE_COLOR="$Y"
    else CACHE_COLOR="$R"; fi
    CACHE_STR="${CACHE_COLOR}${CACHE_PCT}%${RESET}"
else
    CACHE_STR="${D}--${RESET}"
fi

# Cache warmth: time left before the cached prefix expires (yellow in the
# last 5 minutes — send the next prompt before the cache goes cold)
CACHE_EXPIRY_WARN=300
if [ "$PC_WARM" = "true" ] && [ -n "$PC_EXPIRES" ] && [ "$PC_EXPIRES" -gt "$NOW" ]; then
    CACHE_LEFT=$((PC_EXPIRES - NOW))
    WARM_COLOR="$D"; [ "$CACHE_LEFT" -le "$CACHE_EXPIRY_WARN" ] && WARM_COLOR="$Y"
    CACHE_STR="${CACHE_STR} ${WARM_COLOR}warm $(fmt_countdown "$CACHE_LEFT")${RESET}"
elif [ "$PC_OBSERVED" = "true" ]; then
    CACHE_STR="${CACHE_STR} ${R}cold${RESET}"
fi

# Burn rate: cost per minute Claude spent working (API time), so it doesn't
# drift down while the session sits idle; wall-clock if API time is missing
BURN_MINS=$(awk "BEGIN { m = $API_MS / 60000; if (m <= 0) m = $DURATION_MS / 60000; printf \"%.4f\", m }")
if awk "BEGIN { exit !($BURN_MINS >= 1) }"; then
    BURN=$(awk "BEGIN { printf \"%.3f\", $COST / $BURN_MINS }")
    BURN_STR="\$${BURN}/m"
else
    BURN_STR="--"
fi

# Exceeds 200K warning — only meaningful when the window itself is 200K
WARN_200K=""
[ "$EXCEEDS_200K" = "true" ] && [ "$CTX_SIZE" -le 200000 ] && WARN_200K=" ${R}⚠ >200K${RESET}"

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
DISK_CACHE="$CACHE_DIR/claude-statusline-disk"
DISK_CACHE_AGE=60  # 1 minute

if cache_stale "$DISK_CACHE" "$DISK_CACHE_AGE"; then
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

# Cache git info per directory (5s TTL) so parallel sessions don't share state
GIT_CACHE="$CACHE_DIR/claude-statusline-git-$(printf '%s' "$DIR" | cksum | cut -d' ' -f1)"
GIT_CACHE_AGE=5

if cache_stale "$GIT_CACHE" "$GIT_CACHE_AGE"; then
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
[ -n "$WORKTREE" ] && GIT_INFO="${GIT_INFO} ${D}|${RESET} WT: ${C}${WORKTREE}${RESET}"

# Open PR / MR for this branch, colored by review state
if [ -n "$PR_NUM" ]; then
    case "$PR_STATE" in
        approved)          PR_COLOR="$G"; PR_ICON="✓" ;;
        changes_requested) PR_COLOR="$R"; PR_ICON="✗" ;;
        draft)             PR_COLOR="$D"; PR_ICON="◌" ;;
        *)                 PR_COLOR="$Y"; PR_ICON="…" ;;
    esac
    PR_LABEL="PR"; [ "$PR_KIND" = "mr" ] && PR_LABEL="MR"
    PR_TEXT="#${PR_NUM} ${PR_ICON}"
    # Clickable via OSC 8 (Cmd/Ctrl+click) in terminals that support it;
    # strip control characters so the URL can't inject escape sequences
    PR_URL="${PR_URL//[[:cntrl:]\\]/}"
    [[ "$PR_URL" == https://* ]] && PR_TEXT="\033]8;;${PR_URL}\a${PR_TEXT}\033]8;;\a"
    GIT_INFO="${GIT_INFO} ${D}|${RESET} ${PR_LABEL}: ${PR_COLOR}${PR_TEXT}${RESET}"
fi

printf '%b' "${C}◆${RESET} ${C}PWD:${RESET} ${W}${DIRNAME}${RESET} ${GIT_INFO}\n"
fi

# ── MEMORY ──
if section_enabled memory; then
MEM_DIR="$HOME/.claude/projects"
if [ -d "$MEM_DIR" ]; then
    # Classify each memory file by its frontmatter `type:` (top-level or under
    # `metadata:`), falling back to the legacy `<type>_*.md` filename prefix.
    MEM_TYPES=$(find -H "$MEM_DIR" -path '*/memory/*.md' ! -name 'MEMORY.md' -print0 2>/dev/null | xargs -0 awk '
        function flush() { if (file != "") { if (t == "") { t = file; sub(/.*\//, "", t); sub(/_.*/, "", t) } print t } }
        FNR == 1 { flush(); file = FILENAME; t = ""; fm = 0 }
        /^---[[:space:]]*$/ { fm++; next }
        fm == 1 && t == "" && /^[[:space:]]*type:/ { t = $0; sub(/^[[:space:]]*type:[[:space:]]*/, "", t); sub(/[[:space:]]*$/, "", t) }
        END { flush() }
    ' 2>/dev/null)
    count_type() { printf '%s\n' "$MEM_TYPES" | grep -cx "$1"; }
    MEM_TOTAL=$(printf '%s' "$MEM_TYPES" | grep -c .)
    MEM_USER=$(count_type user)
    MEM_FEEDBACK=$(count_type feedback)
    MEM_PROJECT=$(count_type project)
    MEM_REF=$(count_type reference)

    printf '%b' "${M}◉${RESET} ${M}MEMORY:${RESET} 📂 ${W}${MEM_TOTAL}${RESET} Total ${D}|${RESET} ${C}♦${MEM_USER}${RESET} User ${D}|${RESET} ${Y}♦${MEM_FEEDBACK}${RESET} Feedback ${D}|${RESET} ${G}♦${MEM_PROJECT}${RESET} Project ${D}|${RESET} ${M}♦${MEM_REF}${RESET} Ref\n"
fi
fi

# ── ACTIVITY heatmap ──
if section_enabled activity; then
HEATMAP_CACHE="$CACHE_DIR/claude-statusline-heatmap"
HEATMAP_CACHE_AGE=30  # refresh every 30 seconds

if cache_stale "$HEATMAP_CACHE" "$HEATMAP_CACHE_AGE" && [ -f "$HOME/.claude/usage-heatmap.py" ]; then
    python3 "$HOME/.claude/usage-heatmap.py" > "${HEATMAP_CACHE}.$$" 2>/dev/null && mv "${HEATMAP_CACHE}.$$" "$HEATMAP_CACHE"
    rm -f "${HEATMAP_CACHE}.$$"
fi

[ -f "$HEATMAP_CACHE" ] && cat "$HEATMAP_CACHE"
fi
