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
if [ -d "/usr/local/bin" ]; then
    ln -sf "$CLAUDE_DIR/cortex-config-tui.py" /usr/local/bin/cortex-config 2>/dev/null || true
fi

# Update settings.json
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    # Check if statusLine already exists
    if jq -e '.statusLine' "$CLAUDE_DIR/settings.json" > /dev/null 2>&1; then
        # Update existing
        jq '.statusLine = {"type": "command", "command": "/bin/bash '"$CLAUDE_DIR"'/statusline-command.sh"}' \
            "$CLAUDE_DIR/settings.json" > "$CLAUDE_DIR/settings.json.tmp" && \
            mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
    else
        # Add new
        jq '. + {"statusLine": {"type": "command", "command": "/bin/bash '"$CLAUDE_DIR"'/statusline-command.sh"}}' \
            "$CLAUDE_DIR/settings.json" > "$CLAUDE_DIR/settings.json.tmp" && \
            mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
    fi
else
    # Create minimal settings
    cat > "$CLAUDE_DIR/settings.json" << EOF
{
    "statusLine": {
        "type": "command",
        "command": "/bin/bash $CLAUDE_DIR/statusline-command.sh"
    }
}
EOF
fi

echo ""
echo "── CORTEX · by Claude ──"
echo ""
echo "Sections: LOC · ENV · CONTEXT · USAGE · DISK · PWD · MEMORY · ACTIVITY"
echo ""
echo "Commands:"
echo "  /cortex          — show current config"
echo "  /cortex toggle X — toggle a section on/off"
echo "  /cortex minimal  — context + pwd only"
echo "  /cortex full     — enable all sections"
echo ""
echo "Start a new Claude Code session to see your dashboard."
