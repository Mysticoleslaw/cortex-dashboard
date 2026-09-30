#!/bin/bash
# Cortex test suite — renders cortex.sh against fixture payloads in a sandbox.
# Never touches your real ~/.claude or /tmp caches.
#
#   ./tests/run.sh

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export CORTEX_CACHE_DIR="$SANDBOX/cache"
CD="$HOME/.claude"
mkdir -p "$CD" "$CORTEX_CACHE_DIR"
cp "$REPO/usage-heatmap.py" "$CD/"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
has()   { grep -qF -- "$2" <<< "$1"; }
# Plain text: strip color codes and OSC 8 link wrappers
render() { bash "$REPO/cortex.sh" | sed -e $'s/\x1b\\[[0-9;]*m//g' -e $'s/\x1b]8;;[^\x07]*\x07//g'; }
render_raw() { bash "$REPO/cortex.sh"; }
settle() { sleep 0.5; }  # background loggers

# LOC (weather) and the update check hit the network — keep tests offline
write_config() {
    local extra='{}'
    [ $# -gt 0 ] && extra="$1"
    jq -n --argjson extra "$extra" \
        '{"sections": {"loc": false, "updates": false}} * $extra' > "$CD/cortex-config.json"
}

# ── Fixtures ──
mkdir -p "$CD/skills/a" "$CD/skills/b" "$CD/skills/c" "$CD/agents"
touch "$CD/skills/a/SKILL.md" "$CD/skills/b/SKILL.md" "$CD/skills/c/notes.md" "$CD/agents/x.md"
echo '{"hooks":{"PreToolUse":[{"hooks":[{},{}]}],"Stop":[{"hooks":[{}]}]}}' > "$CD/settings.json"

MEM="$CD/projects/p1/memory"; mkdir -p "$MEM"
printf -- '---\nname: a\ntype: user\n---\nbody\n' > "$MEM/who-i-am.md"
printf -- '---\nname: b\nmetadata:\n  type: feedback\n---\nbody\n' > "$MEM/small-changes.md"
printf 'no frontmatter\n' > "$MEM/project_legacy.md"
printf 'no frontmatter\n' > "$MEM/reference_links.md"
printf -- '---\ntype: research\n---\n' > "$MEM/notes.md"
printf 'index\n' > "$MEM/MEMORY.md"

REPO_FIX="$SANDBOX/repo"; mkdir -p "$REPO_FIX"
git -C "$REPO_FIX" init -q -b feature
NOGIT="$SANDBOX/plain"; mkdir -p "$NOGIT"

NOW=$(date +%s)
full_payload() {
    cat <<EOF
{"session_id":"s-full","session_name":"my session","model":{"display_name":"Opus 5.5"},"version":"2.1.283",
 "workspace":{"current_dir":"$REPO_FIX","git_worktree":"wt-1"},
 "cost":{"total_cost_usd":3.21,"total_duration_ms":1830000,"total_api_duration_ms":90000,"total_lines_added":5,"total_lines_removed":2},
 "context_window":{"total_input_tokens":155000,"total_output_tokens":1200,"context_window_size":1000000,"used_percentage":15.5},
 "prompt_cache":{"warm":true,"caching_observed":true,"expires_at":$((NOW + 2550)),"hit_ratio":0.91},
 "fast_mode":true,"effort":{"level":"xhigh"},
 "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":$((NOW + 6870))},
                "seven_day":{"used_percentage":91.2,"resets_at":$((NOW + 300000))},
                "spend_limit":{"used_percentage":112.8,"resets_at":$((NOW + 900000))}},
 "exceeds_200k_tokens":true,
 "pr":{"number":7,"url":"https://github.com/o/r/pull/7","review_state":"approved"}}
EOF
}

