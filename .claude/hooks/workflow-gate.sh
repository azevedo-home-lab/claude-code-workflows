#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Write/Edit/MultiEdit/NotebookEdit in DEFINE, DISCUSS, and COMPLETE phases
# Matcher: Write|Edit|MultiEdit|NotebookEdit
#
# Whitelist tiers:
#   Restrictive (DEFINE/DISCUSS): .claude/state/, docs/superpowers/specs/, docs/superpowers/plans/, docs/plans/
#   Docs-allowed (COMPLETE):      .claude/state/, docs/ (all), *.md at project root

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# No state file = no enforcement (first run, hooks not yet activated)
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

# Allow everything in implement, review, and off phases
case "$PHASE" in
    implement|review|off) exit 0 ;;
esac

# Select whitelist based on phase
case "$PHASE" in
    define|discuss) WHITELIST="$RESTRICTED_WRITE_WHITELIST" ;;
    complete)       WHITELIST="$COMPLETE_WRITE_WHITELIST" ;;
    *)              exit 0 ;;
esac

# Check if the target file is in a whitelisted path
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('file_path', ''))
" 2>/dev/null || echo "")

# Reject path traversal attempts
if [ -n "$FILE_PATH" ] && echo "$FILE_PATH" | grep -qE '\.\.'; then
    FILE_PATH=""  # Force deny — traversal paths are never whitelisted
fi

# Normalize path: strip project root prefix for consistent matching
# (Claude Code may pass absolute paths like /Users/.../project/README.md)
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
NORMALIZED_PATH="$FILE_PATH"
if [ -n "$PROJECT_ROOT" ]; then
    NORMALIZED_PATH="${FILE_PATH#"$PROJECT_ROOT"/}"
fi

# Allow writes to whitelisted paths
if [ -n "$NORMALIZED_PATH" ]; then
    if echo "$NORMALIZED_PATH" | grep -qE "$WHITELIST"; then
        exit 0
    fi
fi

# Phase-aware deny message
case "$PHASE" in
    define)   REASON="BLOCKED: Phase is DEFINE. Code changes are not allowed until you define the problem and outcomes." ;;
    discuss)  REASON="BLOCKED: Phase is DISCUSS. Code changes are not allowed until a plan is discussed and approved. Use /implement to proceed to implementation." ;;
    complete) REASON="BLOCKED: Phase is COMPLETE. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
    *)        REASON="BLOCKED: Unexpected phase ($PHASE)." ;;
esac

REASON="$REASON" python3 -c "
import json, os
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': os.environ['REASON']
    }
}
print(json.dumps(output))
"
exit 0
