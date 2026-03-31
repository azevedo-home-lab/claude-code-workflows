# Debug Show Mode — Full WFM Observability

## Problem

WFM has 10 distinct components that execute during a session, but most are invisible to the user. The current debug mode (`/debug on`) only writes to log files in `/tmp/` that require a separate terminal to monitor. Users cannot see the full picture of what WFM is doing — gate decisions, state mutations, coaching evaluation, phase transitions, agent dispatch context, and skill resolution are all hidden.

### Measurable Outcomes
- All 10 WFM components emit observable output when debug show mode is enabled
- Debug output appears inline in the conversation (hook stdout), not just in log files
- Backwards compatibility: existing `true/false` debug state maps to `log/off`

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Hook-only instrumentation (8/10 coverage)
- Instrument all 7 hooks to emit to stdout in show mode
- Leaves agent dispatch context and skill registry lookups uncovered (Claude-side behaviors)
- Pros: No new commands, minimal change
- Cons: Incomplete — 2 components remain invisible

### Approach B: Hook instrumentation + coaching nudge (10/10 soft coverage)
- Same as A, plus a coaching nudge telling Claude to announce agent/skill lookups
- Pros: Lightweight, uses existing infrastructure
- Cons: Relies on Claude compliance, not mechanically enforced

### Approach C: Hook instrumentation + wrapper commands (10/10 hard coverage)
- Same as A, plus two new workflow-cmd.sh commands: `dispatch_agent` and `resolve_skill`
- Claude calls these before dispatching agents or invoking skills
- Commands log the lookup and return the resolved content/path
- Pros: All 10 components observable through same mechanism, consistent
- Cons: Claude must call wrapper commands (mitigated by coaching fallback)

## Decision (DISCUSS phase — converge)

- **Chosen approach:** C — Three-level debug (`off/log/show`) + wrapper commands
- **Rationale:** Single consistent mechanism (hook stdout) for all 10 components. No observability gaps.
- **Trade-offs accepted:** Verbose output in show mode; two new commands Claude must remember to call
- **Risks identified:** Claude might forget wrapper commands — mitigated by coaching nudge as fallback in show mode
- **Constraints applied:** Must use existing hook stdout mechanism (already displayed by Claude Code)
- **Tech debt acknowledged:** None — clean extension of existing debug infrastructure

## Bugfix: Issue #29 — Hook Output Errors (RESOLVED)

### Problem 1: PreToolUse `_emit_debug_allow()` emits invalid JSON — FIXED (commit 9db30ea)
### Problem 2: PostToolUse JSON structure is wrong — FIXED (commit 9db30ea)

---

## Issue #31 — Coaching Visibility Improvements (post-revert)

### Problem

After fixing #29, debug show mode works but the output is **noisy and missing the most important information**. Users see internal evaluation variables on every tool call but never see the actual coaching messages that get sent to Claude.

**Root cause (verified by code trace):** The output routing in `post-tool-navigator.sh` sends:
- `MESSAGES` (coaching content) → `additionalContext` → **user-invisible** (Claude Code channel for AI context injection)
- `DEBUG_TRACE` (diagnostic booleans) → `systemMessage` → **user-visible** (the only PostToolUse channel rendered in terminal)

The coaching message text is never passed to `_trace()`, so it never enters `DEBUG_TRACE`, so it never reaches `systemMessage`, so the user never sees it.

**Evidence sources:**
- `systemMessage` is user-visible only: Official docs at code.claude.com/docs/en/hooks, GitHub issue #4084
- `additionalContext` is Claude-visible only (and unreliable for built-in tools): GitHub issue #18427 (closed NOT_PLANNED)
- Observation #5623 in claude-mem has full evidence chain

### Sub-problems

#### 1. Coaching messages not visible to users
`_trace()` calls at fire sites log diagnostic strings ("L1: phase entry — FIRED") but not the file path or content preview. Users see "FIRED" but not what fired or what it said.

**Fix:** Enrich `_trace()` calls at each fire site to include file path + truncated content preview.

#### 2. Debug trace is too noisy
Every tool call dumps L3 boolean summary and counter state:
```
[WFM coach] L3: short_agent=false, generic_commit=false, all_downgraded=false, ...
[WFM coach] Counters: calls_since_agent=8, layer2_fired=[]
```

