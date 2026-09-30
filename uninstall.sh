#!/bin/bash
# Cortex — Claude Code Dashboard
# Uninstall script

CLAUDE_DIR="$HOME/.claude"

echo "── Uninstalling Cortex ──"

# Remove scripts, config TUI, and /cortex command
rm -f "$CLAUDE_DIR/statusline-command.sh"
rm -f "$CLAUDE_DIR/usage-heatmap.py"
rm -f "$CLAUDE_DIR/cortex-config-tui.py"
rm -f "$CLAUDE_DIR/commands/cortex.md"

# Remove the cortex-config shortcut, but only if it points at Cortex
BIN_DIR="${CORTEX_BIN_DIR:-/usr/local/bin}"
if [ "$(readlink "$BIN_DIR/cortex-config" 2>/dev/null)" = "$CLAUDE_DIR/cortex-config-tui.py" ]; then
    rm -f "$BIN_DIR/cortex-config"
fi

# Remove statusLine (command + refreshInterval) from settings
if [ -f "$CLAUDE_DIR/settings.json" ] && command -v jq &> /dev/null; then
    jq 'del(.statusLine)' "$CLAUDE_DIR/settings.json" > "$CLAUDE_DIR/settings.json.tmp" && \
        mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
fi

# Clean up caches (weather, disk, per-directory git, heatmap, per-session state)
rm -rf "${CORTEX_CACHE_DIR:-/tmp}"/claude-statusline-*
rm -rf "$CLAUDE_DIR/usage-history.tsv.lock"

echo "Cortex uninstalled. Kept your data:"
echo "  $CLAUDE_DIR/cortex-config.json"
echo "  $CLAUDE_DIR/usage-history.tsv"
echo "  $CLAUDE_DIR/activity-minutes.log"
