#!/bin/bash
# PreToolUse hook: blocks Bash write operations in DISCUSS phase
# Matcher: Bash
# Catches: redirections, sed -i, tee, heredocs, python file writes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

PHASE=$(get_phase)

# Allow everything in implement phase
if [ "$PHASE" = "implement" ]; then
    exit 0
fi

# Read the tool input from stdin
INPUT=$(cat)

# Extract the command from JSON
COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')

# If we can't extract the command, allow (fail open)
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Check for write patterns
WRITE_PATTERN='(>[^&]|>>|sed[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|python[3]?[[:space:]]+-c.*open.*write|echo[[:space:]].*>)'

if echo "$COMMAND" | grep -qE "$WRITE_PATTERN"; then
    cat <<'DENY'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Bash write operation detected in DISCUSS phase. Code changes are not allowed until a plan is discussed and approved. Use /approve to proceed to implementation."
  }
}
DENY
    exit 0
fi

# Read-only Bash commands are allowed in discuss phase
exit 0
