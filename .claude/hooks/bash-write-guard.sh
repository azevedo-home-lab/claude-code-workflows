#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: blocks Bash write operations in DEFINE, DISCUSS, and COMPLETE phases
# Matcher: Bash
# Catches: redirections, sed -i, tee, heredocs, python file writes
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

# Read the tool input from stdin
INPUT=$(cat)

# Extract the command from JSON (handles escaped quotes in values)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# If we can't extract the command, allow (fail open)
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Allow any command targeting whitelisted paths
if echo "$COMMAND" | grep -qE "$WHITELIST"; then
    exit 0
fi
# Allow workflow state commands for phase transitions and state management
if echo "$COMMAND" | grep -qE '(workflow-state\.sh|set_phase|get_phase|reset_review_status|[sg]et_review_field|[sg]et_active_skill|[sg]et_decision_record|check_soft_gate|increment_coaching_counter|reset_coaching_counter|add_coaching_fired|has_coaching_fired)'; then
    exit 0
fi

# Detect write patterns: redirections, sed -i, tee, heredocs, python file writes
# Note: python3 -c only blocked when combined with file-write indicators (open/write)
if echo "$COMMAND" | grep -qE '(>[^&]|>>|sed[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|python[3]?[[:space:]]+-c.*\.(write|open)|echo[[:space:]].*>)'; then
    # Phase-aware deny message
    case "$PHASE" in
        define)   REASON="BLOCKED: Bash write operation detected in DEFINE phase. Code changes are not allowed until you define the problem and outcomes." ;;
        discuss)  REASON="BLOCKED: Bash write operation detected in DISCUSS phase. Code changes are not allowed until a plan is discussed and approved. Use /implement to proceed to implementation." ;;
        complete) REASON="BLOCKED: Bash write operation detected in COMPLETE phase. Code changes are not allowed during completion. Only documentation updates are permitted." ;;
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
fi

# Read-only Bash commands are allowed
exit 0
