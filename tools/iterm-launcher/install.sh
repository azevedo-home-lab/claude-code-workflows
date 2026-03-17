#!/bin/bash
# Install Claude Code iTerm2 launcher
#
# Installs:
#   1. iTerm2 dynamic profile (Claude Code)
#   2. Launcher script to ~/bin/
#   3. IDE-specific keybinding (optional)
#
# Usage:
#   ./install.sh              # Install profile + launcher
#   ./install.sh --vscode     # Also configure VSCode keybinding
#   ./install.sh --zed        # Also configure Zed keybinding
#   ./install.sh --uninstall  # Remove everything

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
LAUNCHER_DIR="$HOME/bin"
LAUNCHER="$LAUNCHER_DIR/launch-claude-iterm"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1" >&2; }

uninstall() {
    echo "Uninstalling Claude Code iTerm launcher..."
    rm -f "$LAUNCHER"
    rm -f "$PROFILE_DIR/claude-code.json"
    ok "Removed launcher and iTerm profile"
    echo ""
    echo "IDE keybindings must be removed manually:"
    echo "  VSCode: Remove 'Claude Code in iTerm2' from tasks.json and keybindings.json"
    echo "  Zed:    Remove 'Claude Code in iTerm' from tasks.json and keymap.json"
    exit 0
}

install_profile() {
    mkdir -p "$PROFILE_DIR"
    cp "$SCRIPT_DIR/claude-code-profile.json" "$PROFILE_DIR/claude-code.json"
    ok "iTerm2 profile installed"
}

install_launcher() {
    mkdir -p "$LAUNCHER_DIR"
    cp "$SCRIPT_DIR/launch-claude-iterm.sh" "$LAUNCHER"
    chmod +x "$LAUNCHER"
    ok "Launcher installed at $LAUNCHER"

    # Check ~/bin is in PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$LAUNCHER_DIR"; then
        warn "$LAUNCHER_DIR is not in PATH — add to your shell profile:"
        echo "  export PATH=\"\$HOME/bin:\$PATH\""
    fi
}

configure_vscode() {
    local VSCODE_DIR="$HOME/Library/Application Support/Code/User"

    if [ ! -d "$VSCODE_DIR" ]; then
        warn "VSCode user directory not found — skipping"
        return
    fi

    # tasks.json
    local TASKS_FILE="$VSCODE_DIR/tasks.json"
    if [ -f "$TASKS_FILE" ] && grep -q "Claude Code in iTerm2" "$TASKS_FILE"; then
        ok "VSCode task already configured"
    else
        cat > "$TASKS_FILE" <<'TASKS'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Claude Code in iTerm2",
      "type": "shell",
      "command": "~/bin/launch-claude-iterm '${workspaceFolder}'",
      "presentation": {"reveal": "never"},
      "problemMatcher": []
    }
  ]
}
TASKS
        ok "VSCode task configured"
    fi

    # keybindings.json — auto-add if not present
    local KEYS_FILE="$VSCODE_DIR/keybindings.json"
    if [ -f "$KEYS_FILE" ] && grep -q "Claude Code in iTerm2" "$KEYS_FILE"; then
        ok "VSCode keybinding already configured"
    else
        local NEW_BINDING='{"key": "cmd+shift+i", "command": "workbench.action.tasks.runTask", "args": "Claude Code in iTerm2"}'
        python3 -c "
import json, sys
path = sys.argv[1]
entry = json.loads(sys.argv[2])
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = []
data.append(entry)
with open(path, 'w') as f:
    json.dump(data, f, indent=4)
    f.write('\n')
" "$KEYS_FILE" "$NEW_BINDING"
        ok "VSCode keybinding added (Cmd+Shift+I)"
    fi
}

configure_zed() {
    local ZED_DIR="$HOME/.config/zed"

    if [ ! -d "$ZED_DIR" ]; then
        warn "Zed config directory not found — skipping"
        return
    fi

    # tasks.json
    local TASKS_FILE="$ZED_DIR/tasks.json"
    if [ -f "$TASKS_FILE" ] && grep -q "Claude Code in iTerm" "$TASKS_FILE"; then
        ok "Zed task already configured"
    else
        cat > "$TASKS_FILE" <<'TASKS'
[
  {
    "label": "Claude Code in iTerm",
    "command": "~/bin/launch-claude-iterm \"$ZED_WORKTREE_ROOT\"",
    "reveal": "never",
    "hide": "always"
  }
]
TASKS
        ok "Zed task configured"
    fi

    # keymap.json — auto-add if not present
    local KEYMAP_FILE="$ZED_DIR/keymap.json"
    if [ -f "$KEYMAP_FILE" ] && grep -q "Claude Code in iTerm" "$KEYMAP_FILE"; then
        ok "Zed keybinding already configured"
    else
        local NEW_BINDING='{"context": "Workspace", "bindings": {"cmd-shift-i": ["task::Spawn", {"task_name": "Claude Code in iTerm"}]}}'
        python3 -c "
import json, sys
path = sys.argv[1]
entry = json.loads(sys.argv[2])
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = []
data.append(entry)
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$KEYMAP_FILE" "$NEW_BINDING"
        ok "Zed keybinding added (Cmd+Shift+I)"
    fi
}

# --- Main ---

if [ "${1:-}" = "--uninstall" ]; then
    uninstall
fi

echo "Installing Claude Code iTerm2 launcher..."
echo ""

install_profile
install_launcher

case "${1:-}" in
    --vscode) configure_vscode ;;
    --zed)    configure_zed ;;
    "")       ;;
    *)        err "Unknown option: $1"; echo "Usage: ./install.sh [--vscode|--zed|--uninstall]"; exit 1 ;;
esac

echo ""
ok "Installation complete!"
echo ""
echo "Usage:"
echo "  launch-claude-iterm /path/to/project    # From terminal"
echo "  Cmd+Shift+I                              # From IDE (if configured)"
echo ""
echo "The iTerm badge shows 'Claude <project-name>' for identification."
