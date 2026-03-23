#!/bin/bash
# Copyright (C) 2026 azevedo-home-lab
# SPDX-License-Identifier: GPL-3.0-only
#
# This file is part of Claude Code Workflows.
# See LICENSE for details.

# Workflow Manager: PostToolUse three-layer coaching system
# Layer 1: Phase entry — objective, scope, done criteria (once per phase)
# Layer 2: Professional standards reinforcement (periodic, contextual)
# Layer 3: Anti-laziness checks (on every red-flag match)
#
# All messages prefixed with [Workflow Coach — PHASE] for user visibility.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workflow-state.sh"

# Read tool name and input from stdin (must happen before any early exits)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

# Helper: extract bash command from tool input (used by Layer 2/3 checks)
extract_bash_command() {
    echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Claude-mem observation ID tracking
# Extracts observation ID from save_observation (dict response) or
# get_observations (list response) and writes to workflow state.
# Runs before phase checks so IDs are captured regardless of phase.
# ---------------------------------------------------------------------------
if echo "$TOOL_NAME" | grep -qE 'mcp.*(save_observation|get_observations)'; then
    # Determine extraction mode: save returns a dict, get returns a list
    EXTRACT_MODE="dict"
    if echo "$TOOL_NAME" | grep -qE 'get_observations'; then
        EXTRACT_MODE="list"
    fi
    OBS_ID=$(echo "$INPUT" | EXTRACT_MODE="$EXTRACT_MODE" python3 -c "
import sys, json, os
mode = os.environ.get('EXTRACT_MODE', 'dict')
d = json.load(sys.stdin)
resp = d.get('tool_response', {})
content = resp.get('content', [])
for block in content:
    if block.get('type') == 'text':
        try:
            data = json.loads(block['text'])
            if mode == 'dict' and isinstance(data, dict) and 'id' in data:
                print(data['id'])
                sys.exit(0)
            elif mode == 'list' and isinstance(data, list) and len(data) > 0 and 'id' in data[-1]:
                print(data[-1]['id'])
                sys.exit(0)
        except (json.JSONDecodeError, KeyError):
            pass
# Fallback: try tool_response directly (non-MCP format)
if isinstance(resp, dict) and 'id' in resp:
    print(resp['id'])
else:
    print('')
" 2>/dev/null || echo "")
    # Validate OBS_ID is numeric before storing
    if [[ "$OBS_ID" =~ ^[0-9]+$ ]]; then
        set_last_observation_id "$OBS_ID"
    fi
fi

# No state file = no coaching enforcement
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(get_phase)

# OFF phase = no coaching
if [ "$PHASE" = "off" ]; then
    exit 0
fi

# Collect messages from all layers — may combine multiple
MESSAGES=""

# ============================================================
# LAYER 1: Phase entry message (fires once per phase transition)
# ============================================================

if [ "$(get_message_shown)" != "true" ]; then
    # IMPLEMENT phase: only fire on Write/Edit/Bash, skip Read/Grep/Glob
    FIRE_LAYER1=true
    if [ "$PHASE" = "implement" ]; then
        case "$TOOL_NAME" in
            Write|Edit|MultiEdit|NotebookEdit|Bash) ;;
            *) FIRE_LAYER1=false ;;
        esac
    fi

    if [ "$FIRE_LAYER1" = "true" ]; then
        case "$PHASE" in
            define)
                MESSAGES="[Workflow Coach — DEFINE]
Objective: Frame the problem and define measurable outcomes.
You are in Diamond 1 (Problem Space). Diverge on understanding, converge on a clear problem statement.
Done when: Decision record has a complete Problem section with measurable outcomes, approved by user."
                ;;
            discuss)
                MESSAGES="[Workflow Coach — DISCUSS]
Objective: Research solution approaches, choose one with documented rationale, write implementation plan.
You are in Diamond 2 (Solution Space). Diverge on possibilities, converge through codebase and risk analysis.
Done when: Decision record has Approaches Considered + Decision sections. Plan file created. User approved."
                ;;
            implement)
                MESSAGES="[Workflow Coach — IMPLEMENT]
Objective: Build the chosen solution following the approved plan with TDD discipline.
Follow the plan. Flag deviations. Write tests before code.
Done when: All plan steps implemented, tests passing, ready for review."
                ;;
            review)
                MESSAGES="[Workflow Coach — REVIEW]
Objective: Independent multi-agent validation of implementation quality.
Report findings accurately. Don't downgrade severity. Quantify impact and fix effort.
Done when: All agents dispatched, findings verified and persisted to decision record, user has responded."
                ;;
            complete)
                MESSAGES="[Workflow Coach — COMPLETE]
