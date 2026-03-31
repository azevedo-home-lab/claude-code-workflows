# Spec: Coaching Visibility Fix (Issue #33)

## Problem

With debug `show` mode active, coaching messages (L1 objectives, L2 nudges, L3 checks) are invisible to the user. The user sees zero WFM coach output despite coaching firing correctly and reaching Claude via `additionalContext`.

**Root cause:** Coaching messages (`MESSAGES`) only go to `additionalContext` (Claude-visible). They never go to `systemMessage` (user-visible). The `_trace()` function populates `DEBUG_TRACE` → `systemMessage`, but:

1. **L1 trace is metadata only** — `_trace()` logs `"L1: objectives/discuss.md — first 80 chars..."`, not the full coaching message. Even in show mode, the user sees a truncated trace line, not the actual objective.
2. **L2/L3 never call `_trace()` for their content** — L2 nudges and L3 checks append to `MESSAGES` only. No trace is emitted, so `DEBUG_TRACE` stays empty and no `systemMessage` is produced.
3. **Result:** In show mode, the user sees nothing. The coaching reaches Claude but the user has no evidence it fired.

**Secondary issues:**
- The output logic is duplicated between two exit paths (early exit at line 265, main exit at line 772), with inconsistent indentation and a missing `_log` call in the early exit path.
- The `_trace()` messages don't confirm delivery channel.

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

- **Chosen approach:** B — Fix early exit + show coaching in systemMessage + extract helper
- **Rationale:** Fixes the actual bug (coaching invisible to user in show mode) by routing `MESSAGES` to `systemMessage` when show mode is on. The `_emit_output()` helper eliminates the duplicated output block, reducing future divergence risk. Early exit performance optimization preserved.
- **Trade-offs accepted:** `_emit_output()` reads globals rather than parameters, consistent with the script's existing pattern but not independently testable. Show mode output is more verbose (full coaching text in `systemMessage`).
- **Risks identified:** The helper function must produce identical JSON output to the current paths when show mode is off. Any regression breaks coaching delivery for all tools.
- **Constraints applied:** Single file change (`plugin/scripts/post-tool-navigator.sh`). No state schema changes.
- **Tech debt acknowledged:** The early exit path remains a separate control flow branch. Approach C would eliminate it but at too high a cost for this fix.

## Changes

### 1. Extract `_emit_output()` helper (~line 118, after `_trace()`)

In show mode, include the coaching content in `systemMessage` so the user can see what coaching fired. In normal mode, behavior is unchanged — coaching goes to `additionalContext` only.

```bash
_emit_output() {
    if [ -n "$DEBUG_TRACE" ]; then
        DEBUG_TRACE="$_TOOL_HEADER
$DEBUG_TRACE"
    fi

    # In show mode, include coaching messages in systemMessage for user visibility
    local user_msg="$DEBUG_TRACE"
    if [ "$_WFM_DEBUG_LEVEL" = "show" ] && [ -n "$MESSAGES" ]; then
        if [ -n "$user_msg" ]; then
            user_msg="$user_msg
$MESSAGES"
        else
            user_msg="$_TOOL_HEADER
$MESSAGES"
        fi
    fi

    if [ -n "$MESSAGES" ] || [ -n "$user_msg" ]; then
        _log "[WFM coach] Message sent to Claude:"
        echo "$MESSAGES" | while IFS= read -r line; do _log "  $line"; done
        if [ -n "$user_msg" ] && [ -n "$MESSAGES" ]; then
            jq -n --arg coach "$MESSAGES" --arg trace "$user_msg" \
                '{"systemMessage": $trace, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $coach}}'
        elif [ -n "$user_msg" ]; then
            jq -n --arg trace "$user_msg" \
                '{"systemMessage": $trace}'
        else
            jq -n --arg coach "$MESSAGES" \
                '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $coach}}'
        fi
    fi
}
```

**Key change:** When `_WFM_DEBUG_LEVEL=show`, `MESSAGES` content is appended to `user_msg` (which becomes `systemMessage`). This means:
- **show mode off:** `MESSAGES` → `additionalContext` only (Claude sees it, user doesn't). No behavior change.
- **show mode on, with trace:** `DEBUG_TRACE` + `MESSAGES` → `systemMessage` (user sees both trace and coaching). `MESSAGES` → `additionalContext` (Claude sees coaching).
- **show mode on, no trace:** `_TOOL_HEADER` + `MESSAGES` → `systemMessage` (user sees coaching with tool context). `MESSAGES` → `additionalContext` (Claude sees coaching).

### 2. Enrich L1 `_trace()` messages with delivery confirmation

- Error phase (line 216): `_trace "[WFM coach] L1 FIRED: objectives/error.md"`
- Normal phases (line 224): `_trace "[WFM coach] L1 FIRED: objectives/$PHASE.md"`

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
- Transition to a new phase (e.g., `/implement`)
- Execute a Read tool call
- **User sees:** `systemMessage` with `[WFM coach] Tool: Read (phase=IMPLEMENT)` header and the full L1 objective text
- **Claude sees:** `additionalContext` with the coaching objective (unchanged)
- Transition again, execute a Write tool call
- **User sees:** L2 nudge content in `systemMessage` when it fires
- Disable show mode: `.claude/hooks/workflow-cmd.sh set_debug "off"`
- Verify no `systemMessage` output — coaching goes to `additionalContext` only (no user-visible change from current behavior)
