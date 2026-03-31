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

# Coaching message directory — resolved from project root, not SCRIPT_DIR.
# SCRIPT_DIR resolves to .claude/hooks/ (symlink directory), not plugin/scripts/.
COACHING_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/plugin/coaching"

# Load a coaching message from file. Returns 1 if file missing (message skipped).
# $1: relative path under COACHING_DIR (e.g., "objectives/define.md")
# $2: optional PHASE value to substitute for {{PHASE}}
load_message() {
    local file="$COACHING_DIR/$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    local msg
    msg=$(cat "$file")
    if [ -n "${2:-}" ]; then
        msg=$(echo "$msg" | sed "s/{{PHASE}}/$2/g")
    fi
    echo "$msg"
}

# Read tool name and input from stdin (must happen before any early exits)
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL_NAME=""

# Helper: extract bash command from tool input (used by Layer 2/3 checks)
extract_bash_command() {
    echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo ""
}

# Skip coaching entirely for infrastructure Bash calls (phase transitions, state queries).
# PostToolUse output for these is swallowed by Claude Code, so L1 would waste
# its once-per-phase message on an invisible call.
if [ "$TOOL_NAME" = "Bash" ]; then
    _INFRA_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || _INFRA_CMD=""
    if echo "$_INFRA_CMD" | grep -qE '(user-set-phase\.sh|workflow-cmd\.sh|workflow-state\.sh)'; then
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Claude-mem observation ID tracking
# Extracts observation ID from save_observation (dict response) or
# get_observations (list response) and writes to workflow state.
# Runs before phase checks so IDs are captured regardless of phase.
# ---------------------------------------------------------------------------
if echo "$TOOL_NAME" | grep -qE 'mcp.*(save_observation|get_observations)'; then
    OBS_ID=$(echo "$INPUT" | jq -r '
    .tool_response.content[]?
    | select(.type == "text")
    | .text
    | try fromjson catch empty
    | if type == "array" then .[-1].id // empty
      elif type == "object" then .id // empty
      else empty end
' 2>/dev/null | tail -1) || OBS_ID=""
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

# Read debug flag once for all layers
DEBUG_MODE=$(get_debug)
source "$SCRIPT_DIR/debug-log.sh" "post-tool-navigator"

# Collect debug trace for systemMessage injection (show mode only).
# _trace() logs via _show (file + stderr) AND collects into DEBUG_TRACE
# so the trace can be prepended to systemMessage — the only user-visible
# channel for PostToolUse hooks in Claude Code.
DEBUG_TRACE=""
_trace() {
    _show "$1"
    if [ "$_WFM_DEBUG_LEVEL" = "show" ]; then
        if [ -n "$DEBUG_TRACE" ]; then
            DEBUG_TRACE="$DEBUG_TRACE
$1"
        else
            DEBUG_TRACE="$1"
        fi
    fi
}

# Compute uppercased phase once for all layers
PHASE_UPPER=$(echo "$PHASE" | tr '[:lower:]' '[:upper:]')

_TOOL_HEADER="[WFM coach] Tool: $TOOL_NAME (phase=$PHASE_UPPER)"
_log "$_TOOL_HEADER"

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
            error)
                ERR_MSG=$(load_message "objectives/error.md")
                if [ -n "$ERR_MSG" ]; then
                    MESSAGES="[Workflow Coach — ERROR]
$ERR_MSG"
                    _trace "[WFM coach] L1: objectives/error.md — ${ERR_MSG:0:80}..."
                fi
                ;;
            *)
                OBJ_MSG=$(load_message "objectives/$PHASE.md")
                if [ -n "$OBJ_MSG" ]; then
                    MESSAGES="[Workflow Coach — $PHASE_UPPER]
$OBJ_MSG"
                    _trace "[WFM coach] L1: objectives/$PHASE.md — ${OBJ_MSG:0:80}..."
                fi
                ;;
        esac
        # Append auto-transition guidance if autonomy is "auto"
        AUTONOMY_LEVEL=$(get_autonomy_level)
        if [ "$AUTONOMY_LEVEL" = "auto" ] && [ -n "$MESSAGES" ]; then
            AUTO_MSG=$(load_message "auto-transition/$PHASE.md")
            if [ -z "$AUTO_MSG" ]; then
                AUTO_MSG=$(load_message "auto-transition/default.md")
            fi
            if [ -n "$AUTO_MSG" ]; then
                MESSAGES="$MESSAGES
