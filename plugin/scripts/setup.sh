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

# Verify python3 is available (required for JSON state management)
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required for Workflow Manager" >&2; exit 1; }
# Warn if jq is missing (required for statusline, not for core hooks)
command -v jq >/dev/null 2>&1 || echo "WARNING: jq not found — statusline will not work. Install: brew install jq" >&2

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
  python3 -c "
import json, sys, datetime
state = {
    'phase': 'off',
    'message_shown': False,
    'active_skill': '',
    'decision_record': '',
    'coaching': {
        'tool_calls_since_agent': 0,
        'layer2_fired': []
    },
    'updated': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'autonomy_level': 2
}
with open(sys.argv[1], 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
" "$STATE_FILE"
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
  python3 -c "
import json, os, sys

settings_path = sys.argv[1]

# Load existing settings or start fresh
if os.path.isfile(settings_path):
    with open(settings_path, 'r') as f:
        settings = json.load(f)
else:
    settings = {}

settings['statusLine'] = {
    'type': 'command',
    'command': '~/.claude/statusline.sh',
    'padding': 2
}

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" "$GLOBAL_SETTINGS" || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# C. Project permissions — ensure tools needed for workflow pipeline are allowed
# ─────────────────────────────────────────────────────────────────────────────

# The workflow pipeline (hooks, coaching, COMPLETE agents) needs these tools
# to operate without permission prompts. Without them, autonomy level 3
# (unattended) is broken by constant approval dialogs.
PROJECT_SETTINGS="$PROJECT_DIR/.claude/settings.json"
if [ -f "$PROJECT_SETTINGS" ]; then
  python3 -c "
import json, sys

settings_path = sys.argv[1]
with open(settings_path, 'r') as f:
    settings = json.load(f)

permissions = settings.setdefault('permissions', {})
allow = permissions.setdefault('allow', [])

# Tools required for unattended workflow operation
required_tools = ['Read', 'Agent', 'Glob', 'Grep']

changed = False
for tool in required_tools:
    if tool not in allow:
        allow.append(tool)
        changed = True

if changed:
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
" "$PROJECT_SETTINGS" || true
fi