echo "── Rendering"
write_config
OUT=$(full_payload | render)
check "header shows session name"          'has "$OUT" "CORTEX · by Claude · my session"'
check "ENV shows effort + fast mode"       'has "$OUT" "(1M) · xhigh ⚡fast"'
check "SK counts skills with SKILL.md + agents" 'has "$OUT" "SK: 3"'
check "hooks counted from settings.json"   'has "$OUT" "Hooks: 3"'
check "PLAN 5h bar with countdown"         'has "$OUT" "PLAN 5h:" && has "$OUT" "23% · resets in 1h 54m"'
check "PLAN 7d bar"                        'has "$OUT" "PLAN 7d:" && has "$OUT" "91%"'
check "SPEND bar can exceed 100%"          'has "$OUT" "SPEND:" && has "$OUT" "112%"'
check "cache uses session-wide hit ratio + warmth" 'has "$OUT" "Cache: 91% warm 42m"'
check "PWD shows branch, worktree, PR"     'has "$OUT" "Branch: feature" && has "$OUT" "WT: wt-1" && has "$OUT" "PR: #7 ✓"'
check "MEMORY classifies by frontmatter + prefix" \
    'has "$OUT" "5 Total | ♦1 User | ♦1 Feedback | ♦1 Project | ♦1 Ref"'

OUT=$(echo '{"session_id":"s-min","workspace":{"current_dir":"'"$NOGIT"'"},"rate_limits":{"five_hour":{"used_percentage":40}}}' | render)
check "missing PLAN windows are hidden"    'has "$OUT" "PLAN 5h:" && ! has "$OUT" "PLAN 7d:" && ! has "$OUT" "SPEND:"'
check "git cache is per directory"         '! has "$OUT" "Branch:"'
check "no effort/fast when absent"         '! has "$OUT" "⚡fast"'

echo "── Usage details"
OUT=$(full_payload | render)
check "burn rate uses API time (\$3.21 / 1.5 min)" 'has "$OUT" "Burn: \$2.140/m"'
check ">200K warning hidden on 1M windows" '! has "$OUT" ">200K"'
OUT=$(echo '{"exceeds_200k_tokens":true,"context_window":{"context_window_size":200000},"workspace":{"current_dir":"'"$NOGIT"'"}}' | render)
check ">200K warning shown on 200K windows" 'has "$OUT" "⚠ >200K"'
OUT=$(echo '{"cost":{"total_cost_usd":1,"total_duration_ms":600000},"workspace":{"current_dir":"'"$NOGIT"'"}}' | render)
check "burn rate falls back to wall-clock"  'has "$OUT" "Burn: \$0.100/m"'
RAW=$(full_payload | render_raw)
check "cache countdown dim when >5 min left" 'has "$RAW" $'"'"'\033[90mwarm 42m'"'"
RAW=$(echo '{"prompt_cache":{"warm":true,"caching_observed":true,"expires_at":'$((NOW + 150))',"hit_ratio":0.9},"workspace":{"current_dir":"'"$NOGIT"'"}}' | render_raw)
check "cache countdown yellow in last 5 min" 'has "$RAW" $'"'"'\033[33mwarm 2m'"'"

echo "── PR link"
RAW=$(full_payload | render_raw)
check "PR badge is an OSC 8 link"          'has "$RAW" $'"'"'\033]8;;https://github.com/o/r/pull/7\a#7'"'"
EVIL=$(jq -n --arg d "$REPO_FIX" '{"workspace":{"current_dir":$d},"pr":{"number":9,"url":"https://x.test/\u001b[31mEVIL\u0007"}}')
RAW=$(echo "$EVIL" | render_raw)
check "control chars stripped from PR URL" '! has "$RAW" $'"'"'\033[31mEVIL'"'"' && has "$RAW" "#9"'
RAW=$(echo '{"workspace":{"current_dir":"'"$REPO_FIX"'"},"pr":{"number":5,"url":"javascript:alert(1)"}}' | render_raw)
check "non-https PR URL isn't linked"      '! has "$RAW" "javascript:" && has "$RAW" "#5"'

OUT=$(echo '{}' | bash "$REPO/cortex.sh" > /dev/null 2>&1; echo "exit=$?")
check "empty payload renders without error" 'has "$OUT" "exit=0"'

echo "── Config"
write_config '{"sections":{"disk":false},"plan":{"7d":false}}'
OUT=$(full_payload | render)
check "disabled section is hidden"         '! has "$OUT" "DISK:"'
check "disabled plan bar is hidden"        '! has "$OUT" "PLAN 7d:" && has "$OUT" "PLAN 5h:"'
write_config

echo "── Usage history"
H="$CD/usage-history.tsv"
printf '# header\n2026-01-01\t10\told-1\t30.0\t1\n2026-01-02\t11\told-2\t45.0\t2\n' > "$H"
for i in $(seq 1 30); do
    echo "{\"session_id\":\"race-$i\",\"cost\":{\"total_duration_ms\":60000},\"workspace\":{\"current_dir\":\"$NOGIT\"}}" \
        | bash "$REPO/cortex.sh" > /dev/null &