Objective: Verify outcomes were met, update documentation, hand over for future sessions.
Be specific about failures. Recommend next steps. Audit tech debt. Write a useful handover.
Done when: Validation results in decision record, README checked, claude-mem observation saved, phase OFF."
                ;;
        esac
        # Append Level 3 auto-transition guidance if applicable
        AUTONOMY_LEVEL=$(get_autonomy_level)
        if [ "$AUTONOMY_LEVEL" = "3" ] && [ -n "$MESSAGES" ]; then
            MESSAGES="$MESSAGES
▶▶▶ Level 3 active — when this phase's work is complete, proceed to the next phase without waiting for user confirmation. Exceptions: stop for user input in DISCUSS/DEFINE, stop before git push, stop if review finds blocking issues."
        fi

        set_message_shown
    fi
fi

# Early exit for tools that don't participate in Layer 2/3
# These tools don't need coaching evaluation or counter tracking
case "$TOOL_NAME" in
    Agent|Write|Edit|MultiEdit|NotebookEdit|Bash|AskUserQuestion) ;;
    mcp*save_observation|mcp*get_observations) ;;
    *) # Tool is irrelevant to coaching — output any Layer 1 message and exit
        if [ -n "$MESSAGES" ]; then
            MESSAGES="$MESSAGES" python3 -c "
import json, os
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'systemMessage': os.environ['MESSAGES']
    }
}
print(json.dumps(output))
"
        fi
        exit 0
        ;;
esac

# ============================================================
# LAYER 2: Professional standards reinforcement (periodic)
# ============================================================

# Extract FILE_PATH once for Write/Edit/MultiEdit tools (used by multiple Layer 2/3 checks)
FILE_PATH=""
case "$TOOL_NAME" in
    Write|Edit|MultiEdit)
        FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
        ;;
esac

# Only fire if Layer 1 has already fired (message_shown = true means we're past entry)
if [ "$(get_message_shown)" = "true" ]; then
    # Refresh Layer 2 triggers after 30 calls of silence (before counter reset)
    check_coaching_refresh

    # Track agent dispatch counter
    if [ "$TOOL_NAME" = "Agent" ]; then
        reset_coaching_counter
    else
        increment_coaching_counter
    fi

    # Determine trigger type based on phase + tool pattern
    TRIGGER=""
    L2_MSG=""

    case "$PHASE" in
        define)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_define"
                L2_MSG="[Workflow Coach — DEFINE] Challenge the first framing. Separate facts from interpretations. Are these findings changing the problem statement?"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'decisions\.md'; then
                    TRIGGER="decision_record_define"
                    L2_MSG="[Workflow Coach — DEFINE] Challenge vague problem statements. Outcomes must be verifiable, not aspirational. 'Better UX' is aspirational; 'checkout completes in under 3 clicks' is verifiable."
                fi
            fi
            ;;
        discuss)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_discuss"
                L2_MSG="[Workflow Coach — DISCUSS] Every approach must have stated downsides. Unsourced claims are opinions. Does this trace back to the problem statement?"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                # Check if writing to a plan file
                if echo "$FILE_PATH" | grep -qE '(docs/superpowers/plans/|docs/plans/)'; then
                    TRIGGER="plan_write"
                    L2_MSG="[Workflow Coach — DISCUSS] Does every plan step trace to the chosen approach? Flag scope creep. Did you document why this approach over alternatives?"
                fi
            fi
            ;;
        implement)
            if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                TRIGGER="source_edit"
                L2_MSG="[Workflow Coach — IMPLEMENT] Does this follow the plan? Would you be proud to have this reviewed? Tests written first?"
            elif [ "$TOOL_NAME" = "Bash" ]; then
                COMMAND=$(extract_bash_command)
                if echo "$COMMAND" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
                    TRIGGER="test_run"
                    L2_MSG="[Workflow Coach — IMPLEMENT] If tests fail, diagnose the root cause. Don't patch the test to make it pass. Don't skip tests for small changes."
                fi
            fi
            ;;
        review)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_review"
                L2_MSG="[Workflow Coach — REVIEW] Don't downgrade findings. Verify before reporting. Flag systemic issues, not just instances."
            fi
            ;;
        complete)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_complete"
                L2_MSG="[Workflow Coach — COMPLETE] Be specific about failures. Quantify fix effort. Recommend a next phase, don't just list options."
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'decisions\.md'; then
                    TRIGGER="decision_record_edit"
                    L2_MSG="[Workflow Coach — COMPLETE] Does the handover make sense to a stranger? Is tech debt visible? Does README match reality?"
                fi
            elif [ "$TOOL_NAME" = "Bash" ]; then
                BASH_CMD=$(extract_bash_command)
                if echo "$BASH_CMD" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
                    TRIGGER="test_run_complete"
                    L2_MSG="[Workflow Coach — COMPLETE] Be specific about validation failures. If a test fails, diagnose with quantified fix effort. Don't let failures be acknowledged without understanding consequences."
                fi
            fi
            ;;
    esac

    # Fire Layer 2 only if trigger matched and hasn't fired yet this phase
    if [ -n "$TRIGGER" ] && [ -n "$L2_MSG" ]; then
        if [ "$(has_coaching_fired "$TRIGGER")" != "true" ]; then
            add_coaching_fired "$TRIGGER"
            if [ -n "$MESSAGES" ]; then
                MESSAGES="$MESSAGES

