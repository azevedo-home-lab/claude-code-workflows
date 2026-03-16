#!/bin/bash
# Workflow Manager: blocks Write/Edit/MultiEdit/NotebookEdit in DISCUSS phase
# Matcher: Write|Edit|MultiEdit|NotebookEdit
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
if [ "$PHASE" != "discuss" ]; then
    exit 0
fi

# DISCUSS phase: check if the target file is in a whitelisted path
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
# Write tool uses 'file_path', Edit uses 'file_path'
print(ti.get('file_path', ''))
" 2>/dev/null || echo "")

# Allow writes to whitelisted paths
if [ -n "$FILE_PATH" ]; then
    if echo "$FILE_PATH" | grep -qE "$DISCUSS_WRITE_WHITELIST"; then
        exit 0
    fi
fi

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