done
wait; settle
check "30 concurrent renders keep existing rows" 'grep -q old-1 "$H" && grep -q old-2 "$H" && grep -q "^# header" "$H"'
check "no leftover lock or temp files"     '[ ! -d "$H.lock" ] && [ -z "$(ls "$CD" | grep "usage-history.tsv\.")" ]'
check "no duplicate session rows"          '[ -z "$(cut -f3 "$H" | sort | uniq -d)" ]'

echo "── Active minutes"
A="$CD/activity-minutes.log"; rm -f "$A"
act() { echo "{\"session_id\":\"$1\",\"cost\":{\"total_cost_usd\":$2,\"total_api_duration_ms\":$3},\"workspace\":{\"current_dir\":\"$NOGIT\"}}" | bash "$REPO/cortex.sh" > /dev/null; settle; }
act a1 0 0
check "fresh idle session logs nothing"    '[ ! -s "$A" ]'
act a1 0.5 1000
check "session doing work logs a minute"   '[ "$(wc -l < "$A" | tr -d " ")" = 1 ]'
act a1 0.5 1000
check "unchanged session (refresh tick) logs nothing" '[ "$(wc -l < "$A" | tr -d " ")" = 1 ]'
act a2 1.0 500
check "parallel sessions don't stack"      '[ -z "$(sort "$A" | uniq -d)" ]'

echo "── Heatmap"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(python3 -c 'import datetime;print(datetime.date.today()-datetime.timedelta(days=1))')
printf '%s 10:00\n%s 10:03\n%s 10:30\n' "$TODAY" "$TODAY" "$TODAY" > "$A"
printf '%s\t09\tlegacy\t2000.0\t1\n' "$YESTERDAY" > "$H"
RESULT=$(python3 - "$CD/usage-heatmap.py" <<'EOF'
import importlib.util, sys, datetime
spec = importlib.util.spec_from_file_location("hm", sys.argv[1])
hm = importlib.util.module_from_spec(spec); spec.loader.exec_module(hm)
daily, hourly = hm.load_usage()
today = datetime.date.today()
y = str(today - datetime.timedelta(days=1))
print(int(daily[str(today)]), int(hourly[(str(today), 10)]), int(daily[y]), int(hourly[(y, 9)]))
EOF
)
read -r T_DAY T_HOUR Y_DAY Y_HOUR <<< "$RESULT"
check "gaps ≤5 min are filled, longer gaps aren't (5 active min)" '[ "$T_DAY" = 5 ] && [ "$T_HOUR" = 5 ]'
check "legacy days capped at 24h/day, 60m/hour" '[ "$Y_DAY" = 1440 ] && [ "$Y_HOUR" = 60 ]'
check "heatmap renders"                    'python3 "$CD/usage-heatmap.py" | grep -q ACTIVITY'

echo "── Update notice"
write_config '{"sections":{"updates":true}}'
echo v1.3.0 > "$CD/cortex-version"
UC="$CORTEX_CACHE_DIR/claude-statusline-update"
echo v1.4.0 > "$UC"; OUT=$(echo '{}' | render)
check "banner when a newer release exists"  'has "$OUT" "⬆ v1.4.0 available · cortex update"'
echo v1.3.0 > "$UC"; OUT=$(echo '{}' | render)
check "no banner when up to date"           '! has "$OUT" "available"'
echo v1.2.0 > "$UC"; OUT=$(echo '{}' | render)
check "no banner when installed is newer"   '! has "$OUT" "available"'
printf '\033[31mEVIL\n' > "$UC"; RAW=$(echo '{}' | render_raw)
check "junk in update cache is ignored"     '! has "$RAW" "EVIL"'
echo v1.4.0 > "$UC"; write_config; OUT=$(echo '{}' | render)
check "updates toggle turns the notice off" '! has "$OUT" "available"'
rm -f "$UC" "$CD/cortex-version"

