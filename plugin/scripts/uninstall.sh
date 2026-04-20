#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# Uninstall WFM from the current project and optionally globally.
# Usage: uninstall.sh [--global]
#   No flag:  removes project-level WFM files only
#   --global: also uninstalls the plugin from Claude Code

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

echo "Uninstalling Workflow Manager from: $PROJECT_DIR"

# Remove project-level files created by setup.sh
rm -rf "$PROJECT_DIR/.claude/state"
rm -rf "$PROJECT_DIR/.claude/commands"
echo "  Removed .claude/state/ and .claude/commands/"

# Remove stale hooks directory if it exists
rm -rf "$PROJECT_DIR/.claude/hooks"

# Remove WFM permissions from project settings (keep the file)
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"
if [ -f "$PROJECT_SETTINGS" ] && command -v jq &>/dev/null; then
  # Remove hooks section if present
  if jq -e '.hooks' "$PROJECT_SETTINGS" &>/dev/null; then
    jq 'del(.hooks)' "$PROJECT_SETTINGS" > "$PROJECT_SETTINGS.tmp" \
      && mv "$PROJECT_SETTINGS.tmp" "$PROJECT_SETTINGS"
  fi
  echo "  Cleaned project settings"
fi

echo "  Project cleanup complete."

# Global uninstall if requested
if [ "${1:-}" = "--global" ]; then
  echo ""
  echo "Global uninstall:"

  # Remove statusline
  rm -f "$HOME/.claude/statusline.sh"
  rm -f "$HOME/.claude/statusline.sh.backup"

  # Remove statusLine from global settings
  GLOBAL_SETTINGS="$HOME/.claude/settings.json"
  if [ -f "$GLOBAL_SETTINGS" ] && command -v jq &>/dev/null; then
    jq 'del(.statusLine)' "$GLOBAL_SETTINGS" > "$GLOBAL_SETTINGS.tmp" \
      && mv "$GLOBAL_SETTINGS.tmp" "$GLOBAL_SETTINGS"
    echo "  Removed statusline from global settings"
  fi

  # Uninstall plugin via Claude Code
  if command -v claude &>/dev/null; then
    claude plugin uninstall workflow-manager@azevedo-home-lab 2>/dev/null || true
    echo "  Uninstalled plugin from Claude Code"
  fi

  echo "  Global cleanup complete."
fi

echo ""
echo "Done. Restart Claude Code for changes to take effect."
