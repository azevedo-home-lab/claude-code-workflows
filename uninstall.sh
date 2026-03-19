#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Remove Claude Code Workflow Manager from the current project
# Usage: ./uninstall.sh [/path/to/project]

set -euo pipefail

TARGET="${1:-$(pwd)}"

echo "Removing Workflow Manager from: $TARGET"
echo ""

# Remove hook files
rm -f "$TARGET/.claude/hooks/workflow-state.sh"
rm -f "$TARGET/.claude/hooks/workflow-gate.sh"
rm -f "$TARGET/.claude/hooks/bash-write-guard.sh"
rm -f "$TARGET/.claude/hooks/post-tool-navigator.sh"

# Remove commands
rm -f "$TARGET/.claude/commands/approve.md"
rm -f "$TARGET/.claude/commands/discuss.md"
rm -f "$TARGET/.claude/commands/review.md"
rm -f "$TARGET/.claude/commands/complete.md"
rm -f "$TARGET/.claude/commands/override.md"

# Remove state
rm -rf "$TARGET/.claude/state"

# Clean up empty directories
rmdir "$TARGET/.claude/hooks" 2>/dev/null || true
rmdir "$TARGET/.claude/commands" 2>/dev/null || true

echo "Removed hooks, commands, and state."
echo ""
echo "NOTE: .claude/settings.json was not modified."
echo "Remove the PreToolUse hook entries for workflow-gate.sh and bash-write-guard.sh manually."
echo ""
echo "Restart Claude Code to deactivate the hooks."