**Fix:** Downgrade L3 boolean dump (line 632) and counter summary (line 637) from `_trace()` to `_log()`. These go to file only, not to `systemMessage`. Only trace when something actually fires.

**Constraint:** `DEBUG_TRACE` must not become empty when coaching fires — if both `DEBUG_TRACE` and `MESSAGES` are empty, the hook correctly produces no JSON output. But if coaching fires, `_trace()` at the fire site ensures `DEBUG_TRACE` is non-empty, so JSON is always produced.

#### 3. L1 coaching fires on infrastructure Bash calls
Phase transition commands (`user-set-phase.sh`, `workflow-cmd.sh`, `workflow-state.sh`) trigger PostToolUse hooks. L1 fires on these invisible calls, consuming the once-per-phase message. Claude Code swallows the `systemMessage` for these calls.

**Fix:** After extracting `TOOL_NAME` and bash command, detect infrastructure commands and skip coaching evaluation entirely. Counter increment and other state management still runs.

#### 4. Show coaching file + content preview when coaching fires
Target user-visible output format:
```
[WFM coach] L1: objectives/review.md — Objective: Independent multi-agent...
[WFM coach] L2: nudges/source_edit_implement.md — You've made code changes...
[WFM coach] L3: checks/short_agent_prompt.md — Agent prompts under 150...
```

This is achieved by sub-problem 1's fix — enriching `_trace()` at fire sites.

### Approaches Considered

#### Approach A: Enrich `_trace()` at fire sites (CHOSEN)
At each L1/L2/L3 fire site, change the `_trace()` call to include file path + truncated preview. Downgrade noise lines to `_log()`.

- **Pro:** Minimal change, each fire site controls its own trace, stays close to current design
- **Con:** Truncation logic repeated at ~6 fire sites (acceptable for bash)

#### Approach B: Build trace summary at output time
Keep `_trace()` calls lean, accumulate structured data in variables, build user-visible summary at the output section (lines 643-656).

- **Pro:** Single formatting location
- **Con:** More refactoring in the exact area where 7 previous commits broke things. Requires passing structured data through new variables.

### Decision
- **Chosen approach:** A — Enrich `_trace()` at fire sites
- **Rationale:** Conservative fix. Previous attempt failed from too much refactoring. A changes ~6 individual lines, each independently verifiable.
- **Trade-offs accepted:** Truncation logic duplicated at 6 sites
- **Risks identified:** Must verify JSON output after each change (lesson from failed attempt)

### Implementation Steps

Each step must be verified before proceeding to the next (syntax check + JSON output test).

#### Step 1: Infrastructure skip for Bash calls
After `TOOL_NAME` extraction (~line 42), detect infrastructure commands:
```bash
if [ "$TOOL_NAME" = "Bash" ]; then
    BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || BASH_CMD=""
    if echo "$BASH_CMD" | grep -qE '(user-set-phase\.sh|workflow-cmd\.sh|workflow-state\.sh)'; then
        exit 0  # Skip coaching entirely for infrastructure
    fi
fi
```
Place this after stdin read but before phase/state checks so it's the earliest possible exit.

**Verify:** `echo '{"tool_name":"Bash","tool_input":{"command":"workflow-cmd.sh get_phase"}}' | bash plugin/scripts/post-tool-navigator.sh` → no output, exit 0.

#### Step 2: Downgrade noise lines to `_log()`
Change line 632 (`_trace` for L3 booleans) and line 637 (`_trace` for counters) to `_log()`:
```bash
_log "[WFM coach] L3: short_agent=$_L3_SHORT_AGENT, ..."
_log "[WFM coach] Counters: calls_since_agent=$_COACH_COUNTER, ..."
```

**Verify:** JSON output still produced when coaching fires (L1 `_trace` at fire site ensures `DEBUG_TRACE` non-empty). When nothing fires and debug=show, tool header line still produces output.

#### Step 3: Enrich L1 fire trace with file path + preview
At line 161, change:
```bash
_trace "[WFM coach] L1: phase entry — FIRED"
```
To:
```bash
_trace "[WFM coach] L1: objectives/$PHASE.md — ${OBJ_MSG:0:80}..."
```
(For error phase, use `objectives/error.md` instead.)

