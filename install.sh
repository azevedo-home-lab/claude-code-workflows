#!/bin/bash
# Install Claude Code Workflow Manager into the current project
# Usage: curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/install.sh | bash
#    or: git clone ... && cd claude-code-workflows && ./install.sh /path/to/your/project

set -euo pipefail

# Determine target project directory
if [ -n "${1:-}" ]; then
    TARGET="$1"
else
    TARGET="$(pwd)"
fi

# Determine source directory (where the hook files live)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If running via curl pipe, we need to clone the repo to a temp dir
if [ ! -f "$SCRIPT_DIR/.claude/hooks/workflow-gate.sh" ]; then
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    echo "Downloading Workflow Manager..."
    git clone --depth 1 --quiet https://github.com/azevedo-home-lab/claude-code-workflows.git "$TMPDIR"
    SCRIPT_DIR="$TMPDIR"
fi

echo "Installing Workflow Manager into: $TARGET"
echo ""

# Validate target is a git repo
if [ ! -d "$TARGET/.git" ]; then
    echo "ERROR: $TARGET is not a git repository."
    echo "Run this from your project root or pass the project path as an argument."
    exit 1
fi

# Create directories
mkdir -p "$TARGET/.claude/hooks"
mkdir -p "$TARGET/.claude/commands"
mkdir -p "$TARGET/.claude/state"

# Copy hooks
cp "$SCRIPT_DIR/.claude/hooks/workflow-state.sh" "$TARGET/.claude/hooks/"
cp "$SCRIPT_DIR/.claude/hooks/workflow-gate.sh" "$TARGET/.claude/hooks/"
cp "$SCRIPT_DIR/.claude/hooks/bash-write-guard.sh" "$TARGET/.claude/hooks/"
chmod +x "$TARGET/.claude/hooks/"*.sh

# Copy commands
cp "$SCRIPT_DIR/.claude/commands/approve.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/discuss.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/review.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/complete.md" "$TARGET/.claude/commands/"

echo "Copied hooks and commands."

# Handle settings.json — merge hooks into existing config or create new
SETTINGS="$TARGET/.claude/settings.json"
HOOKS_CONFIG='{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-gate.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/bash-write-guard.sh"
          }
        ]
      }
    ]
  }
}'

if [ -f "$SETTINGS" ]; then
    # Check if hooks are already configured
    if grep -q "workflow-gate.sh" "$SETTINGS" 2>/dev/null; then
        echo "Hooks already configured in .claude/settings.json — skipping."
    else
        echo ""
        echo "WARNING: .claude/settings.json already exists."
        echo "Add the following hooks configuration manually:"
        echo ""
        echo "$HOOKS_CONFIG"
        echo ""
        echo "If you have existing hooks, add the PreToolUse entries to your existing hooks array."
    fi
else
    echo "$HOOKS_CONFIG" > "$SETTINGS"
    echo "Created .claude/settings.json with hooks configuration."
fi

# Update .gitignore
GITIGNORE="$TARGET/.gitignore"
if [ -f "$GITIGNORE" ]; then
    if ! grep -q ".claude/state/" "$GITIGNORE" 2>/dev/null; then
        echo "" >> "$GITIGNORE"
        echo "# Workflow enforcement state (per-session)" >> "$GITIGNORE"
        echo ".claude/state/" >> "$GITIGNORE"
        echo "Added .claude/state/ to .gitignore."
    fi
else
    echo "# Workflow enforcement state (per-session)" > "$GITIGNORE"
    echo ".claude/state/" >> "$GITIGNORE"
    echo "Created .gitignore with .claude/state/ entry."
fi

# Initialize workflow state to DISCUSS phase
cat > "$TARGET/.claude/state/phase.json" <<'INIT'
{
  "phase": "discuss",
  "updated": "auto-initialized by installer"
}
INIT
echo "Initialized workflow state to DISCUSS phase (edits blocked)."

# Install statusline globally
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_DST="$HOME/.claude/statusline.sh"

cp "$SCRIPT_DIR/statusline/statusline.sh" "$STATUSLINE_DST"
chmod +x "$STATUSLINE_DST"
echo "Installed statusline to $STATUSLINE_DST."

if [ -f "$GLOBAL_SETTINGS" ]; then
    if grep -q "statusline.sh" "$GLOBAL_SETTINGS" 2>/dev/null; then
        echo "Statusline already configured in global settings — skipping."
    else
        # Merge statusLine into existing global settings using python
        python3 -c "
import json, sys
with open('$GLOBAL_SETTINGS') as f:
    settings = json.load(f)
settings['statusLine'] = {
    'type': 'command',
    'command': '$STATUSLINE_DST',
    'padding': 2
}
with open('$GLOBAL_SETTINGS', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" 2>/dev/null && echo "Added statusLine to global settings." || echo "WARNING: Could not update global settings. Add statusLine manually."
    fi
else
    cat > "$GLOBAL_SETTINGS" <<SLCFG
{
  "statusLine": {
    "type": "command",
    "command": "$STATUSLINE_DST",
    "padding": 2
  }
}
SLCFG
    echo "Created global settings with statusLine."
fi

echo ""
echo "Workflow Manager installed!"
echo ""
echo "Usage:"
echo "  /approve  — unlock code edits (after plan is approved)"
echo "  /discuss  — lock code edits (back to discussion mode)"
echo ""
echo "Sessions start in DISCUSS phase. Restart Claude Code to activate."
