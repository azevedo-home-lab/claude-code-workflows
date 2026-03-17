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
# BASH_SOURCE is unset when piped from curl, so handle that case
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR=""
fi

# If running via curl pipe (or source not found), clone the repo to a temp dir
if [ -z "$SCRIPT_DIR" ] || [ ! -f "$SCRIPT_DIR/.claude/hooks/workflow-gate.sh" ]; then
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    echo "Downloading Workflow Manager..."
    git clone --depth 1 --quiet https://github.com/azevedo-home-lab/claude-code-workflows.git "$TMPDIR"
    SCRIPT_DIR="$TMPDIR"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

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
cp "$SCRIPT_DIR/.claude/hooks/post-tool-navigator.sh" "$TARGET/.claude/hooks/"
chmod +x "$TARGET/.claude/hooks/"*.sh

# Copy commands
cp "$SCRIPT_DIR/.claude/commands/approve.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/discuss.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/review.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/complete.md" "$TARGET/.claude/commands/"
cp "$SCRIPT_DIR/.claude/commands/override.md" "$TARGET/.claude/commands/"

ok "Copied hooks and commands"

# Handle settings.json — merge hooks into existing config or create new
SETTINGS="$TARGET/.claude/settings.json"

if [ -f "$SETTINGS" ]; then
    if grep -q "workflow-gate.sh" "$SETTINGS" 2>/dev/null; then
        ok "Hooks already configured in settings.json"
    else
        python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})

# PreToolUse entries
pre = hooks.setdefault('PreToolUse', [])
gate_entry = {
    'matcher': 'Write|Edit|MultiEdit|NotebookEdit',
    'hooks': [{'type': 'command', 'command': '\$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-gate.sh'}]
}
bash_entry = {
    'matcher': 'Bash',
    'hooks': [{'type': 'command', 'command': '\$CLAUDE_PROJECT_DIR/.claude/hooks/bash-write-guard.sh'}]
}
pre.append(gate_entry)
pre.append(bash_entry)

# PostToolUse entry
post = hooks.setdefault('PostToolUse', [])
nav_entry = {
    'hooks': [{'type': 'command', 'command': '\$CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-navigator.sh'}]
}
post.append(nav_entry)

with open(sys.argv[1], 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" "$SETTINGS"
        ok "Merged workflow hooks into existing settings.json"
    fi
else
    cat > "$SETTINGS" <<'HOOKSCFG'
{
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
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-navigator.sh"
          }
        ]
      }
    ]
  }
}
HOOKSCFG
    ok "Created settings.json with hooks"
fi

# Update .gitignore
GITIGNORE="$TARGET/.gitignore"
if [ -f "$GITIGNORE" ]; then
    if ! grep -q ".claude/state/" "$GITIGNORE" 2>/dev/null; then
        echo "" >> "$GITIGNORE"
        echo "# Workflow enforcement state (per-session)" >> "$GITIGNORE"
        echo ".claude/state/" >> "$GITIGNORE"
        ok "Added .claude/state/ to .gitignore"
    fi
else
    echo "# Workflow enforcement state (per-session)" > "$GITIGNORE"
    echo ".claude/state/" >> "$GITIGNORE"
    ok "Created .gitignore with .claude/state/"
fi

# Initialize workflow state to OFF phase (no enforcement)
cat > "$TARGET/.claude/state/phase.json" <<'INIT'
{
  "phase": "off",
  "message_shown": false,
  "updated": "auto-initialized by installer"
}
INIT
ok "Initialized workflow state to OFF phase"

# Install statusline globally
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
STATUSLINE_DST="$HOME/.claude/statusline.sh"

cp "$SCRIPT_DIR/statusline/statusline.sh" "$STATUSLINE_DST"
chmod +x "$STATUSLINE_DST"
ok "Installed statusline to $STATUSLINE_DST"

if [ -f "$GLOBAL_SETTINGS" ]; then
    if grep -q "statusline.sh" "$GLOBAL_SETTINGS" 2>/dev/null; then
        ok "Statusline already configured in global settings"
    else
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
" 2>/dev/null && ok "Added statusLine to global settings" || warn "Could not update global settings — add statusLine manually"
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
    ok "Created global settings with statusLine"
fi

echo ""
ok "Workflow Manager installed!"
echo ""
echo "Usage:"
echo "  /discuss    — start workflow (brainstorming, edits blocked)"
echo "  /approve    — unlock code edits (after plan is approved)"
echo "  /review     — run multi-agent review pipeline"
echo "  /complete   — verified completion (back to off)"
echo "  /override   — jump to any phase (off/discuss/implement/review)"
echo ""
echo "Sessions start in OFF phase (no enforcement). Use /discuss to begin a workflow."

# --- Optional features ---

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Optional features (install separately)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# CLAUDE.md template
CLAUDE_MD="$TARGET/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
    echo "  CLAUDE.md template"
    echo "    Your project has a CLAUDE.md. Review the template and merge missing sections"
    echo "    (behavioral rules, security rules, context window management, claude-mem handover):"
    echo "    curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/claude.md.template"
    echo ""
else
    echo "  CLAUDE.md template"
    echo "    Add behavioral rules, security rules, and session management to your project:"
    echo "    curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/claude.md.template > CLAUDE.md"
    echo ""
fi

# iTerm launcher (macOS only)
if [ "$(uname)" = "Darwin" ]; then
    echo "  iTerm Launcher (macOS)"
    echo "    Launch Claude Code in iTerm2 with project badge. Works with VSCode and Zed:"
    echo "    curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/iterm-launcher/install.sh | bash -s -- --vscode"
    echo "    curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/iterm-launcher/install.sh | bash -s -- --zed"
    echo ""
fi

# YubiKey setup (macOS only, check if signing is configured)
if [ "$(uname)" = "Darwin" ]; then
    echo "  YubiKey Git Signing (macOS)"
    echo "    Git wrapper with touch banners + SSH wrappers for FIDO2 signing in Claude Code:"
    echo "    curl -fsSL https://raw.githubusercontent.com/azevedo-home-lab/claude-code-workflows/main/tools/yubikey-setup/install.sh | bash"
    echo ""
fi

echo "Restart Claude Code to activate hooks."
