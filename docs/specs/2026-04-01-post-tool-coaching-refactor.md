# Post-Tool Coaching Refactor — L1 Visibility + Architecture

> Closes #36 (L1 coaching not visible to user in debug:show mode)
> Closes #38 (post-tool-coaching.sh architecture refactor)

## Problem

`post-tool-coaching.sh` (264 lines) has accumulated structural debt that causes recurring bugs:

1. **L1 coaching invisible to user in debug:show mode.** Phase transitions run via `user-set-phase.sh` in `!backtick` context. Stderr from `!backtick` is swallowed by Claude Code — it never reaches the user's terminal. The PostToolUse hook (`post-tool-coaching.sh`) — the only channel that can emit `systemMessage` (user-visible) — has a blanket `exit 0` on lines 59-63 that skips all infrastructure Bash calls, including phase transitions. Result: no `systemMessage` is ever emitted after a phase transition.

2. **L1 coaching delivered through a separate path.** `user-set-phase.sh` and `agent-set-phase.sh` emit L1 coaching via stdout from `_emit_phase_coaching()`. This text reaches Claude as raw command output but bypasses the PostToolUse `_emit_output()` function — the single place where `additionalContext` (Claude) and `systemMessage` (user) are split. This means debug:show cannot mirror what Claude receives, because the paths diverge.

3. **No tool classification abstraction.** "Is this infrastructure?" is checked with a grep on line 61. "Does this tool participate in coaching?" is checked with a case statement on line 176. These are two expressions of the same question answered in different places, making it easy to add a new case to one and miss the other.

4. **Stale reference.** Line 61 matches `workflow-state.sh` which was removed during the v2.0/v2.1 refactor.

5. **Unnecessary `_trace`/`DEBUG_TRACE` split.** Two separate accumulation variables (`MESSAGES` and `DEBUG_TRACE`) both end up in `systemMessage` under the same `show` mode condition. This is needless complexity — in show mode, the user should see what Claude sees, through one variable, split at the boundary.

## Design Principles

### Single delivery path
All coaching content (L1, L2, L3) flows through `_emit_output()`. No layer has a separate stdout/stderr delivery path. `_emit_output()` is the only function that produces the PostToolUse JSON output.

### Late split
Content is assembled into `MESSAGES` by all layers. At the boundary, `_emit_output()` splits once:
- `MESSAGES` → `additionalContext` → Claude receives it (always)
- `MESSAGES` → `systemMessage` → User sees it (show mode only)

Same content, two channels, one split point. This makes it impossible for debug output and Claude's input to diverge.

### Tool classification as first-class concept
A single `_classify_tool` function categorizes every tool call. The main script dispatches by classification. No scattered grep/case checks.

### Security invariant
`user-set-phase.sh` remains user-only. Called exclusively from `!backtick` commands, blocked by `pre-tool-bash-guard.sh` for Claude. This refactor changes coaching delivery, not the security model.

## Approach: Layered Dispatch Architecture

### Tool Classifications

| Category | Meaning | Examples |
|---|---|---|
| `phase-transition` | User or agent phase change | `user-set-phase.sh`, `workflow-cmd.sh agent_set_phase` |
| `infrastructure-query` | Internal plumbing calls | `workflow-cmd.sh get_phase`, `workflow-cmd.sh get_plan_path` |
| `coaching-participant` | Tools L2/L3 care about | `Agent`, `Write`, `Edit`, `Bash` (non-infra), etc. |
| `irrelevant` | Tools L2/L3 don't track | `Read`, `Grep`, `Glob`, `Skill`, etc. |

Classification for Bash tool:
- Command contains `user-set-phase.sh` or `agent_set_phase` → `phase-transition`
- Command contains `workflow-cmd.sh` (but not `agent_set_phase`) → `infrastructure-query`
- Otherwise → `coaching-participant`

Non-Bash tools: existing case statement mapped to `coaching-participant` or `irrelevant`.

### Dispatch Table

| Classification | Obs tracking | L1 | L2/L3 | Counter increment | `_emit_output` |
|---|---|---|---|---|---|
| `phase-transition` | yes | yes | no | no | yes |
| `infrastructure-query` | yes | no | no | no | yes |
| `coaching-participant` | yes | no | yes | yes | yes |
| `irrelevant` | yes | no | no | no | yes |

### Main Script Flow (~80 lines)

```
1. Setup: read stdin, extract TOOL_NAME/INPUT, source dependencies
2. Observation tracking (always, before phase checks)
3. Phase/state guards: no state → exit, off → exit
4. Classify: tool_type = _classify_tool(TOOL_NAME, INPUT)
5. Dispatch:
   - phase-transition → _deliver_l1
   - infrastructure-query → skip to emit
   - coaching-participant → _run_l2, L3 checks
   - irrelevant → skip to emit
6. _emit_output (always — late split)
```

