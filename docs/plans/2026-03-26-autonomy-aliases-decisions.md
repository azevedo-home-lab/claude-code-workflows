# Decision Record: Autonomy Off Redesign, /complete Push, /wf: Aliases

## Problem (DISCUSS phase)

### Problem Statement
Three related issues degrade the WFM user experience:

1. **Autonomy `off` is unusable during implementation** (#4228, #4194.1): The hooks block ALL writes regardless of phase when autonomy is `off`, making it a "pause button" instead of a supervised mode. Users who want step-by-step pair programming can't use `off` during IMPLEMENT/REVIEW phases — they're forced to use `ask` or `auto`, losing granular control.

2. **`/complete` doesn't push** (#4194.2): The COMPLETE phase commits but never pushes to remote. Users must manually push after `/off`, defeating the purpose of the completion pipeline.

3. **Command discoverability** (#4197): WFM commands lack namespace consistency. Users typing `/wf:` can't tab-complete to discover all WFM commands. Additionally, managing tracked observations requires knowing internal function names — no slash commands exist for this.

### Who is affected
- All WFM users who want supervised mode (autonomy `off`)
- All WFM users completing work (push friction)
- New WFM users discovering available commands

### Measurable Outcomes
1. Autonomy `off` allows writes in IMPLEMENT/REVIEW phases (same gate as `ask`), with step-by-step instruction in command files
2. `/complete` Step 5 pushes to remote (with confirmation at all autonomy levels)
3. All 8 WFM commands have `/wf:` prefixed aliases
4. 3 observation management commands exist: `/wf:obs-read`, `/wf:obs-track`, `/wf:obs-untrack`
5. All existing tests pass; new tests cover changed behavior

### Scope
- **In scope:** Hook behavior changes, command file updates, symlink aliases, observation commands, test updates, documentation updates
- **Out of scope:** `/wf:debug` (#4234), status line issues (#4194.3-5), ECC integration (#3793)

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Hooks identical for off/ask, discipline via instructions
- Remove autonomy `off` write blocks from both hook guards
- Remove `EnterPlanMode` from `autonomy.md`
- Add `off`-specific step-by-step instructions to all 5 phase command files
- **Pros:** Clean separation — hooks enforce phase gates, instructions enforce granularity. Minimal hook changes. `off` becomes genuinely usable.
- **Cons:** Step-by-step pausing is not hook-enforced — it's instruction-following. A misbehaving model could ignore it.
- **Source:** Analysis of current hook code and open issue #4228

### Approach B: Keep EnterPlanMode for off
- Same write permissions as `ask`, but Claude starts in plan mode
- User manually exits plan mode for each step
- **Pros:** Some enforcement via plan mode
- **Cons:** `EnterPlanMode` blocks ALL writes including whitelisted ones (specs, plans, state files). Counterproductive. Plan mode is a blunt instrument not designed for step-gating.
- **Source:** Current implementation analysis

### Approach C: Per-edit hook confirmation
- Hook emits `askUser` decision instead of `allow` for each write
- **Pros:** True per-edit enforcement
- **Cons:** Claude Code hook API may not support `askUser` decision type. Per-edit is too noisy (not per-step). Major hook rewrite required.
- **Source:** Claude Code hook documentation review

## Decision (DISCUSS phase — converge)
- **Chosen approach:** A — Hooks identical for off/ask, discipline via instructions
- **Rationale:** Clean architecture. Hooks enforce hard phase gates (security boundary). Instructions enforce workflow discipline (soft boundary). This matches the existing pattern — hooks enforce "what's possible", commands enforce "how to behave."
- **Trade-offs accepted:** Step-by-step pausing at `off` is not hook-enforced. A model that ignores instructions could skip pauses. This is acceptable because most WFM discipline is instruction-based.
- **Risks identified:** Tests that assert `off` blocks writes will need updating. Documentation across 5+ files must be synchronized.
- **Constraints applied:** Claude Code hook API only supports allow/deny decisions. No `askUser` or `confirm` decision type exists.
- **Tech debt acknowledged:** Autonomy level descriptions are now duplicated across README, architecture.md, hooks.md, and 5 command files. Drift risk is accepted (same as existing duplication noted in #4217).
- **Link to implementation plan:** `docs/superpowers/plans/2026-03-26-autonomy-aliases-plan.md`

## Outcome Verification (COMPLETE phase)
- [x] Outcome 1: Autonomy off allows writes in IMPLEMENT/REVIEW — PASS — tests verify allows in IMPLEMENT, blocks in DISCUSS
- [x] Outcome 2: /complete pushes with confirmation — PASS — explicit "Push to Remote" sub-section added
- [x] Outcome 3: All 8 WFM commands have /wf: aliases — PASS — 8 symlinks, 16 tests pass
- [x] Outcome 4: 3 observation commands exist — PASS — wf:obs-read, wf:obs-track, wf:obs-untrack created
- [x] Outcome 5: All tests pass, new tests added — PASS — 713 passed (up from 694), 0 failures
- **Unresolved items:** setup.sh test for command symlink creation not implemented (deferred — low risk, setup.sh manually tested)
- **Tech debt incurred:** Autonomy description duplication across 8+ files (accepted, same as prior sessions)
- **Discovery:** CC permission mode (acceptEdits) vs WFM autonomy gap — tracked as #4259