$L2_MSG"
            else
                MESSAGES="$L2_MSG"
            fi
        fi
    fi

    # REVIEW Layer 2 trigger: "After presenting findings"
    # Fires when writing review findings to user (Write/Edit/MultiEdit to decision record in review phase)
    # This is separate from the agent_return_review trigger above
    if [ "$PHASE" = "review" ]; then
        if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
            if echo "$FILE_PATH" | grep -qE 'decisions\.md'; then
                FINDINGS_TRIGGER="findings_present"
                if [ "$(has_coaching_fired "$FINDINGS_TRIGGER")" != "true" ]; then
                    add_coaching_fired "$FINDINGS_TRIGGER"
                    FINDINGS_MSG="[Workflow Coach — REVIEW] Quantify the cost of not fixing. Don't soften with 'but this is minor.' State facts, let user decide."
                    if [ -n "$MESSAGES" ]; then
                        MESSAGES="$MESSAGES

$FINDINGS_MSG"
                    else
                        MESSAGES="$FINDINGS_MSG"
                    fi
                fi
            fi
        fi
    fi
fi

# ============================================================
# LAYER 3: Anti-laziness checks (fires on every match)
# ============================================================

L3_MSG=""

# Check 1: Short agent prompts (< 150 chars)
if [ "$TOOL_NAME" = "Agent" ]; then
    PROMPT_LEN=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
prompt = d.get('tool_input', {}).get('prompt', '')
print(len(prompt))
" 2>/dev/null || echo "999")
    if [ "$PROMPT_LEN" -lt 150 ]; then
        L3_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] Agent prompts must be detailed enough for autonomous work. Include: context, specific task, expected output format, constraints. Short prompts produce shallow results."
    fi
fi

# Check 2: Generic commit messages (< 30 chars)
if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(extract_bash_command)
    if echo "$COMMAND" | grep -qE 'git commit'; then
        COMMIT_MSG_LEN=$(echo "$COMMAND" | python3 -c "
import sys, re
cmd = sys.stdin.read()
# Match -m followed by a double-quoted or single-quoted string
# Use \x22 for double-quote and \x27 for single-quote to avoid shell quoting issues
m = re.search(r'-m\s+[\x22\x27](.*?)[\x22\x27]', cmd)
if m and '\$(cat' not in m.group(1) and '<<' not in m.group(1):
    print(len(m.group(1)))
else:
    # Try HEREDOC: look for EOF markers with \n as line separators
    m2 = re.search(r'EOF.*?\\\\n(.*?)\\\\n.*?EOF', cmd)
    if m2:
        first_line = m2.group(1).strip()
        print(len(first_line))
    else:
        print(999)
" 2>/dev/null || echo "999")
        if [ "$COMMIT_MSG_LEN" -lt 30 ]; then
            L3_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] Commit messages must explain why, not what. The diff shows what changed. Include context and reasoning."
        fi
    fi
fi

