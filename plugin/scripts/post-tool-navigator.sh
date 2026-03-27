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
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL_NAME=""

# Helper: extract bash command from tool input (used by Layer 2/3 checks)
extract_bash_command() {
    echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo ""
}

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
            error)
                MESSAGES="[Workflow Coach — ERROR]
Workflow state is corrupted. All writes are blocked for safety.
To recover: run /off to reset the workflow, or manually delete .claude/state/workflow.json"
                ;;
        esac
        # Append auto-transition guidance if autonomy is "auto"
        AUTONOMY_LEVEL=$(get_autonomy_level)
        if [ "$AUTONOMY_LEVEL" = "auto" ] && [ -n "$MESSAGES" ]; then
            case "$PHASE" in
                implement)
                    MESSAGES="$MESSAGES
▶▶▶ Unattended (auto) — when all milestones are complete (plan_read, tests_passing, all_tasks_complete), you MUST invoke /review immediately. Do NOT commit, push, or do other work after milestones are done."
                    ;;
                review)
                    MESSAGES="$MESSAGES
▶▶▶ Unattended (auto) — when all review milestones are complete, you MUST invoke /complete immediately. Do NOT wait for user."
                    ;;
                complete)
                    MESSAGES="$MESSAGES
▶▶▶ Unattended (auto) — run the full completion pipeline. Stop only before git push (always requires confirmation)."
                    ;;
                *)
                    MESSAGES="$MESSAGES
▶▶▶ Unattended (auto) — when this phase's work is complete, proceed to the next phase without waiting for user confirmation."
                    ;;
            esac
        fi

        # Skip state update in error phase — state is corrupt, writes will fail
        if [ "$PHASE" != "error" ]; then
            set_message_shown
        fi
    fi
fi

# Early exit for tools that don't participate in Layer 2/3
# These tools don't need coaching evaluation or counter tracking
case "$TOOL_NAME" in
    Agent|Write|Edit|MultiEdit|NotebookEdit|Bash|AskUserQuestion) ;;
    mcp*save_observation|mcp*get_observations) ;;
    *) # Tool is irrelevant to coaching — output any Layer 1 message and exit
        if [ "$DEBUG_MODE" = "true" ]; then
            if [ -n "$MESSAGES" ]; then
                echo "[WFM DEBUG] PostToolUse ($TOOL_NAME) — Layer 1 only:" >&2
                echo "$MESSAGES" | sed 's/^/  /' >&2
            else
                echo "[WFM DEBUG] PostToolUse: $TOOL_NAME — no coaching (tool not tracked)" >&2
            fi
        fi
        if [ -n "$MESSAGES" ]; then
            jq -n --arg msg "$MESSAGES" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "systemMessage": $msg}}'
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
    PROMPT_LEN=$(echo "$INPUT" | jq -r '.tool_input.prompt // "" | length' 2>/dev/null) || PROMPT_LEN=999
    if [ "$PROMPT_LEN" -lt 150 ]; then
        L3_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] Agent prompts must be detailed enough for autonomous work. Include: context, specific task, expected output format, constraints. Short prompts produce shallow results."
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
            L3_MSG="[Workflow Coach — $(echo "$PHASE" | tr '[:lower:]' '[:upper:]')] Commit messages must explain why, not what. The diff shows what changed. Include context and reasoning."
        fi
    fi
fi

# Check 3: All findings downgraded (REVIEW phase, writing to decision record)
if [ "$PHASE" = "review" ] && { [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; }; then
    if echo "$FILE_PATH" | grep -qE 'decisions\.md'; then
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
            L3_MSG="[Workflow Coach — REVIEW] All findings were rated as suggestions. Review severity assessments. Are you downgrading to avoid friction?"
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
    COUNTER=$(jq -r '.coaching.tool_calls_since_agent // 0' "$STATE_FILE" 2>/dev/null) || COUNTER=0
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
    AGENTS_RETURNED=$(jq -r '[.coaching.layer2_fired[]? | select(startswith("agent_return"))] | if length > 0 then "true" else "false" end' "$STATE_FILE" 2>/dev/null) || AGENTS_RETURNED="false"
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

# Check 8: Stalled auto-transition — milestones complete but Claude hasn't moved to next phase
# Fires on every tool call when auto + milestones done, so Claude can't ignore it
AUTONOMY_LEVEL=$(get_autonomy_level 2>/dev/null) || AUTONOMY_LEVEL=""
if [ "$AUTONOMY_LEVEL" = "auto" ]; then
    STALL_MSG=""
    if [ "$PHASE" = "implement" ]; then
        IMPL_MISSING=$(_check_milestones "implement" "plan_read" "tests_passing" "all_tasks_complete" 2>/dev/null) || IMPL_MISSING="skip"
        if [ -z "$IMPL_MISSING" ]; then
            STALL_MSG="[Workflow Coach — IMPLEMENT] ⚠ ALL MILESTONES COMPLETE. You MUST transition to /review NOW. Do not commit, push, or do other work — invoke /review immediately. Auto autonomy requires completing the full pipeline: IMPLEMENT → REVIEW → COMPLETE."
        fi
    elif [ "$PHASE" = "review" ]; then
        REVIEW_DONE=true
        for field in verification_complete agents_dispatched findings_presented findings_acknowledged; do
            VAL=$(get_review_field "$field" 2>/dev/null) || VAL=""
            [ "$VAL" != "true" ] && REVIEW_DONE=false && break
        done
        if [ "$REVIEW_DONE" = "true" ]; then
            STALL_MSG="[Workflow Coach — REVIEW] ⚠ ALL REVIEW MILESTONES COMPLETE. You MUST transition to /complete NOW. Auto autonomy requires completing the full pipeline: REVIEW → COMPLETE."
        fi
    fi
    if [ -n "$STALL_MSG" ]; then
        if [ -n "$L3_MSG" ]; then
            L3_MSG="$L3_MSG

$STALL_MSG"
        else
            L3_MSG="$STALL_MSG"
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
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[WFM DEBUG] PostToolUse ($TOOL_NAME):" >&2
        echo "$MESSAGES" | sed 's/^/  /' >&2
    fi
    jq -n --arg msg "$MESSAGES" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "systemMessage": $msg}}'
else
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[WFM DEBUG] PostToolUse: $TOOL_NAME — no coaching triggered" >&2
    fi
fi
