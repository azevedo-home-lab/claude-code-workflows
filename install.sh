#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Migration tool — removes old hook-based installation and directs users
# to install via the Claude Code plugin marketplace instead.
#
# Usage:
#   ./install.sh [target-dir]

set -euo pipefail

TARGET="${1:-$(pwd)}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

OLD_HOOKS_DIR="$TARGET/.claude/hooks"
OLD_SETTINGS="$TARGET/.claude/settings.json"

OLD_HOOK_FILES=(
    "workflow-gate.sh"
    "bash-write-guard.sh"
    "post-tool-navigator.sh"
    "workflow-cmd.sh"
    "workflow-state.sh"
)

echo ""
echo "Claude Code Workflows — Migration Tool"
echo "======================================="
echo ""

# Detect old-style installation: workflow-gate.sh exists as a regular file (not a symlink)
if [ -f "$OLD_HOOKS_DIR/workflow-gate.sh" ] && [ ! -L "$OLD_HOOKS_DIR/workflow-gate.sh" ]; then
    warn "Old hook-based installation detected in $TARGET"
    echo ""

    # Remove old hook files (only regular files, not symlinks)
    for hook in "${OLD_HOOK_FILES[@]}"; do
        hook_path="$OLD_HOOKS_DIR/$hook"
        if [ -f "$hook_path" ] && [ ! -L "$hook_path" ]; then
            rm "$hook_path"
            ok "Removed $hook"
        fi
    done

    # Remove hooks directory if empty
    if [ -d "$OLD_HOOKS_DIR" ] && [ -z "$(ls -A "$OLD_HOOKS_DIR")" ]; then
        rmdir "$OLD_HOOKS_DIR"
        ok "Removed empty .claude/hooks/ directory"
    fi

    # Remove hook entries from settings.json
    if [ -f "$OLD_SETTINGS" ]; then
        python3 -c "
import json, sys

settings_path = sys.argv[1]
with open(settings_path) as f:
    settings = json.load(f)

if 'hooks' in settings:
    del settings['hooks']
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('removed')
else:
    print('none')
" "$OLD_SETTINGS"
        HOOK_RESULT=$?
        if [ $HOOK_RESULT -eq 0 ]; then
            ok "Removed hook entries from .claude/settings.json"
        fi
    fi

    echo ""
    ok "Old installation cleaned up"
else
    ok "No old hook-based installation found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Install via Claude Code Plugin Marketplace"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Claude Code Workflows is now distributed as a plugin."
echo "  To install, run inside Claude Code:"
echo ""
echo "    /install-plugin @azevedo-home-lab/claude-code-workflows"
echo ""
echo "  The plugin manages hooks, commands, and state automatically."
echo "  No manual file copying required."
echo ""