# Check 3: All findings downgraded (REVIEW phase, writing to decision record)
if [ "$PHASE" = "review" ] && { [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; }; then
    if echo "$FILE_PATH" | grep -qE 'decisions\.md'; then
        # Check if all findings are under Suggestions with no Critical or Warning entries
        ALL_SUGGESTIONS=$(python3 -c "
import sys
try:
    with open(sys.argv[1]) as f:
        content = f.read()
    in_review = False
    has_critical = False
    has_warning = False
    for line in content.split('\n'):
        if '## Review Findings' in line:
            in_review = True
        elif in_review and line.startswith('## ') and 'Review Findings' not in line:
            break
        elif in_review:
            if '### Critical' in line: has_critical = True
            if '### Warning' in line: has_warning = True
    # If we found the section but no critical/warning headings with content
    if in_review and not has_critical and not has_warning:
        print('true')
    else:
        print('false')
except Exception:
    print('false')
" "$FILE_PATH" 2>/dev/null || echo "false")
        if [ "$ALL_SUGGESTIONS" = "true" ]; then
            L3_MSG="[Workflow Coach — REVIEW] All findings were rated as suggestions. Review severity assessments. Are you downgrading to avoid friction?"
        fi
    fi
fi

# Check 4: save_observation quality (handover length + project field)
# Single python3 call extracts both text length and project presence
if echo "$TOOL_NAME" | grep -qE 'mcp.*save_observation'; then
    OBS_CHECK=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
text = ti.get('narrative', ti.get('text', ''))
project = ti.get('project', '')
print(f'{len(text)} {\"true\" if project else \"false\"}')
" 2>/dev/null || echo "999 true")
    OBS_LEN="${OBS_CHECK%% *}"
    HAS_PROJECT="${OBS_CHECK##* }"

    # 4a: Minimal handover (COMPLETE phase only)
    if [ "$PHASE" = "complete" ] && [ "$OBS_LEN" -lt 200 ]; then
        L3_MSG="[Workflow Coach — COMPLETE] The handover must be useful to someone who knows nothing about this session. Include: what was built, why these choices, gotchas, what's left."
    fi

    # 4b: Missing project field (any phase)
    if [ "$HAS_PROJECT" = "false" ]; then
        PROJ_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] save_observation called without project parameter. Always pass project to scope observations to this repo. Derive repo name: git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git\$/\1/' | sed 's/.*[:/]\([^/]*\)\$/\1/'"
        if [ -n "$L3_MSG" ]; then
            L3_MSG="$L3_MSG

$PROJ_MSG"
        else
            L3_MSG="$PROJ_MSG"
        fi
    fi
fi

# Check 5: Skipping research in DEFINE/DISCUSS (fires on every match per spec Layer 3)
# Moved from Layer 2 to Layer 3 because spec says this fires on every match, not once per phase
if [ "$PHASE" = "define" ] || [ "$PHASE" = "discuss" ]; then
    COUNTER=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print(d.get('coaching', {}).get('tool_calls_since_agent', 0))
except Exception: print(0)
" "$STATE_FILE" 2>/dev/null || echo "0")
    if [ "$COUNTER" -gt 10 ]; then
        SKIP_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] You're in a research phase but haven't dispatched background agents. Is this trivial enough to skip? State explicitly."
        if [ -n "$L3_MSG" ]; then
            L3_MSG="$L3_MSG

$SKIP_MSG"
        else
            L3_MSG="$SKIP_MSG"
        fi
    fi
fi

# Check 6: Options without recommendation (best-effort heuristic)
# The hook can't read Claude's text, but can detect AskUserQuestion tool
# following agent returns without an intervening recommendation signal.
# This is approximate — may produce false positives. Fires in any active phase.
if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
    # Check if any agent has returned in this phase (any agent_return_* trigger fired)
    AGENTS_RETURNED=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    fired = d.get('coaching', {}).get('layer2_fired', [])
    has_agent = any(t.startswith('agent_return') for t in fired)
    print('true' if has_agent else 'false')
except Exception: print('false')
" "$STATE_FILE" 2>/dev/null || echo "false")
    if [ "$AGENTS_RETURNED" = "true" ]; then
        L3_RECOMMEND="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] Don't just list options. State which you recommend and why. The user needs your professional judgment, not a menu."
        if [ -n "$L3_MSG" ]; then
            L3_MSG="$L3_MSG

$L3_RECOMMEND"
        else
            L3_MSG="$L3_RECOMMEND"
        fi
    fi
fi

# Check 7: No verify after code change (source edits without test run)
if [ "$PHASE" = "implement" ] || [ "$PHASE" = "review" ]; then
    if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
        if [ -n "$FILE_PATH" ] && ! echo "$FILE_PATH" | grep -qE '(test|spec|docs/|plans/|specs/|\.md$)'; then
            VERIFY_COUNT=$(get_pending_verify)
            VERIFY_COUNT=$((VERIFY_COUNT + 1))
            set_pending_verify "$VERIFY_COUNT"
            if [ "$VERIFY_COUNT" -ge 5 ]; then
                VERIFY_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] You've edited source code $VERIFY_COUNT times but haven't run tests or verification. Verify your changes before continuing."
                set_pending_verify 0
                if [ -n "$L3_MSG" ]; then
                    L3_MSG="$L3_MSG

$VERIFY_MSG"
                else
                    L3_MSG="$VERIFY_MSG"
                fi
            fi
        fi
    elif [ "$TOOL_NAME" = "Bash" ]; then
        BASH_CMD=$(extract_bash_command)
        if echo "$BASH_CMD" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
            set_pending_verify 0
        fi
    fi
fi

# Append Layer 3 message if any
if [ -n "$L3_MSG" ]; then
    if [ -n "$MESSAGES" ]; then
        MESSAGES="$MESSAGES

$L3_MSG"
    else
        MESSAGES="$L3_MSG"
    fi
fi

# ============================================================
# OUTPUT: Return combined messages
# ============================================================

if [ -n "$MESSAGES" ]; then
    MESSAGES="$MESSAGES" python3 -c "
import json, os
output = {
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'systemMessage': os.environ['MESSAGES']
    }
}
print(json.dumps(output))
"
fi
