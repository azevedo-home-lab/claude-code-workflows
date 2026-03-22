# Autonomy Levels — Design Specification

## Problem

The Workflow Manager currently has a binary permission model: either the user manually approves everything, or `settings.local.json` grants blanket access for unattended operation. There's no middle ground. Users need granular control over how much autonomy Claude has during a workflow session — from fully supervised research to completely unattended execution.

## Outcomes

1. User can select one of three autonomy levels via a `/autonomy` command
2. The selected level is visible in the status line as a play symbol (`▶`, `▶▶`, `▶▶▶`)
3. Level 1 (`▶`): Local research only — no file writes, no web, no Bash writes
4. Level 2 (`▶▶`): Semi-autonomous — writes allowed per phase rules, stops at phase transitions
5. Level 3 (`▶▶▶`): Fully unattended — auto-transitions, auto-commits, stops only for user input (DISCUSS/DEFINE) and git push
6. Level can be changed mid-session
7. Default is Level 2 on session start (set when workflow phase first transitions from OFF)
8. Git push always requires user confirmation regardless of level
9. Only the user can change the autonomy level — Claude can suggest but not execute level changes

## Constraints

- Must work with Claude Code's native permission modes (plan, default, acceptEdits)
- Must integrate with existing hook architecture (workflow-gate.sh, bash-write-guard.sh)
- Status line changes must be backward-compatible with existing phase display
- Autonomy level is orthogonal to workflow phase — both dimensions coexist

## Architecture

Autonomy level adds an orthogonal dimension to the existing phase-based permission system:

```
Phase (DEFINE/DISCUSS/IMPLEMENT/REVIEW/COMPLETE) → controls WHAT is allowed
Autonomy Level (1/2/3)                           → controls HOW MUCH is allowed
```

Enforcement uses two layers:
- **Claude Code permission modes** — best-effort convenience layer (plan/default/acceptEdits). Mode switching is instructed via the `/autonomy` command but may not always engage. If the CC mode fails to switch, the hooks still enforce correctly.
- **Hooks** — single source of truth for enforcement, read autonomy level from state

**Enforcement check order** (in workflow-gate.sh and bash-write-guard.sh):
1. No state file → exit 0 (allow — no workflow active)
2. Phase is OFF → exit 0 (allow — workflow enforcement inactive)
3. Autonomy level check (Level 1 blocks all writes regardless of phase)
4. Phase gate check (existing logic for DEFINE/DISCUSS/COMPLETE restrictions)

**Level changes take effect on the next tool invocation.** In-flight operations complete normally.

## Level Definitions

### Level 1 — Supervised (`▶`)

| Capability | Allowed |
|---|---|
| Read/Grep/Glob | Yes |
| WebFetch/WebSearch | No (plan mode blocks; no hook fallback — known gap) |
| File writes (Write/Edit) | No |
| Bash write commands | No |
| Phase transitions | Propose and wait |
| Commit | No (behavioral — `git commit` not hook-enforced) |
| Push | Propose and wait (always) |

**CC permission mode**: `plan`
**Use case**: User wants to explore, research, and plan with Claude while retaining full control.

### Level 2 — Semi-Autonomous (`▶▶`)

| Capability | Allowed |
|---|---|
| Read/Grep/Glob | Yes |
| WebFetch/WebSearch | Yes |
| File writes (Write/Edit) | Yes, phase-gated (IMPLEMENT/REVIEW only) |
| Bash write commands | Yes, phase-gated |
| Phase transitions | Propose and wait |
| Commit | Propose and wait (behavioral, not hook-enforced) |
| Push | Propose and wait (always) |

**CC permission mode**: `default`
**Allow list**: WebFetch, WebSearch
**Use case**: User supervises at phase boundaries but trusts Claude within each phase.

### Level 3 — Unattended (`▶▶▶`)

| Capability | Allowed |
|---|---|
| Read/Grep/Glob | Yes |
| WebFetch/WebSearch | Yes |
| File writes (Write/Edit) | Yes, phase-gated |
| Bash write commands | Yes, phase-gated |
| Phase transitions | Auto-transition (except when user input needed) |
| Commit | Auto-commit in COMPLETE phase (behavioral — Claude commits without asking) |
| Push | Propose and wait (always) |

**CC permission mode**: `acceptEdits`
**Allow list**: Bash, WebFetch, WebSearch, MCP tools, Skills (user must have these in `settings.local.json` — the `/autonomy` command advises but cannot modify settings files)
**Use case**: User kicks off a workflow and walks away. Claude executes end-to-end, stopping only for genuine user input needs and push confirmation.

**Level 3 still respects phase gates for writes.** Writing code in DISCUSS phase is wrong regardless of autonomy level. The difference is in phase transitions and commits, not in bypassing phase-appropriate restrictions.

**Level 3 stop conditions:**
- User input needed in DISCUSS/DEFINE (questions that require user judgment)
- Git push (always requires confirmation)
- Review finds blocking issues that need user judgment

## State

New `autonomy_level` field in `.claude/state/workflow.json`:

```json
{
  "phase": "implement",
  "autonomy_level": 2,
  "active_skill": "test-driven-development",
  ...
}
```

New functions in `workflow-state.sh`:
- `get_autonomy_level()` — returns current level, defaults to 2 if field absent
- `set_autonomy_level(n)` — validates input is 1, 2, or 3; writes to state

**Initialization**: `set_phase()` sets `autonomy_level: 2` when transitioning from OFF to any active phase, if the field is absent. This is the natural trigger since every workflow starts with a phase command.