### L1 Delivery via PostToolUse

`_deliver_l1` (in `l1/post-tool-delivery.sh`):
1. Check `message_shown` — if `true`, L1 already delivered, skip
2. Read `AUTONOMY` from state via `get_autonomy_level` (from `workflow-facade.sh`)
3. Call `_emit_phase_coaching "$PHASE" "$AUTONOMY"` to load coaching content
4. Append output to `MESSAGES`
5. Set `message_shown = true` in state

This reuses the existing `_emit_phase_coaching` content loader from `l1/phase-coaching.sh`.

### Simplified `_emit_output`

```bash
_emit_output() {
    if [ -z "$MESSAGES" ]; then return; fi

    if [ "$_WFM_DEBUG_LEVEL" = "show" ]; then
        jq -n --arg m "$MESSAGES" \
            '{"systemMessage": $m, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $m}}'
    else
        jq -n --arg m "$MESSAGES" \
            '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $m}}'
    fi
}
```

No `DEBUG_TRACE`. No `_trace`. One variable, two channels.

## File Changes

### Created

| File | Purpose | ~Lines |
|---|---|---|
| `plugin/scripts/infrastructure/tool-classifier.sh` | `_classify_tool` function | 35 |
| `plugin/scripts/l1/post-tool-delivery.sh` | `_deliver_l1` function | 40 |

### Modified

| File | Change |
|---|---|
| `plugin/scripts/post-tool-coaching.sh` | Rewrite: 264 → ~80 lines. Dispatch-only. |
| `plugin/scripts/user-set-phase.sh` | Remove `source l1/phase-coaching.sh` (line 22) and `_emit_phase_coaching` call (line 85). |
| `plugin/scripts/agent-set-phase.sh` | Remove `source l1/phase-coaching.sh` (line 18) and `_emit_phase_coaching` call (line 81). |
| `plugin/scripts/l1/phase-coaching.sh` | Remove stderr debug line (line 71). Pure content loader. |

### Deleted

- `_trace` function and `DEBUG_TRACE` variable (from `post-tool-coaching.sh`)
- Stale `workflow-state.sh` grep match (from old line 61)
- L1 stdout emission from `user-set-phase.sh` and `agent-set-phase.sh`
- stderr debug line from `l1/phase-coaching.sh`

### Unchanged

- `plugin/scripts/l2/standards-reinforcement.sh` — sourced as-is
- `plugin/scripts/l2/coaching-state.sh` — counter API unchanged
- `plugin/scripts/l3/coaching-runner.sh` — throttle engine unchanged
- `plugin/scripts/l3/*.sh` (individual checks) — sourced as-is
- `plugin/scripts/infrastructure/debug-log.sh` — `_log`/`_show` unchanged
- `plugin/scripts/workflow-facade.sh` — unchanged
- `plugin/scripts/infrastructure/patterns.sh` — unchanged
- Guard system (`pre-tool-bash-guard.sh`, `pre-tool-write-gate.sh`) — unchanged

## Out of Scope

- L2/L3 logic changes
- Guard system changes
- Debug logging infrastructure changes
- Phase transition security model changes

## Risks

1. **L1 delivery timing.** Today L1 fires during `user-set-phase.sh` execution (synchronous). In the new design, L1 fires in the PostToolUse hook after the Bash tool completes. If the hook fails or is skipped, L1 is lost. Mitigation: `message_shown` stays `false` so L1 retries on the next tool call.

2. **`additionalContext` reliability.** Research confirms `additionalContext` works for native tools (Bash, Read, Write, Edit, Grep, Glob) on current Claude Code versions. MCP tools have a known bug (#24788). Our coaching system only fires on native tools, so this is not a concern.

3. **Counter distortion regression.** The old `exit 0` prevented counter increment for infrastructure calls. The new design explicitly skips counter increment for `phase-transition` and `infrastructure-query` classifications. This is tested by verifying the dispatch table.

## Verification

1. Run `/discuss` in `debug:show` mode — user should see full L1 coaching text in terminal via `systemMessage`
2. Run `/discuss` in `debug:off` mode — user should see only `Phase set to discuss. Re-evaluate.` from stdout
3. Run `workflow-cmd.sh get_phase` — should produce no coaching output, no counter increment
4. L2/L3 coaching should continue to work on `Write`/`Edit`/`Agent` tool calls as before
5. `agent_set_phase` in auto mode should deliver L1 through the same PostToolUse path
