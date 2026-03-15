#!/bin/bash
# PreToolUse hook: blocks Write/Edit/MultiEdit/NotebookEdit in DISCUSS phase
# Matcher: Write|Edit|MultiEdit|NotebookEdit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

PHASE=$(get_phase)

if [ "$PHASE" = "discuss" ]; then
    cat <<'DENY'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Phase is DISCUSS. Code changes are not allowed until a plan is discussed and approved. Use /approve to proceed to implementation."
  }
}
DENY
    exit 0
fi

# Phase is "implement" — allow
exit 0
