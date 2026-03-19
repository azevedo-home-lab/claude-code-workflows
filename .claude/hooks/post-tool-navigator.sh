#!/bin/bash
# Workflow Manager: PostToolUse phase navigator
# Fires once per phase transition to remind Claude of current phase and next steps.
# After the message is shown once, it goes silent until the phase changes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# No state file = no enforcement
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

# Already shown message for this phase — stay silent
if [ "$(get_message_shown)" = "true" ]; then
    exit 0
fi

PHASE=$(get_phase)

# Read tool name from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

# IMPLEMENT phase: only fire on Write/Edit/Bash, skip Read/Grep/Glob
if [ "$PHASE" = "implement" ]; then
    case "$TOOL_NAME" in
        Write|Edit|MultiEdit|NotebookEdit|Bash)
            ;;
        *)
            exit 0
            ;;
    esac
fi

# Build phase-specific message
case "$PHASE" in
    define)
        MSG="You are in DEFINE phase. Next steps: define the problem statement, outcomes, and success metrics. When definition is complete, use /discuss to proceed to discussion and planning."
        ;;
    discuss)
        MSG="You are in DISCUSS phase. Next steps: use superpowers:brainstorming to explore requirements, then superpowers:writing-plans to create a plan. When plan is ready, user will /approve. User can /discuss to restart discussion at any time."
        ;;
    implement)
        MSG="You are in IMPLEMENT phase. Code was modified. Next steps: continue implementing the approved plan, use superpowers:executing-plans with review checkpoints and superpowers:test-driven-development for tests before code. When implementation is complete, user will /review to enter review phase. User can /discuss to go back to discussion at any time."
        ;;
    review)
        MSG="You are in REVIEW phase. The /review command has initiated the review pipeline. Follow the pipeline steps: run tests, detect changes, dispatch review agents, verify findings, present consolidated report. When review passes, user will /complete to finish. User can /discuss to go back at any time."
        ;;
    *)
        exit 0
        ;;
esac

# Mark message as shown
set_message_shown

# Return message via hookSpecificOutput
MSG="$MSG" python3 -c "
import json, os
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'systemMessage': os.environ['MSG']
    }
}
print(json.dumps(output))
"
