#!/bin/bash
# Cortex — Claude Code Dashboard
# Uninstall script

CLAUDE_DIR="$HOME/.claude"

echo "── Uninstalling Cortex ──"

# Remove scripts
rm -f "$CLAUDE_DIR/statusline-command.sh"
rm -f "$CLAUDE_DIR/usage-heatmap.py"

# Remove statusLine from settings
if [ -f "$CLAUDE_DIR/settings.json" ] && command -v jq &> /dev/null; then
    jq 'del(.statusLine)' "$CLAUDE_DIR/settings.json" > "$CLAUDE_DIR/settings.json.tmp" && \
        mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
fi

# Clean up caches
rm -f /tmp/claude-statusline-weather
rm -f /tmp/claude-statusline-disk
rm -f /tmp/claude-statusline-git-cache
rm -f /tmp/claude-statusline-heatmap

echo "Cortex uninstalled. Usage history preserved at $CLAUDE_DIR/usage-history.tsv"
