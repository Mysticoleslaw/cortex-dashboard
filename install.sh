#!/bin/bash
# Cortex — Claude Code Dashboard
# Install script

set -e

CLAUDE_DIR="$HOME/.claude"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "── Installing Cortex ──"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required."
    exit 1
fi

# Copy scripts
cp "$SCRIPT_DIR/cortex.sh" "$CLAUDE_DIR/statusline-command.sh"
cp "$SCRIPT_DIR/usage-heatmap.py" "$CLAUDE_DIR/usage-heatmap.py"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/usage-heatmap.py"

# Install config (don't overwrite existing)
if [ ! -f "$CLAUDE_DIR/cortex-config.json" ]; then
    cp "$SCRIPT_DIR/cortex-config.default.json" "$CLAUDE_DIR/cortex-config.json"
    echo "Created default config at $CLAUDE_DIR/cortex-config.json"
else
    echo "Config already exists, keeping your settings"
fi

# Install /cortex slash command
mkdir -p "$CLAUDE_DIR/commands"
cp "$SCRIPT_DIR/cortex-command.md" "$CLAUDE_DIR/commands/cortex.md"

# Install CLI config tool
cp "$SCRIPT_DIR/cortex-config-tui.py" "$CLAUDE_DIR/cortex-config-tui.py"
chmod +x "$CLAUDE_DIR/cortex-config-tui.py"

# Create symlink for easy access
BIN_DIR="${CORTEX_BIN_DIR:-/usr/local/bin}"
if [ -d "$BIN_DIR" ]; then
    ln -sf "$CLAUDE_DIR/cortex-config-tui.py" "$BIN_DIR/cortex-config" 2>/dev/null || true
fi

# Update settings.json — keep any existing statusLine options (e.g. padding),
# and refresh every 30s so the clock and reset countdowns stay current when idle
STATUSLINE_CMD="/bin/bash $CLAUDE_DIR/statusline-command.sh"
[ -f "$CLAUDE_DIR/settings.json" ] || echo '{}' > "$CLAUDE_DIR/settings.json"
jq --arg cmd "$STATUSLINE_CMD" \
    '.statusLine = ((.statusLine // {}) + {"type": "command", "command": $cmd, "refreshInterval": (.statusLine.refreshInterval // 30)})' \
    "$CLAUDE_DIR/settings.json" > "$CLAUDE_DIR/settings.json.tmp" && \
    mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"

echo ""
echo "── CORTEX · by Claude ──"
echo ""
echo "Sections: LOC · ENV · CONTEXT · PLAN · USAGE · DISK · PWD · MEMORY · ACTIVITY"
echo ""
echo "Commands:"
echo "  /cortex          — show current config"
echo "  /cortex toggle X — toggle a section on/off"
echo "  /cortex minimal  — context + pwd only"
echo "  /cortex full     — enable all sections"
echo ""
echo "Start a new Claude Code session to see your dashboard."
