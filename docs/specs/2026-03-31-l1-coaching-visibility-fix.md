# Spec: L1 Coaching Visibility Fix (Issue #33)

## Problem

After `agent_set_phase("complete")`, L1 coaching output may not appear to the user even with debug `show` mode active. The `PostToolUse:Read` system-reminder tag was not visible in the conversation, suggesting the coaching message either failed to deliver or was not emitted correctly.

**Root cause:** The output logic in `post-tool-navigator.sh` is duplicated between two exit paths (early exit at line 265 and main exit at line 772). The early exit path — which handles Read, Grep, Glob, and other non-tracked tools — has inconsistent indentation (lines 260-263 are flush-left inside a case arm) and is missing the `_log` call present in the main path. This makes the two paths diverge silently and complicates debugging.

**Secondary issue:** The `_trace()` messages for L1 don't confirm delivery channel, making it hard for users in `show` mode to verify coaching reached Claude.

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Fix early exit indentation only
- Cosmetic fix to indentation at lines 260-263
- Pros: Minimal change, lowest risk
- Cons: Doesn't address observability gap or duplicated output logic

### Approach B: Fix early exit + enrich debug trace + extract helper (chosen)
- Fix indentation, enrich `_trace()` with delivery confirmation, extract `_emit_output()` to eliminate duplication
- Pros: Fixes bug, improves observability, DRYs the output logic
- Cons: Slightly larger change (~20 lines added, ~30 removed)

### Approach C: Single output path refactor
- Delete early exit entirely, gate L2 internally
- Pros: Fully linear control flow
- Cons: Performance regression for frequent tools (Read/Grep/Glob), risky refactor of 787-line script

## Decision (DISCUSS phase — converge)

- **Chosen approach:** B — Fix early exit + enrich debug trace + extract helper
- **Rationale:** Fixes the actual bug and observability gap while preserving the early exit performance optimization. The `_emit_output()` helper eliminates the duplicated output block, reducing future divergence risk.
- **Trade-offs accepted:** `_emit_output()` reads globals rather than parameters, consistent with the script's existing pattern but not independently testable.
- **Risks identified:** The helper function must produce identical JSON output to the current paths. Any regression breaks coaching delivery for all tools.
- **Constraints applied:** Single file change (`plugin/scripts/post-tool-navigator.sh`). No state schema changes.
- **Tech debt acknowledged:** The early exit path remains a separate control flow branch. Approach C would eliminate it but at too high a cost for this fix.

## Changes

### 1. Extract `_emit_output()` helper (~line 118, after `_trace()`)

```bash
_emit_output() {
    if [ -n "$DEBUG_TRACE" ]; then
        DEBUG_TRACE="$_TOOL_HEADER
$DEBUG_TRACE"
    fi
    if [ -n "$MESSAGES" ] || [ -n "$DEBUG_TRACE" ]; then
        _log "[WFM coach] Message sent to Claude:"
        echo "$MESSAGES" | while IFS= read -r line; do _log "  $line"; done
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
}
```

### 2. Enrich L1 `_trace()` messages with delivery confirmation

- Error phase (line 216): `_trace "[WFM coach] L1 FIRED: objectives/error.md → additionalContext"`
- Normal phases (line 224): `_trace "[WFM coach] L1 FIRED: objectives/$PHASE.md → additionalContext"`

### 3. Replace early exit output block (lines 259-278)

Replace the duplicated output logic and misindented prepend block with:

```bash
    *) # Tool is irrelevant to coaching — output any Layer 1 message and exit
        _log "[WFM coach] L2: no trigger matched (tool not tracked)"
        _emit_output
        exit 0
        ;;
```

### 4. Replace main exit output block (lines 766-786)

Replace the duplicated output logic and prepend block with:

```bash
_emit_output
```

## Verification

- Enable debug show mode: `.claude/hooks/workflow-cmd.sh set_debug "show"`
- Transition to a new phase
- Execute a Read tool call
- Confirm `systemMessage` contains `L1 FIRED: objectives/<phase>.md → additionalContext`
- Confirm `additionalContext` contains the coaching objective message
- Verify tracked tools (Write, Edit, Bash) still receive L2/L3 coaching