echo "── Install, update, rollback"
# Local stand-in for GitHub: the working tree committed on Main, released twice
FX="$SANDBOX/remote"; mkdir -p "$FX"
tar -C "$REPO" --exclude .git -cf - . | tar -C "$FX" -xf -
fxgit() { git -C "$FX" -c user.name=test -c user.email=test@test "$@"; }
fxgit init -q -b Main
echo v1.2.9 > "$FX/VERSION"; fxgit add -A; fxgit commit -qm old; fxgit tag v1.2.9
echo v1.3.0 > "$FX/VERSION"; fxgit commit -qam new; fxgit tag v1.3.0
H2="$SANDBOX/home2"; BIN="$SANDBOX/bin/not-yet"; mkdir -p "$H2/.claude"
echo '{"statusLine":{"padding":2}}' > "$H2/.claude/settings.json"
export_h2() { HOME="$H2" CORTEX_REPO_URL="$FX" CORTEX_BIN_DIR="$BIN" "$@"; }
get() { export_h2 bash "$REPO/get.sh" > /dev/null 2>&1; }
cli() { export_h2 bash "$H2/.claude/cortex-cli.sh" "$@" 2>&1; }
installed() { cat "$H2/.claude/cortex-version"; }
src_version() { cat "$H2/.cortex-dashboard/VERSION"; }

get; FIRST=$?
check "get.sh installs the latest release"  '[ "$FIRST" = 0 ] && [ "$(installed)" = v1.3.0 ] && [ "$(src_version)" = v1.3.0 ]'
check "dashboard script installed"          'cmp -s "$H2/.cortex-dashboard/cortex.sh" "$H2/.claude/statusline-command.sh"'
check "settings get command + refreshInterval, keep padding" \
    '[ "$(jq -c ".statusLine | [.refreshInterval, .padding]" "$H2/.claude/settings.json")" = "[30,2]" ]'
check "cortex + cortex-config shortcuts in CORTEX_BIN_DIR" '[ -L "$BIN/cortex" ] && [ -L "$BIN/cortex-config" ]'

OUT=$(cli versions)
check "cortex versions lists releases, marks installed" 'has "$OUT" "* v1.3.0 (installed)" && has "$OUT" "  v1.2.9"'
OUT=$(cli update)
check "cortex update when current is a no-op" 'has "$OUT" "up to date"'
OUT=$(cli rollback)
check "cortex rollback goes to previous release" '[ "$(installed)" = v1.2.9 ] && [ "$(src_version)" = v1.2.9 ]'
OUT=$(cli rollback); RC=$?
check "rollback past the oldest release fails cleanly" '[ "$RC" != 0 ] && has "$OUT" "no release older" && [ "$(installed)" = v1.2.9 ]'
OUT=$(cli version)
check "cortex version reports an update"    'has "$OUT" "Installed: v1.2.9" && has "$OUT" "v1.3.0 — run '"'"'cortex update'"'"'"'
OUT=$(cli update)
check "cortex update installs the latest"   '[ "$(installed)" = v1.3.0 ] && [ "$(src_version)" = v1.3.0 ]'
echo v1.9.0 > "$H2/.claude/cortex-version"; OUT=$(cli update)
check "cortex update never downgrades"      'has "$OUT" "newer than the latest release" && [ "$(installed)" = v1.9.0 ]'
OUT=$(cli use 1.2.9)
check "cortex use <version> (v optional)"   '[ "$(installed)" = v1.2.9 ]'
OUT=$(cli use v9.9.9); RC=$?
check "cortex use unknown version fails, changes nothing" '[ "$RC" != 0 ] && has "$OUT" "no release named v9.9.9" && [ "$(installed)" = v1.2.9 ]'
UPD=$(export_h2 env CORTEX_REF=Main bash "$REPO/get.sh" > /dev/null 2>&1; echo $?)
check "get.sh CORTEX_REF installs a branch" '[ "$UPD" = 0 ] && [ "$(installed)" = Main ]'

export_h2 bash "$REPO/uninstall.sh" > /dev/null 2>&1
check "uninstall removes scripts, setting, shortcuts" \
    '[ ! -f "$H2/.claude/statusline-command.sh" ] && [ ! -f "$H2/.claude/cortex-cli.sh" ] && [ "$(jq .statusLine "$H2/.claude/settings.json")" = null ] && [ ! -e "$BIN/cortex" ] && [ ! -e "$BIN/cortex-config" ]'
check "uninstall keeps config"              '[ -f "$H2/.claude/cortex-config.json" ]'

echo
if [ "$FAIL" -eq 0 ]; then printf '\033[32m%d passed\033[0m\n' "$PASS"; exit 0
else printf '\033[31m%d failed\033[0m, %d passed\n' "$FAIL" "$PASS"; exit 1; fi