**Preservation**: `set_phase()` must preserve `autonomy_level` across phase transitions (same pattern as `active_skill` and `decision_record`). The current implementation rebuilds state from scratch — `autonomy_level` must be included in the rebuild.

**Cleanup**: `set_phase("off")` clears `autonomy_level` (resets to absent). Re-entering a workflow gets the default (Level 2) again.

## Command

New file: `.claude/commands/autonomy.md`

The command:
1. Validates the argument (1, 2, or 3)
2. Calls `set_autonomy_level(n)` to update workflow state
3. Instructs Claude to switch CC permission mode:
   - Level 1: enter plan mode via `EnterPlanMode`
   - Level 2: exit plan mode if active via `ExitPlanMode`
   - Level 3: exit plan mode if active via `ExitPlanMode`
4. Outputs confirmation: "Autonomy set to Level N (symbol) — description"

**Security constraint**: Only the user can invoke `/autonomy`. Claude can suggest ("This task would benefit from Level 3 — run `/autonomy 3` if you'd like") but cannot execute the command itself.

## Hook Changes

### `workflow-gate.sh` (PreToolUse for Write/Edit/MultiEdit/NotebookEdit)

New logic prepended to existing phase check:

```
1. Read autonomy_level from state
2. If level == 1 → DENY with message: "▶ Level 1: read-only mode. Run /autonomy 2 to enable writes."
3. If level == 2 or 3 → fall through to existing phase-based logic (unchanged)
```

Level 3 does NOT bypass phase gates. Phase gates protect against wrong-phase writes regardless of autonomy.

### `bash-write-guard.sh` (PreToolUse for Bash)

Same pattern:

```
1. Read autonomy_level from state
2. If level == 1 → DENY all Bash write commands with message
3. If level == 2 or 3 → fall through to existing phase-based logic
```

### `post-tool-navigator.sh` (PostToolUse coaching)

New behavior based on autonomy level:

- **Level 1 and 2**: Current behavior — when phase work is complete, coaching says "Ready to move to X, proceed?" and waits for user to run the phase command.
- **Level 3**: Layer 1 phase-entry messages include an additional line: "▶▶▶ Level 3 active — when this phase's work is complete, proceed to the next phase without waiting for user confirmation." This is appended to existing phase-entry coaching text.

**Auto-transition is purely behavioral guidance, not hook-enforced detection.** There is no mechanism for hooks to detect "phase work is complete" — that requires Claude's judgment (e.g., all plan steps done, tests passing, review acknowledged). The coaching message reinforces the Level 3 contract: Claude should auto-transition rather than propose-and-wait. The exceptions (user input needed, push confirmation, blocking review findings) are part of the behavioral instruction, not hook logic.

**Auto-commit at Level 3** is also behavioral: the COMPLETE phase coaching at Level 3 says "auto-commit when ready" rather than "propose commit and wait." `git commit` is not caught by bash-write-guard (it's not a file write), so this works without hook changes.

## Status Line

Current display: `[DISCUSS]` with phase color.
New display: `▶▶ [DISCUSS]` — autonomy symbol prepended.

In `statusline.sh`:
1. Read `autonomy_level` from `workflow.json` (same file already read for phase)
2. Map level to symbol: 1→`▶`, 2→`▶▶`, 3→`▶▶▶`
3. Prepend symbol before phase bracket with a space separator
4. When workflow is OFF or no level set: no autonomy symbol displayed

## Documentation Updates

| File | Change |
|---|---|
| `docs/reference/hooks.md` | Document autonomy level checks in workflow-gate and bash-write-guard |
| `docs/reference/architecture.md` | Add autonomy levels as a system concept |
| `docs/guides/statusline-guide.md` | Document autonomy symbols |
| `README.md` | Mention autonomy levels in feature overview |

## Testing

New tests in `tests/run-tests.sh` (~15-20 tests):

**State management:**
- `get_autonomy_level` returns default 2 when unset
- `get_autonomy_level` returns default 2 when state file exists but field absent (backward compat)
- `set_autonomy_level` accepts 1, 2, 3
- `set_autonomy_level` rejects invalid values (0, 4, -1, "abc")
- `autonomy_level` preserved across `set_phase()` transitions
- `set_phase("off")` clears `autonomy_level`
- `set_phase()` from OFF sets `autonomy_level: 2` if absent

**workflow-gate.sh:**
- Level 1 blocks Write/Edit in IMPLEMENT phase (normally allowed)
- Level 1 blocks Write/Edit in all phases
- Level 1 denial message mentions `/autonomy 2`
- Level 1 does NOT block writes when phase is OFF (workflow inactive)
- Level 2 allows writes in IMPLEMENT (current behavior preserved)
- Level 3 allows writes in IMPLEMENT (current behavior preserved)
- Level 2/3 still blocks writes in DISCUSS (phase gate preserved)

**bash-write-guard.sh:**
- Level 1 blocks Bash write commands in IMPLEMENT phase
- Level 2/3 allows Bash write commands in IMPLEMENT phase
- Level 2/3 still blocks Bash writes in DISCUSS (phase gate preserved)

**statusline.sh:**
- Level 1 renders `▶` before phase
- Level 2 renders `▶▶` before phase
- Level 3 renders `▶▶▶` before phase
- No symbol when workflow is OFF
- No symbol when autonomy_level field is absent
- Correct rendering with active skill present (full format test)

**post-tool-navigator.sh:**
- Level 3 phase-entry coaching includes auto-transition guidance
- Level 1/2 phase-entry coaching does not include auto-transition guidance
