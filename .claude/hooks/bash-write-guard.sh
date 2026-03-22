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

# If we can't extract the command, deny (fail closed — security over availability)
if [ -z "$COMMAND" ]; then
    REASON="BLOCKED: Could not parse Bash command in $PHASE phase. Fail-closed for security."
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

# Allow workflow state commands ONLY when they are the sole command
# (prevents bypass by chaining: source workflow-state.sh && echo pwned > evil)
if echo "$COMMAND" | grep -qE '^[[:space:]]*(source[[:space:]]|\.[ /]).*workflow-state\.sh'; then
    # Reject if command contains chain operators after the source
    if ! echo "$COMMAND" | grep -qE '(&&|\|\||;|\|)'; then
        exit 0
    fi
fi

# Detect write patterns: redirections, sed -i, tee, heredocs, python file writes,
# cp, mv, install, curl -o, wget -O (common file-writing commands)
# Note: python3 -c only blocked when combined with file-write indicators (open/write)
WRITE_PATTERN='(>[^&]|>>|sed[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|python[3]?[[:space:]]+-c.*\.(write|open)|echo[[:space:]].*>|^[[:space:]]*cp[[:space:]]|^[[:space:]]*mv[[:space:]]|^[[:space:]]*rm[[:space:]]|^[[:space:]]*install[[:space:]]|curl[[:space:]].*-o[[:space:]]|wget[[:space:]].*-O[[:space:]]|dd[[:space:]].*of=|^[[:space:]]*patch[[:space:]]|^[[:space:]]*ln[[:space:]])'

# Strip safe redirects before checking write patterns
# 2>/dev/null, 2>&1, 1>&2 etc. are not file writes
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]+>\/dev\/null//g; s/[0-9]*>&[0-9]+//g')

if echo "$CLEAN_CMD" | grep -qE "$WRITE_PATTERN"; then
    # Extract the write target path from the command for whitelist checking
    # For redirections: extract path after > or >>
    # For cp/mv: extract the last argument
    WRITE_TARGET=$(echo "$COMMAND" | python3 -c "
import sys, re
cmd = sys.stdin.read().strip()
# Try redirect target first (most common)
m = re.search(r'>{1,2}\s*(\S+)', cmd)
if m:
    print(m.group(1))
else:
    # For cp/mv/install: last argument is typically the target
    parts = cmd.split()
    if len(parts) >= 3 and parts[0] in ('cp', 'mv', 'install'):
        print(parts[-1])
    else:
        print('')
" 2>/dev/null || echo "")

    # Reject path traversal attempts (../ in the target)
    if [ -n "$WRITE_TARGET" ] && echo "$WRITE_TARGET" | grep -qE '\.\.'; then
        WRITE_TARGET=""  # Force deny — traversal paths are never whitelisted
    fi

    # If we can identify a write target, check it against the whitelist
    if [ -n "$WRITE_TARGET" ] && echo "$WRITE_TARGET" | grep -qE "$WHITELIST"; then
        exit 0
    fi
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
