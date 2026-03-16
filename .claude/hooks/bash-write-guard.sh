#!/bin/bash
# Workflow Manager: blocks Bash write operations in DISCUSS phase
# Matcher: Bash
# Catches: redirections, sed -i, tee, heredocs, python file writes
#
# Whitelisted paths (allowed in DISCUSS phase):
#   - .claude/state/         (workflow state files)
#   - docs/superpowers/specs/ (design specs)
#   - docs/plans/            (implementation plans)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# No state file = no enforcement (first run, hooks not yet activated)
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

# Allow everything in implement and review phases
if [ "$PHASE" = "implement" ] || [ "$PHASE" = "review" ]; then
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

# Detect write patterns: redirections, sed -i, tee, heredocs, python file writes
# Note: python3 -c only blocked when combined with file-write indicators (open/write)
if echo "$COMMAND" | grep -qE '(>[^&]|>>|sed[[:space:]]+-i|tee[[:space:]]|cat[[:space:]].*<<|python[3]?[[:space:]]+-c.*\.(write|open)|echo[[:space:]].*>)'; then
    # Write detected — allow if targeting whitelisted paths (state, specs, plans)
    if echo "$COMMAND" | grep -qE "$DISCUSS_WRITE_WHITELIST"; then
        exit 0
    fi
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