**Verify:** Phase transition → first tool call → `PostToolUse:Bash says: [WFM coach] L1: objectives/implement.md — Objective: ...`

#### Step 4: Enrich L2 fire trace with file path + preview
At line 289, change:
```bash
_trace "[WFM coach] L2: trigger=$TRIGGER — FIRED"
```
To:
```bash
_trace "[WFM coach] L2: nudges/$TRIGGER.md — ${L2_MSG_BODY:0:80}..."
```

**Verify:** Trigger an L2 condition → `PostToolUse:Edit says: [WFM coach] L2: nudges/source_edit_implement.md — ...`

#### Step 5: Enrich L3 fire traces with file path + preview
At each `_append_l3` call site (checks 1-9), add a corresponding `_trace()` with the check file name and preview. Example for Check 1 (short agent prompt, line 359):
```bash
[ -n "$CHECK_BODY" ] && _append_l3 "[Workflow Coach — $PHASE_UPPER] $CHECK_BODY"
[ -n "$CHECK_BODY" ] && _trace "[WFM coach] L3: checks/short_agent_prompt.md — ${CHECK_BODY:0:80}..."
```

**Verify:** Trigger an L3 check → trace shows file + preview.

#### Step 6: Suppress "Message sent to Claude:" noise
Line 644 (`_trace "[WFM coach] Message sent to Claude:"`) and line 645 (echo loop) — downgrade to `_log()` or remove. The user already sees what fired from the enriched traces.

### Verification Plan (after all steps)

```bash
# 1. Syntax check
bash -n plugin/scripts/post-tool-navigator.sh

# 2. Infrastructure skip
echo '{"tool_name":"Bash","tool_input":{"command":"workflow-cmd.sh get_phase"}}' | bash plugin/scripts/post-tool-navigator.sh
# Expected: no output

# 3. Normal tool call (debug show, no coaching fires)
# Expected: [WFM coach] Tool: Bash (phase=IMPLEMENT) — minimal, no boolean dump

# 4. L1 fire (first tool after phase transition)
# Expected: [WFM coach] L1: objectives/implement.md — <preview>

# 5. JSON validity
echo '{"tool_name":"Bash","tool_input":{"command":"echo test"}}' | bash plugin/scripts/post-tool-navigator.sh | jq .
# Expected: valid JSON with systemMessage
```

## Review Findings

### Critical (must fix before merge)
None

### Warnings (fixed)
- [QUAL] Infrastructure skip regex matched substrings — anchored to command start `(^|/)`
- [QUAL] Duplicated L2 trigger block for findings_present_review — unified into main dispatch
- [QUAL] Check 7 hardcoded message body — now uses coaching file content
- [QUAL] Direct jq on STATE_FILE bypasses accessor — TODO added (no accessor exists yet)
- [ARCH] Infrastructure skip spec claimed counter state preserved — spec updated to match reality
- [ARCH] findings_present_review trace unguarded — fixed by unifying into main L2 block
- [GOV] Implementation plan in docs/specs/ — moved to docs/plans/
- [GOV] gh issue close without confirmation gate — will require user approval in COMPLETE phase
- [HYG] L1 "already shown, skipped" misleading when tool not eligible — fixed trace message
- [HYG] Plan doc referenced wrong coaching file path — fixed example

### Suggestions (fixed or noted)
- [QUAL] Repeated Write/Edit/MultiEdit checks — extracted IS_WRITE_TOOL helper
- [QUAL] String concatenation in _trace — pre-existing pattern, safe under current usage
- [ARCH] "already shown" traces _trace vs _log — resolved: downgraded to _log
- [ARCH] Version bump not in plan tasks — acceptable operational step
- [GOV] COACHING_DIR pwd fallback silent — added early exit if directory missing
- [HYG] Plan spec checkboxes unchecked — plan is a reference doc, checkboxes not tracked
- [HYG] Abandoned worktrees — managed by Claude Code, not cleaned up

### Pre-existing tech debt (not introduced by this PR)
- Inline commit message length extraction (Check 2) is opaque — candidate for helper function
- No automated test suite for hook scripts — all verification is manual
- Direct jq calls on STATE_FILE in 3 locations — need accessor functions in workflow-state.sh
