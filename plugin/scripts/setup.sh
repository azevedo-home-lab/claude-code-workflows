#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Setup hook — runs on first plugin activation (Setup hook in hooks.json).
# Three responsibilities:
#   A. Project state initialization (workflow.json + .gitignore)
#   B. Global statusline installation (~/.claude/statusline.sh + settings.json)
#   C. Project permissions (ensure tools needed for unattended operation are allowed)

set -euo pipefail

# Verify jq is available (required for all JSON state management)
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed. Install it:" >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Ubuntu: sudo apt-get install jq" >&2
    echo "  Other:  https://jqlang.github.io/jq/download/" >&2
    return 1 2>/dev/null || exit 1  # return when sourced, exit when run directly
fi

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# ─────────────────────────────────────────────────────────────────────────────
# A. Project state initialization
# ─────────────────────────────────────────────────────────────────────────────

STATE_DIR="$PROJECT_DIR/.claude/state"
STATE_FILE="$STATE_DIR/workflow.json"

# Create state directory
mkdir -p "$STATE_DIR"

# Write default workflow.json if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg ts "$ts" '{
    phase: "off",
    message_shown: false,
    active_skill: "",
    decision_record: "",
    coaching: {
      tool_calls_since_agent: 0,
      layer2_fired: []
    },
    updated: $ts,
    autonomy_level: 2
  }' > "$STATE_FILE"
fi

# Add .claude/state/ to .gitignore if not already there
GITIGNORE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -qxF '.claude/state/' "$GITIGNORE"; then
    printf '\n# Workflow Manager state (per-session, not committed)\n.claude/state/\n' >> "$GITIGNORE"
  fi
else
  printf '# Workflow Manager state (per-session, not committed)\n.claude/state/\n' > "$GITIGNORE"
fi

# ─────────────────────────────────────────────────────────────────────────────
# B. Global statusline installation
# ─────────────────────────────────────────────────────────────────────────────

STATUSLINE_SRC="$PLUGIN_ROOT/statusline/statusline.sh"
STATUSLINE_DST="$HOME/.claude/statusline.sh"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"

# Only install if the plugin ships a statusline
if [ -f "$STATUSLINE_SRC" ]; then
  mkdir -p "$HOME/.claude"

  # Back up existing statusline if it differs from ours
  if [ -f "$STATUSLINE_DST" ]; then
    if ! cmp -s "$STATUSLINE_SRC" "$STATUSLINE_DST"; then
      cp "$STATUSLINE_DST" "${STATUSLINE_DST}.backup"
    fi
  fi

  cp "$STATUSLINE_SRC" "$STATUSLINE_DST"
  chmod +x "$STATUSLINE_DST"

  # Configure statusLine in global settings.json
  if [ -f "$GLOBAL_SETTINGS" ]; then
    jq '.statusLine = {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2}' \
      "$GLOBAL_SETTINGS" > "$GLOBAL_SETTINGS.tmp" && mv "$GLOBAL_SETTINGS.tmp" "$GLOBAL_SETTINGS"
  else
    jq -n '{"statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "padding": 2}}' \
      > "$GLOBAL_SETTINGS"
  fi || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# C. Project permissions — ensure tools needed for workflow pipeline are allowed
# ─────────────────────────────────────────────────────────────────────────────

# The workflow pipeline (hooks, coaching, COMPLETE agents) needs these tools
# to operate without permission prompts. Without them, autonomy level 3
# (unattended) is broken by constant approval dialogs.
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"
if [ -f "$PROJECT_SETTINGS" ]; then
  jq '.permissions.allow = ((.permissions.allow // []) + ["Read", "Agent", "Glob", "Grep"] | unique)' \
    "$PROJECT_SETTINGS" > "$PROJECT_SETTINGS.tmp" && mv "$PROJECT_SETTINGS.tmp" "$PROJECT_SETTINGS" || true
fi
