# Autonomy Levels for Workflow Manager

## Problem

The Workflow Manager currently has a binary permission model: either the user manually approves everything, or `settings.local.json` grants blanket access for unattended operation. There's no middle ground. Users need granular control over how much autonomy Claude has during a workflow session — from fully supervised research to completely unattended execution.

## Outcomes

1. User can select one of three autonomy levels via a command
2. The selected level is visible in the status line as a play symbol (▶, ▶▶, ▶▶▶)
3. Level 1 (▶): Local research only — no file writes, no web, no Bash writes
4. Level 2 (▶▶): Semi-autonomous — writes allowed per phase rules, stops at phase transitions
5. Level 3 (▶▶▶): Fully unattended — auto-transitions, auto-commits, stops only for user input (DISCUSS/DEFINE) and git push
6. Level can be changed mid-session
7. Default is Level 2 on session start
8. Git push always requires user confirmation regardless of level

## Constraints

- Must work with Claude Code's native permission modes (plan, default, acceptEdits)
- Must integrate with existing hook architecture (workflow-gate.sh, bash-write-guard.sh)
- Status line changes must be backward-compatible with existing phase display
- Autonomy level is orthogonal to workflow phase — both dimensions coexist

## Outcome Verification (COMPLETE phase)

- [x] Outcome 1: `/autonomy` command selects level — PASS — `autonomy.md` calls `set_autonomy_level`
- [x] Outcome 2: Status line shows ▶/▶▶/▶▶▶ — PASS — `statusline.sh` reads `autonomy_level`, 5 tests pass
- [x] Outcome 3: Level 1 blocks all writes — PASS — both hooks deny at Level 1, 4 tests pass
- [x] Outcome 4: Level 2/3 phase-gated — PASS — fall through to existing logic, 5 tests pass
- [x] Outcome 5: Level 3 auto-transitions via coaching — PASS — Layer 1 coaching appends guidance, 2 tests pass
- [x] Outcome 6: Level changeable mid-session — PASS — `set_autonomy_level` has no phase restriction
- [x] Outcome 7: Default Level 2 on session start — PASS — `set_phase` initializes to 2 on OFF→active
- [x] Outcome 8: Git push always requires confirmation — PASS — command doc and coaching text both specify
- [x] Outcome 9: Only user can change level — PASS — command doc prohibits Claude from invoking
- Plan deliverables: 24/24 PASS
- Tests: 237/237 PASS (0 failures)
- **Unresolved items:** Level 1 WebFetch/WebSearch blocking relies on CC plan mode only (no hook fallback — known gap documented in spec)
- **Tech debt incurred:** DRY violation noted in spec review — resolved with `emit_deny` helper. Remaining: `get_autonomy_level` default-2 behavior means the OFF→active initialization guard in `set_phase` only fires on first-ever call (cosmetic, documented with comment)