$AUTO_MSG"
            fi
        fi

        # Skip state update in error phase — state is corrupt, writes will fail
        if [ "$PHASE" != "error" ]; then
            set_message_shown
        fi
    else
        _log "[WFM coach] L1: already shown, skipped"
    fi
else
    _log "[WFM coach] L1: already shown, skipped"
fi

# Early exit for tools that don't participate in Layer 2/3
# These tools don't need coaching evaluation or counter tracking
case "$TOOL_NAME" in
    Agent|Write|Edit|MultiEdit|NotebookEdit|Bash|AskUserQuestion) ;;
    mcp*save_observation|mcp*get_observations) ;;
    *) # Tool is irrelevant to coaching — output any Layer 1 message and exit
        _log "[WFM coach] L2: no trigger matched (tool not tracked)"
        # Prepend tool header to DEBUG_TRACE only when there is coaching output
if [ -n "$DEBUG_TRACE" ]; then
    DEBUG_TRACE="$_TOOL_HEADER
$DEBUG_TRACE"
fi

if [ -n "$MESSAGES" ] || [ -n "$DEBUG_TRACE" ]; then
            # coaching → additionalContext (Claude-visible), debug trace → systemMessage (user-visible)
            if [ -n "$DEBUG_TRACE" ] && [ -n "$MESSAGES" ]; then
                jq -n --arg coach "$MESSAGES" --arg trace "$DEBUG_TRACE" \
                    '{"systemMessage": $trace, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $coach}}'
            elif [ -n "$DEBUG_TRACE" ]; then
                jq -n --arg trace "$DEBUG_TRACE" \
                    '{"systemMessage": $trace}'
            else
                jq -n --arg coach "$MESSAGES" \
                    '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $coach}}'
            fi
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
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || FILE_PATH=""
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
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
                    TRIGGER="plan_write_define"
                fi
            fi
            ;;
        discuss)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_discuss"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
                    TRIGGER="plan_write_discuss"
                fi
            fi
            ;;
        implement)
            if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                TRIGGER="source_edit_implement"
            elif [ "$TOOL_NAME" = "Bash" ]; then
                COMMAND=$(extract_bash_command)
                if echo "$COMMAND" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
                    TRIGGER="test_run_implement"
                fi
            fi
            ;;
        review)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_review"
            fi
            ;;
        complete)
            if [ "$TOOL_NAME" = "Agent" ]; then
                TRIGGER="agent_return_complete"
            elif [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
                if echo "$FILE_PATH" | grep -qE 'docs/'; then
                    TRIGGER="project_docs_edit_complete"
                fi
            elif [ "$TOOL_NAME" = "Bash" ]; then
                BASH_CMD=$(extract_bash_command)
                if echo "$BASH_CMD" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
                    TRIGGER="test_run_complete"
                fi
            fi
            ;;
    esac

    # Load nudge message and fire if trigger matched and hasn't fired yet this phase
    if [ -n "$TRIGGER" ]; then
        L2_MSG_BODY=$(load_message "nudges/$TRIGGER.md")
        if [ -n "$L2_MSG_BODY" ]; then
            L2_MSG="[Workflow Coach — $PHASE_UPPER] $L2_MSG_BODY"
        fi
    fi

    if [ -n "$TRIGGER" ] && [ -n "$L2_MSG" ]; then
        if [ "$(has_coaching_fired "$TRIGGER")" != "true" ]; then
            add_coaching_fired "$TRIGGER"
            if [ -n "$MESSAGES" ]; then
                MESSAGES="$MESSAGES

$L2_MSG"
            else
                MESSAGES="$L2_MSG"
            fi
            _trace "[WFM coach] L2: nudges/$TRIGGER.md — ${L2_MSG_BODY:0:80}..."
        else
            _log "[WFM coach] L2: trigger=$TRIGGER — already fired, skipped"
        fi
    elif [ -n "$TRIGGER" ]; then
        _log "[WFM coach] L2: trigger=$TRIGGER — no message file"
    else
        _log "[WFM coach] L2: no trigger matched"
    fi

    # REVIEW Layer 2 trigger: "After presenting findings"
    # Fires when writing review findings (Write/Edit/MultiEdit to spec in review phase)
    # This is separate from the agent_return_review trigger above
    if [ "$PHASE" = "review" ]; then
        if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
            if echo "$FILE_PATH" | grep -qE 'docs/specs/'; then
                FINDINGS_TRIGGER="findings_present_review"
                if [ "$(has_coaching_fired "$FINDINGS_TRIGGER")" != "true" ]; then
                    add_coaching_fired "$FINDINGS_TRIGGER"
                    FINDINGS_BODY=$(load_message "nudges/findings_present_review.md")
                    [ -n "$FINDINGS_BODY" ] && _trace "[WFM coach] L2: nudges/findings_present_review.md — ${FINDINGS_BODY:0:80}..."
                    if [ -n "$FINDINGS_BODY" ]; then
                        FINDINGS_MSG="[Workflow Coach — REVIEW] $FINDINGS_BODY"
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
fi

# ============================================================
# LAYER 3: Anti-laziness checks (fires on every match)
# ============================================================

L3_MSG=""

# Helper: append a check message to L3_MSG
_append_l3() {
    if [ -n "$L3_MSG" ]; then
        L3_MSG="$L3_MSG

$1"
    else
        L3_MSG="$1"
    fi
}

# Track which L3 checks fired for debug summary
_L3_SHORT_AGENT=false
_L3_GENERIC_COMMIT=false
_L3_ALL_DOWNGRADED=false
_L3_MINIMAL_HANDOVER=false
_L3_MISSING_PROJECT=false
_L3_SKIP_RESEARCH=false
_L3_OPTIONS_NO_REC=false
_L3_NO_VERIFY=false
_L3_STALLED=false
_L3_STEP_ORDER=false

# Check 1: Short agent prompts (< 150 chars)
if [ "$TOOL_NAME" = "Agent" ]; then
    PROMPT_LEN=$(echo "$INPUT" | jq -r '.tool_input.prompt // "" | length' 2>/dev/null) || PROMPT_LEN=999
    if [ "$PROMPT_LEN" -lt 150 ]; then
        CHECK_BODY=$(load_message "checks/short_agent_prompt.md" "$PHASE_UPPER")
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/short_agent_prompt.md — ${CHECK_BODY:0:80}..."
        _L3_SHORT_AGENT=true
    fi
fi

# Check 2: Generic commit messages (< 30 chars)
if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(extract_bash_command)
    if echo "$COMMAND" | grep -qE 'git commit'; then
        COMMIT_MSG_LEN=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null | {
    cmd=$(cat)
    # Try -m "..." or -m '...' (single-line, no HEREDOC)
    msg=$(echo "$cmd" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p; s/.*-m[[:space:]]*'"'"'\([^'"'"']*\)'"'"'.*/\1/p' | head -1)
    if [ -n "$msg" ] && ! echo "$msg" | grep -qE '(\$\(cat|<<)'; then
        echo "${#msg}"
    else
        # Try HEREDOC: normalise literal \n to real newlines, then extract first line after EOF
        first_line=$(echo "$cmd" | sed 's/\\n/\n/g' | awk 'found && !/^EOF/{print; exit} /EOF/{found=1}' | head -1)
        if [ -n "$first_line" ]; then
            echo "${#first_line}"
        else
            echo "999"
        fi
    fi
}) || COMMIT_MSG_LEN=999
        if [ "$COMMIT_MSG_LEN" -lt 30 ]; then
            CHECK_BODY=$(load_message "checks/generic_commit.md" "$PHASE_UPPER")
            [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
            [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/generic_commit.md — ${CHECK_BODY:0:80}..."
            _L3_GENERIC_COMMIT=true
        fi
    fi
fi

# Check 3: All findings downgraded (REVIEW phase, writing to spec)
if [ "$PHASE" = "review" ] && { [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; }; then
    if echo "$FILE_PATH" | grep -qE 'docs/specs/'; then
        # Check if all findings are under Suggestions with no Critical or Warning entries
        ALL_SUGGESTIONS="false"
        if [ -f "$FILE_PATH" ]; then
            IN_REVIEW=false
            HAS_CRITICAL=false
            HAS_WARNING=false
            while IFS= read -r line; do
                if echo "$line" | grep -q '## Review Findings'; then IN_REVIEW=true; fi
                if [ "$IN_REVIEW" = "true" ] && echo "$line" | grep -qE '^## ' && ! echo "$line" | grep -q 'Review Findings'; then break; fi
                if [ "$IN_REVIEW" = "true" ]; then
                    if echo "$line" | grep -q '### Critical'; then HAS_CRITICAL=true; fi
                    if echo "$line" | grep -q '### Warning'; then HAS_WARNING=true; fi
                fi
            done < "$FILE_PATH"
            if [ "$IN_REVIEW" = "true" ] && [ "$HAS_CRITICAL" = "false" ] && [ "$HAS_WARNING" = "false" ]; then
                ALL_SUGGESTIONS="true"
            fi
        fi
        if [ "$ALL_SUGGESTIONS" = "true" ]; then
            CHECK_BODY=$(load_message "checks/all_findings_downgraded.md")
            [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — REVIEW] $CHECK_BODY"
            [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/all_findings_downgraded.md — ${CHECK_BODY:0:80}..."
            _L3_ALL_DOWNGRADED=true
        fi
    fi
fi

# Check 4: save_observation quality (handover length + project field)
# Single jq call extracts both text length and project presence
if echo "$TOOL_NAME" | grep -qE 'mcp.*save_observation'; then
    OBS_CHECK=$(echo "$INPUT" | jq -r '
        (.tool_input.narrative // .tool_input.text // "") as $t |
        (.tool_input.project // "") as $p |
        "\($t | length) \(if $p != "" then "true" else "false" end)"
    ' 2>/dev/null) || OBS_CHECK="999 true"
    OBS_LEN="${OBS_CHECK%% *}"
    HAS_PROJECT="${OBS_CHECK##* }"

    # 4a: Minimal handover (COMPLETE phase only)
    if [ "$PHASE" = "complete" ] && [ "$OBS_LEN" -lt 200 ]; then
        CHECK_BODY=$(load_message "checks/minimal_handover.md")
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — COMPLETE] $CHECK_BODY"
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/minimal_handover.md — ${CHECK_BODY:0:80}..."
        _L3_MINIMAL_HANDOVER=true
    fi

    # 4b: Missing project field (any phase)
    if [ "$HAS_PROJECT" = "false" ]; then
        CHECK_BODY=$(load_message "checks/missing_project_field.md" "$PHASE_UPPER")
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/missing_project_field.md — ${CHECK_BODY:0:80}..."
        _L3_MISSING_PROJECT=true
    fi
fi

# Check 5: Skipping research in DEFINE/DISCUSS (fires on every match per spec Layer 3)
# Moved from Layer 2 to Layer 3 because spec says this fires on every match, not once per phase
if [ "$PHASE" = "define" ] || [ "$PHASE" = "discuss" ]; then
    COUNTER=$(jq -r '.coaching.tool_calls_since_agent // 0' "$STATE_FILE" 2>/dev/null) || COUNTER=0
    if [ "$COUNTER" -gt 10 ]; then
        CHECK_BODY=$(load_message "checks/skipping_research.md" "$PHASE_UPPER")
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/skipping_research.md — ${CHECK_BODY:0:80}..."
        _L3_SKIP_RESEARCH=true
    fi
fi

# Check 6: Options without recommendation (best-effort heuristic)
# The hook can't read Claude's text, but can detect AskUserQuestion tool
# following agent returns without an intervening recommendation signal.
# This is approximate — may produce false positives. Fires in any active phase.
if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
    # Check if any agent has returned in this phase (any agent_return_* trigger fired)
    AGENTS_RETURNED=$(jq -r '[.coaching.layer2_fired[]? | select(startswith("agent_return"))] | if length > 0 then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || AGENTS_RETURNED="false"
    if [ "$AGENTS_RETURNED" = "true" ]; then
        CHECK_BODY=$(load_message "checks/options_without_recommendation.md" "$PHASE_UPPER")
        [ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
        [ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/options_without_recommendation.md — ${CHECK_BODY:0:80}..."
        _L3_OPTIONS_NO_REC=true
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
                # Load file as gate (if deleted, message suppressed); count stays inline
                if load_message "checks/no_verify_after_edits.md" >/dev/null 2>&1; then
                    _VERIFY_BODY="You've edited source code $VERIFY_COUNT times but haven't run tests or verification. Verify your changes before continuing."
                    VERIFY_MSG="[Workflow Coach — $PHASE_UPPER] $_VERIFY_BODY"
                    _append_l3 "$VERIFY_MSG"
                    _trace "[WFM coach] L3: checks/no_verify_after_edits.md — ${_VERIFY_BODY:0:80}..."
                    _L3_NO_VERIFY=true
                fi
                set_pending_verify 0
            fi
        fi
    elif [ "$TOOL_NAME" = "Bash" ]; then
        BASH_CMD=$(extract_bash_command)
        if echo "$BASH_CMD" | grep -qE '(pytest|npm test|cargo test|make test|run-tests|jest|vitest|go test)'; then
            set_pending_verify 0
        fi
    fi
fi

# Check 8: Stalled auto-transition — milestones complete but Claude hasn't moved to next phase
# Fires on every tool call when auto + milestones done, so Claude can't ignore it
AUTONOMY_LEVEL=$(get_autonomy_level 2>/dev/null) || AUTONOMY_LEVEL=""
if [ "$AUTONOMY_LEVEL" = "auto" ]; then
    STALL_FIRE=false
    if [ "$PHASE" = "implement" ]; then
        IMPL_MISSING=$(_check_milestones "implement" "plan_written" "plan_read" "tests_passing" "all_tasks_complete" 2>/dev/null) || IMPL_MISSING="skip"
        [ -z "$IMPL_MISSING" ] && STALL_FIRE=true
    elif [ "$PHASE" = "discuss" ]; then
        DISCUSS_DONE=true
        for field in problem_confirmed research_done approach_selected; do
            VAL=$(get_discuss_field "$field" 2>/dev/null) || VAL=""
            [ "$VAL" != "true" ] && DISCUSS_DONE=false && break
        done
        [ "$DISCUSS_DONE" = "true" ] && STALL_FIRE=true
    elif [ "$PHASE" = "review" ]; then
        REVIEW_DONE=true
        for field in verification_complete agents_dispatched findings_presented findings_acknowledged; do
            VAL=$(get_review_field "$field" 2>/dev/null) || VAL=""
            [ "$VAL" != "true" ] && REVIEW_DONE=false && break
        done
        [ "$REVIEW_DONE" = "true" ] && STALL_FIRE=true
    fi
    if [ "$STALL_FIRE" = "true" ]; then
        STALL_BODY=$(load_message "checks/stalled_auto_transition/$PHASE.md")
        if [ -n "$STALL_BODY" ]; then
            _append_l3 "[Workflow Coach — $PHASE_UPPER] $STALL_BODY"
            _trace "[WFM coach] L3: checks/stalled_auto_transition/$PHASE.md — ${STALL_BODY:0:80}..."
            _L3_STALLED=true
        fi
    fi
fi

# Check 9: Within-phase step ordering — fires on every match (all autonomy modes)
# Helper: load step ordering message and set STEP_MSG
_load_step() {
    local body
    body=$(load_message "checks/step_ordering/$1.md")
    if [ -n "$body" ]; then
        STEP_MSG="[Workflow Coach — $PHASE_UPPER] $body"
        STEP_FILE="checks/step_ordering/$1.md"
        STEP_BODY="$body"
    fi
}

STEP_MSG=""
STEP_FILE=""
STEP_BODY=""

if [ "$PHASE" = "complete" ]; then
    if [ "$(_section_exists "completion")" = "true" ]; then
        if [ "$TOOL_NAME" = "Bash" ]; then
            BASH_CMD=$(extract_bash_command)
            if echo "$BASH_CMD" | grep -qE 'git[[:space:]]+commit'; then
                if [ "$(get_completion_field "results_presented")" != "true" ]; then
                    _load_step "complete_commit_before_validation"
                elif [ "$(get_completion_field "docs_checked")" != "true" ]; then
                    _load_step "complete_commit_before_docs"
                fi
            fi
            if echo "$BASH_CMD" | grep -qE 'git[[:space:]]+push'; then
                if [ "$(get_completion_field "committed")" != "true" ]; then
                    _load_step "complete_push_before_commit"
                fi
            fi
        fi
        if echo "$TOOL_NAME" | grep -qE 'mcp.*save_observation'; then
            if [ "$(get_completion_field "tech_debt_audited")" != "true" ]; then
                _load_step "complete_handover_before_audit"
            fi
        fi
        # Pipeline-abandoned: pushed but later steps not done
        if [ "$(get_completion_field "pushed")" = "true" ] && [ "$(get_completion_field "handover_saved")" != "true" ]; then
            _load_step "complete_pipeline_incomplete"
        fi
    fi
elif [ "$PHASE" = "discuss" ]; then
    if [ "$(_section_exists "discuss")" = "true" ]; then
        if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
            if echo "$FILE_PATH" | grep -qE 'docs/plans/'; then
                if [ "$(get_discuss_field "research_done")" != "true" ]; then
                    _load_step "discuss_plan_before_research"
                elif [ "$(get_discuss_field "approach_selected")" != "true" ]; then
                    _load_step "discuss_plan_before_approach"
                fi
            fi
        fi
    fi
elif [ "$PHASE" = "implement" ]; then
    if [ "$(_section_exists "implement")" = "true" ]; then
        if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
            if [ -n "$FILE_PATH" ] && ! echo "$FILE_PATH" | grep -qE '(test|spec|docs/|plans/|specs/|\.md$)'; then
                if [ "$(get_implement_field "plan_written")" != "true" ]; then
                    _load_step "implement_code_before_plan"
                elif [ "$(get_implement_field "plan_read")" != "true" ]; then
                    _load_step "implement_code_before_plan_read"
                fi
            fi
        fi
        # Pipeline-abandoned: tasks complete but tests not run
        if [ "$(get_implement_field "all_tasks_complete")" = "true" ] && [ "$(get_implement_field "tests_passing")" != "true" ]; then
            _load_step "implement_pipeline_incomplete"
        fi
    fi
elif [ "$PHASE" = "review" ]; then
    if [ "$(_section_exists "review")" = "true" ]; then
        if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
            if echo "$FILE_PATH" | grep -qE 'docs/specs/'; then
                if [ "$(get_review_field "agents_dispatched")" != "true" ]; then
                    _load_step "review_findings_before_agents"
                fi
            fi
        fi
        if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
            if [ "$(get_review_field "findings_presented")" != "true" ]; then
                _load_step "review_ack_before_findings"
            fi
        fi
        # Pipeline-abandoned: agents dispatched but findings not presented
        if [ "$(get_review_field "agents_dispatched")" = "true" ] && [ "$(get_review_field "findings_presented")" != "true" ]; then
            _load_step "review_pipeline_incomplete"
        fi
    fi
fi

if [ -n "$STEP_MSG" ]; then
    _append_l3 "$STEP_MSG"
    _trace "[WFM coach] L3: $STEP_FILE — ${STEP_BODY:0:80}..."
    _L3_STEP_ORDER=true
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

# Debug summary for L3 checks
_log "[WFM coach] L3: short_agent=$_L3_SHORT_AGENT, generic_commit=$_L3_GENERIC_COMMIT, all_downgraded=$_L3_ALL_DOWNGRADED, minimal_handover=$_L3_MINIMAL_HANDOVER, missing_project=$_L3_MISSING_PROJECT, skip_research=$_L3_SKIP_RESEARCH, options_no_rec=$_L3_OPTIONS_NO_REC, no_verify=$_L3_NO_VERIFY, stalled=$_L3_STALLED, step_order=$_L3_STEP_ORDER"

# Counter summary
_COACH_COUNTER=$(jq -r '.coaching.tool_calls_since_agent // 0' "$STATE_FILE" 2>/dev/null) || _COACH_COUNTER="?"
_COACH_L2_FIRED=$(jq -r '.coaching.layer2_fired // [] | join(",")' "$STATE_FILE" 2>/dev/null) || _COACH_L2_FIRED="?"
_log "[WFM coach] Counters: calls_since_agent=$_COACH_COUNTER, layer2_fired=[$_COACH_L2_FIRED]"

# ============================================================
# OUTPUT: Return combined messages
# ============================================================

# Prepend tool header to DEBUG_TRACE only when there is coaching output
if [ -n "$DEBUG_TRACE" ]; then
    DEBUG_TRACE="$_TOOL_HEADER
$DEBUG_TRACE"
fi

if [ -n "$MESSAGES" ] || [ -n "$DEBUG_TRACE" ]; then
    _log "[WFM coach] Message sent to Claude:"
    echo "$MESSAGES" | while IFS= read -r line; do _log "  $line"; done
    # coaching → additionalContext (Claude-visible), debug trace → systemMessage (user-visible)
    if [ -n "$DEBUG_TRACE" ] && [ -n "$MESSAGES" ]; then
        jq -n --arg coach "$MESSAGES" --arg trace "$DEBUG_TRACE" \
            '{"systemMessage": $trace, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $coach}}'
    elif [ -n "$DEBUG_TRACE" ]; then
        jq -n --arg trace "$DEBUG_TRACE" \
            '{"systemMessage": $trace}'
    else
        jq -n --arg coach "$MESSAGES" \
            '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $coach}}'
    fi
fi
