#!/usr/bin/env bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows — CL Plugin.
# See LICENSE for details.
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"

echo "=== CL Plugin Uninstall ==="

# Confirmation prompt (unless --force passed)
if [ "${1:-}" != "--force" ]; then
  printf "This will remove the CL plugin from this project (complete.md, marketplace.json, state files). Proceed? (y/N) "
  read -r CONFIRM
  case "$CONFIRM" in
    y|Y) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# Strip sentinel from complete.md
COMPLETE_MD="$PROJECT_DIR/plugin/commands/complete.md"
if [ -f "$COMPLETE_MD" ] && grep -q 'CL-INJECT-START' "$COMPLETE_MD"; then
  echo "Removing CL trigger from complete.md..."
  # Use awk for cross-platform compatibility (avoids sed -i differences between macOS/GNU)
  awk '/<!-- CL-INJECT-START -->/{skip=1; next} /<!-- CL-INJECT-END -->/{skip=0; next} !skip{print}' \
    "$COMPLETE_MD" > "$COMPLETE_MD.tmp" && mv "$COMPLETE_MD.tmp" "$COMPLETE_MD"
  echo "CL trigger removed"
fi

# Remove state files
echo "Removing state files..."
rm -f "$PROJECT_DIR/.claude/state/cl-state.json"
rm -f "$PROJECT_DIR/.claude/state/cl-state.lock"
rm -f "$PROJECT_DIR/.claude/state/cl-active-rules.json"

# Remove from marketplace.json
MARKETPLACE="$PROJECT_DIR/.claude-plugin/marketplace.json"
if [ -f "$MARKETPLACE" ] && jq -e '.plugins[] | select(.name=="continuous-learning")' "$MARKETPLACE" &>/dev/null; then
  echo "Removing from marketplace.json..."
  jq '.plugins = [.plugins[] | select(.name != "continuous-learning")]' \
    "$MARKETPLACE" > "$MARKETPLACE.tmp" && mv "$MARKETPLACE.tmp" "$MARKETPLACE"
  echo "Removed from marketplace.json"
fi

# Remove symlink
rm -f "$PROJECT_DIR/.claude/commands/evolve.md"
echo "Removed /evolve command symlink"

echo ""
echo "=== CL Plugin Uninstalled ==="
echo "Remove cl-plugin/ directory manually to delete config and prompts."
