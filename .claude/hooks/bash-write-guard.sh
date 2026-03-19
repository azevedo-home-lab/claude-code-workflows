#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Bash write operations in DISCUSS and DEFINE phases
# Matcher: Bash
# Catches: redirections, sed -i, tee, heredocs, python file writes
#
# Whitelisted paths (allowed in DISCUSS phase):
#   - .claude/state/              (workflow state files)
#   - docs/superpowers/specs/     (design specs)
#   - docs/superpowers/plans/     (implementation plans)
#   - docs/plans/                 (implementation plans, legacy path)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# No state file = no enforcement (first run, hooks not yet activated)
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

# Allow everything in non-discuss/non-define phases (off, implement, review)
if [ "$PHASE" != "discuss" ] && [ "$PHASE" != "define" ]; then
    exit 0
fi

# Read the tool input from stdin
INPUT=$(cat)

# Extract the command from JSON (handles escaped quotes in values)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# If we can't extract the command, allow (fail open)
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Allow any command targeting whitelisted paths (state, specs, plans)
# Also allow workflow state commands (set_phase, workflow-state.sh) for phase transitions
if echo "$COMMAND" | grep -qE "$DISCUSS_WRITE_WHITELIST"; then
    exit 0
fi
if echo "$COMMAND" | grep -qE '(workflow-state\.sh|set_phase|reset_review_status|set_review_field)'; then
    exit 0
fi

# Detect write patterns: redirections, sed -i, tee, heredocs, python file writes
# Note: python3 -c only blocked when combined with file-write indicators (open/write)
if echo "$COMMAND" | grep -qE '(>[^&]|>>|sed[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|python[3]?[[:space:]]+-c.*\.(write|open)|echo[[:space:]].*>)'; then
    # Phase-aware deny message
    if [ "$PHASE" = "define" ]; then
        REASON="BLOCKED: Bash write operation detected in DEFINE phase. Code changes are not allowed until you define the problem and outcomes. Use /discuss to proceed to discussion."
    else
        REASON="BLOCKED: Bash write operation detected in DISCUSS phase. Code changes are not allowed until a plan is discussed and approved. Use /approve to proceed to implementation."
    fi

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
fi

# Read-only Bash commands are allowed in discuss phase
exit 0
