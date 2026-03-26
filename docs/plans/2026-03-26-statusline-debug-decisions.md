# Decision Record — Status Line Improvements & Debug Command

**Date:** 2026-03-26
**Issues:** #4194.4, #4194.5, #4234
**Spec:** `docs/superpowers/specs/2026-03-26-statusline-debug-design.md`

## Problem

Three usability gaps:
1. No CC version visible in status line — users can't see their Claude Code version at a glance.
2. Yellow context bar unreadable on white terminal backgrounds.
3. Hook coaching messages invisible to users — system is opaque and undebuggable.

### Outcomes
- CC version displayed as first status bar element
- Context bar readable on both light and dark terminals
- Users can toggle visibility of all hook messages via `/wf:debug on|off`

## Approaches Considered (DISCUSS phase — diverge)

### Feature 1: CC Version
Single approach — read `version` from CC session JSON. No alternatives needed.

### Feature 2: Context Bar Colors
Single approach — replace yellow with blue, adjust thresholds. User specified: green <30%, blue 30-60%, red >=60%.

### Feature 3: Debug Command

#### Approach A: PostToolUse dual output via stderr (chosen)
- Hook scripts echo debug messages to stderr (visible to user) alongside existing systemMessage JSON (visible to Claude)
- Debug state stored as boolean in workflow.json
- **Pros:** Output appears in the conversation where the user is looking. Simple implementation.
- **Cons:** Every hook reads one extra JSON field when debug is on (negligible).

#### Approach B: Separate debug log file
- Write all decisions to `~/.claude/state/wfm-debug.log`, user reads via `tail -f`
- **Pros:** No risk of interfering with hook JSON protocol.
- **Cons:** Requires second terminal. User misses real-time context. File rotation complexity.

## Decision (DISCUSS phase — converge)

- **Chosen approach:** Approach A for debug, direct implementation for version and colors
- **Rationale:** All three features are small, well-scoped, and independent. Debug via stderr keeps output where the user is looking.
- **Trade-offs accepted:** Debug flag cleared on OFF (users re-enable per cycle). No debug granularity (all-or-nothing).
- **Risks identified:** stderr behavior in CC hooks needs verification — if CC doesn't show hook stderr, we pivot to Approach B.
- **Constraints applied:** CC session JSON schema provides version field. Terminal color codes must work on both light and dark themes.
- **Tech debt acknowledged:** None introduced.

## Review Findings (REVIEW phase)

**5 review agents dispatched, 4 false positives filtered, 11 unique confirmed findings.**

### Fixed (this session)
- [QUAL] Redundant `if [ -f STATE_FILE ]` guard in workflow-gate.sh and bash-write-guard.sh — removed
- [QUAL] Vestigial `get_phase` call in wf:debug.md Step 1 — removed
- [QUAL] `get_debug` called before OFF-phase exit — moved after exit for efficiency
- [ARCH/GOV] Missing temp dir cleanup in debug indicator tests — added `rm -rf`

### Pre-existing tech debt (not introduced by this change)
- [SEC] `_update_state` jq filter interpolation is fragile against future callers (workflow-state.sh:47-56)
- [HYG] `pushed` completion field written but never checked by exit gate (complete.md:257)
- [HYG] `_plugin_version` function duplicated in test suite (tests/run-tests.sh:2372-2384)

### Dismissed as false positive
- SEC: `WF_SKIP_AUTH=1` is a production mechanism (used by 8 command files), not a test backdoor
- GOV: `allowed-tools: Bash` in wf:debug.md is intentionally different from other commands
- CQ: Missing tests for error paths is a coverage suggestion, not a code defect
- ARCH: Version bump without plan step is an informational process note
