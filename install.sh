#!/bin/bash
# Install Claude Code Workflow Enforcement Hooks into the current project
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
    echo "Downloading workflow hooks..."
    git clone --depth 1 --quiet https://github.com/azevedo-home-lab/claude-code-workflows.git "$TMPDIR"
    SCRIPT_DIR="$TMPDIR"
fi

echo "Installing workflow enforcement hooks into: $TARGET"
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

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  /approve  — unlock code edits (after plan is approved)"
echo "  /discuss  — lock code edits (back to discussion mode)"
echo ""
echo "New Claude Code sessions start in DISCUSS phase (edits blocked)."
echo "Restart Claude Code to activate the hooks."
