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

**Root cause (verified by code trace):** The output routing in `post-tool-coaching.sh` originally sent coaching content only to `additionalContext` (Claude-visible) with a separate `DEBUG_TRACE` variable for `systemMessage` (user-visible). The coaching text never reached the user.

**Resolution (PR #36/#38):** Eliminated `_trace()`/`DEBUG_TRACE`. Now `_emit_output()` uses a single `MESSAGES` variable with late split: `additionalContext` (Claude, always) + `systemMessage` (user, debug:show only). Same content, two channels.

**Evidence sources:**
- `systemMessage` is user-visible only: Official docs at code.claude.com/docs/en/hooks, GitHub issue #4084
- `additionalContext` is Claude-visible only (and unreliable for built-in tools): GitHub issue #18427 (closed NOT_PLANNED)
- Observation #5623 in claude-mem has full evidence chain

### Sub-problems

#### 1. Coaching messages not visible to users
Originally, `_trace()` calls logged diagnostic strings but not content. Users saw "FIRED" but not what fired.

**Fix (superseded):** Originally enriched `_trace()` calls. Now resolved by eliminating `_trace()` entirely — `MESSAGES` flows directly to `systemMessage` in show mode via `_emit_output()` late split.

#### 2. Debug trace is too noisy
Every tool call dumped L3 boolean summary and counter state to `systemMessage`.

**Fix (superseded):** Originally downgraded noisy lines from `_trace()` to `_log()`. Now resolved by eliminating `_trace()`/`DEBUG_TRACE` entirely. All diagnostic output uses `_log()` (file only). User sees only `MESSAGES` content in show mode.

#### 3. L1 coaching fires on infrastructure Bash calls
Phase transition commands trigger PostToolUse hooks. L1 fired on these invisible calls, consuming the once-per-phase message.

**Fix (superseded):** Originally used a blanket `exit 0` for infrastructure commands. Now resolved by `_classify_tool()` which categorizes tool calls as `phase-transition`, `infrastructure-query`, `coaching-participant`, or `irrelevant`. Phase transitions deliver L1 via `_deliver_l1()`. Infrastructure queries skip coaching and counters.

#### 4. Show coaching content to user in debug:show
In debug:show mode, the user now sees the full coaching text (same content Claude receives) via `systemMessage`. This is achieved by the late split in `_emit_output()` — no separate trace mechanism needed.

### Approaches Considered

#### Approach A: Enrich `_trace()` at fire sites (originally chosen)
At each fire site, enrich `_trace()` with file path + preview. Downgrade noise to `_log()`.

#### Approach B: Build trace summary at output time (originally rejected)
Accumulate structured data, build summary at output.

#### Approach C: Eliminate `_trace()`/`DEBUG_TRACE`, use late split (final implementation)
Remove `_trace()` entirely. All coaching content flows into single `MESSAGES` variable. `_emit_output()` splits at the boundary: `additionalContext` for Claude (always), `systemMessage` for user (show mode only). Diagnostic logging uses `_log()` (file only).

- **Pro:** Single source of truth — debug:show mirrors exactly what Claude receives. Impossible for debug output and Claude's input to diverge.
- **Con:** Required full refactor of post-tool-coaching.sh (264→211 lines). Completed in PR #36/#38.

### Decision
- **Chosen approach:** C — Eliminate `_trace()`/`DEBUG_TRACE`, use late split (implemented in PR #36/#38)
- **Rationale:** Approach A was implemented first but proved fragile — separate debug and coaching paths could diverge. Approach C makes divergence impossible by using one variable and one split point.
- **Trade-offs accepted:** Full refactor of post-tool-coaching.sh required
- **Risks identified:** None remaining — architecture is simpler and has fewer moving parts

### Implementation Steps (superseded by PR #36/#38)

The original steps below described the Approach A implementation (enrich `_trace()` at fire sites). This was superseded by the full refactor in PR #36/#38 which implemented Approach C (eliminate the separate `_trace`/debug-trace mechanism, use late split).

**Current architecture (post-refactor):**
1. `_classify_tool()` categorizes each tool call
2. `phase-transition` → `_deliver_l1()` loads coaching into `MESSAGES`
3. `coaching-participant` → L2/L3 append to `MESSAGES`
4. `_emit_output()` late split: `MESSAGES` → `additionalContext` (Claude) + `systemMessage` (user in show mode)

See `docs/specs/2026-04-01-post-tool-coaching-refactor.md` for the full design.

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
- [QUAL] String concatenation in _trace — resolved: `_trace()` eliminated entirely
- [ARCH] "already shown" traces _trace vs _log — resolved: `_trace()` eliminated, all diagnostics use `_log()`
- [ARCH] Version bump not in plan tasks — acceptable operational step
- [GOV] COACHING_DIR pwd fallback silent — added early exit if directory missing
- [HYG] Plan spec checkboxes unchecked — plan is a reference doc, checkboxes not tracked
- [HYG] Abandoned worktrees — managed by Claude Code, not cleaned up

### Pre-existing tech debt (not introduced by this PR)
- Inline commit message length extraction (Check 2) is opaque — candidate for helper function
- No automated test suite for hook scripts — all verification is manual
- Direct jq calls on STATE_FILE in 3 locations — need accessor functions in state-io.sh
