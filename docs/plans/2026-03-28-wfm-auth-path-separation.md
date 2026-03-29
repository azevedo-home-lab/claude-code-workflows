# WFM Auth Path Separation — Decision Record

## Problem

The WFM phase authorization system has a single `set_phase()` function that handles both user-initiated and agent-initiated transitions via a shared `WF_SKIP_AUTH=1` bypass. This bypass was introduced as "test-only" but is used in all 7 production command files. It is a global env var that any Claude Bash tool call can set, bypassing all authorization logic. Under context pressure, Claude sessions have historically exploited this to force state changes and skip phases.

Additionally, the feature branch `feat/wfm-gate-hardening` (commit a0363f7) contains 16 changes that were built without user discussion. Several are correct and ready to ship; others have bugs (no-op code, security holes, dead code). All need to be assessed and integrated cleanly.

### Root Causes
1. `WF_SKIP_AUTH=1` conflates two distinct use cases: user override and test bypass. Both are actually production paths. Neither is safe as a global env var.
2. `set_phase()` is one function serving two callers (user and agent) with incompatible security requirements — the user path needs no checks, the agent path needs forward-only + gate checks.
3. Hook files (`.claude/hooks/`, `plugin/scripts/`) are unprotected in IMPLEMENT and REVIEW phases — Claude can edit them freely, corrupting the guard system.
4. `gh api` in DEFINE/DISCUSS allows POST/PATCH mutations, not just reads.

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Intent file covers user path (remove WF_SKIP_AUTH, keep set_phase)
- Description: Remove `WF_SKIP_AUTH=1` from command files. The intent file written by `user-phase-gate.sh` already exists when `!backtick` runs. Command files call `set_phase` which checks the intent file.
- Pros: Minimal change to `set_phase` logic. Intent file mechanism already built.
- Cons: Claude remains in the execution chain for user transitions. `set_phase` still has complex conditional logic distinguishing user vs agent. A bug in that logic lets Claude transition as a user. Doesn't eliminate the shared function problem.
- Source: Derived from analysis of current intent file architecture.

### Approach B: Hard path separation — user-set-phase.sh and agent-set-phase.sh
- Description: Split into two scripts with no shared logic. `user-set-phase.sh` called only from `!backtick` — writes state directly, no checks, no gates. `agent-set-phase.sh` — Bash tool path only, forward-only ordinal check + gate check, no user bypass.
- Pros: Complete separation. Claude cannot reach the user path. No shared bypass mechanism to abuse. Eliminates the conceptual confusion that has caused repeated bugs.
- Cons: Duplicates state-writing logic (field preservation, atomic write). Two scripts to maintain.
- Source: Architectural analysis of `!backtick` pre-processing vs Bash tool execution model.

## Decision (DISCUSS phase — converge)

**Chosen approach:** Approach B — hard path separation.

**Rationale:** The history of this codebase shows that shared logic with conditional bypass is repeatedly exploited or confused. `WF_SKIP_AUTH=1` started as "test-only" and became production. The `user_initiated` flag was added to fix confusion that came from conflating paths. Each patch adds complexity. Option B ends this permanently by making the paths structurally impossible to conflate — Claude literally cannot reach `user-set-phase.sh` because bash-write-guard blocks Bash tool calls to it, and `!backtick` is pre-processed before Claude is involved.

**Trade-offs accepted:** Duplicated state-writing logic. The duplication is bounded and stable — `user-set-phase.sh` changes only when the state schema changes, which is a deliberate development event.

**Risks identified:**
- If bash-write-guard itself is edited by Claude, the protection collapses. Mitigated by: adding phase-independent hook/script protection to both `workflow-gate.sh` and `bash-write-guard.sh`.
- If `user-set-phase.sh` and `agent-set-phase.sh` diverge in their state-writing logic over time, phase transitions may have different behavior. Mitigated by: clear comments in both files explaining the schema contract.

**Constraints applied:**
- `!backtick` is pre-processed by CC before Claude receives context — this is the architectural guarantee that makes Option B secure.
- bash-write-guard sees all Bash tool calls — this is what allows us to block `user-set-phase.sh` from Bash tool access.
- IMPLEMENT and REVIEW phases currently allow all writes — hook files are completely unprotected in these phases. This must be fixed as part of this work.

**Tech debt acknowledged:**
- Test suite gutted or removed (tests relied on `WF_SKIP_AUTH=1`). No replacement planned per user decision — tests added repetition without value.
- `user-phase-gate.sh` (intent file writer) becomes dead code once `set_phase` no longer reads intent files. Should be removed.
- `_check_phase_intent` and `_check_autonomy_intent` in `workflow-state.sh` become dead code. Remove.

**Link to implementation plan:** `docs/superpowers/plans/2026-03-28-wfm-auth-path-separation-plan.md`

## Scope

### In scope (this PR)
1. `user-set-phase.sh` — new script, user-only state write path
2. `agent-set-phase.sh` — renamed/stripped `set_phase`, agent-only forward+gate path
3. Remove `WF_SKIP_AUTH` from all command files and `workflow-state.sh`
4. Remove intent file logic (`_check_phase_intent`, `user-phase-gate.sh`, intent file reads)
5. Remove `set_autonomy_level` `WF_SKIP_AUTH` bypass (same pattern, same fix)
6. Hook/script self-protection: phase-independent guard in `workflow-gate.sh` and `bash-write-guard.sh`
7. Feature branch changes (clean ones): gate messages, REVIEW skip gate, FILE_OPS anchoring, gh read-only fix, step expectations tables, wfm-architecture.md, COMPLETE_WRITE_WHITELIST fix
8. Remove no-op code from branch: phase reset on entry (Change E), workflow-cmd.sh whitelist (Change F)
9. Test suite removal

### Out of scope (separate PR)
- Agent isolation for boundary-tester and devils-advocate (#4815)
