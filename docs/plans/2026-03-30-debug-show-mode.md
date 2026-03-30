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
