# WFM Architecture Reference

> How the Workflow Manager works: phases, gates, hooks, and the trust model.

---

## Phase State Machine

```
OFF → DEFINE → DISCUSS → IMPLEMENT → REVIEW → COMPLETE → OFF
```

Each phase has a gate. You must pass the gate to leave.

---

## The Phases

| Phase | What happens | Who does the work |
|-------|-------------|-------------------|
| OFF | No enforcement | — |
| DEFINE | Problem definition | Agent |
| DISCUSS | Solution design + plan | Agent |
| IMPLEMENT | Write code | Agent |
| REVIEW | 5 agents check the code | Agent |
| COMPLETE | Validate, commit, handover | Agent |

---

## Exit Gates (what must be true to LEAVE a phase)

```
DISCUSS exit requires:
  ├── problem_confirmed = true
  ├── research_done = true
  ├── approach_selected = true
  └── plan_written = true

IMPLEMENT exit requires:
  ├── plan_read = true
  ├── all_tasks_complete = true
  └── tests_passing = true

REVIEW exit requires:
  ├── verification_complete = true
  ├── agents_dispatched = true
  ├── findings_presented = true
  └── findings_acknowledged = true

COMPLETE exit requires:
  ├── plan_validated = true
  ├── outcomes_validated = true
  ├── results_presented = true
  ├── docs_checked = true
  ├── committed = true
  ├── pushed = true
  ├── tech_debt_audited = true
  └── handover_saved = true
```

The agent sets these flags itself. Gates trust them.

---

## Who Can Transition Phases

```
User /command  → always works (intent file bypasses gates)
Agent (auto)   → works if milestones complete + autonomy = auto
Agent (ask)    → blocked — must tell user to run /command
Agent → off    → always blocked (only user can close the workflow)
```

---

## The 6 Hook Scripts

### `workflow-state.sh`
**Type:** Library — not a hook itself, sourced by everything else.

**Contains:** `get_phase`, `set_phase`, `_check_phase_gates`, `_check_phase_intent`, milestone getters/setters, whitelist constants.

**Used by:** every other script in `.claude/hooks/`

---

### `workflow-cmd.sh`
**Type:** Public CLI wrapper — exposes `workflow-state.sh` functions as shell commands.

**Used by:** the agent (via Bash tool calls) and command files (`implement.md`, `discuss.md`, etc.)

```bash
.claude/hooks/workflow-cmd.sh agent_set_phase "implement"
.claude/hooks/workflow-cmd.sh set_implement_field "tests_passing" "true"
.claude/hooks/workflow-cmd.sh get_phase
```

---

### `user-phase-gate.sh`
**Type:** `UserPromptSubmit` hook — fires on every user message, before the agent sees it.

**What it does:** If the user types `/discuss`, `/implement`, `/review`, `/complete`, or `/off` — writes an intent file to `.claude/state/phase-intent.json`. For `/autonomy` commands — writes to `autonomy-intent.json`.

**Why it matters:** This is the **only** path that authorizes user-initiated phase transitions. The agent cannot write intent files. Claude Code cannot trigger this hook — only real user input does.

```
User types /implement
    → user-phase-gate.sh fires
    → writes .claude/state/phase-intent.json = {"intent": "implement"}
    → agent calls workflow-cmd.sh agent_set_phase "implement"
    → agent_set_phase reads intent file, sees match, authorizes, deletes file
```

---

### `workflow-gate.sh`
**Type:** `PreToolUse` hook on `Write|Edit|MultiEdit|NotebookEdit`.

**What it does:** Checks current phase. Blocks file writes in DEFINE, DISCUSS, COMPLETE unless the target path is whitelisted. Passes everything in IMPLEMENT and REVIEW.

```
Whitelists:
  DEFINE/DISCUSS: .claude/state/, docs/superpowers/specs/, docs/plans/
  COMPLETE:       .claude/state/, docs/, root *.md files
```

---

### `bash-write-guard.sh`
**Type:** `PreToolUse` hook on `Bash`.

**What it does:** Same job as `workflow-gate.sh` but for shell commands. Detects write operations (`>`, `sed -i`, `cp`, `mv`, `gh` mutations, etc.) and blocks them in DEFINE, DISCUSS, COMPLETE unless whitelisted.

```
Always allowed (any phase):
  - workflow-cmd.sh calls (single command, no chaining)
  - workflow-state.sh sourcing (single command, no chaining)
  - gh commands (no pipe to file writers, no chaining)
  - git commit (standalone only)

Allowed in COMPLETE only:
  - rm .claude/tmp/ cleanup
```

---

### `post-tool-navigator.sh`
**Type:** `PostToolUse` hook — fires after every tool call the agent makes.

**What it does:** Three-layer coaching system:
- **Layer 1:** On phase entry — injects phase objective, scope, and done criteria (once per phase)
- **Layer 2:** Periodic — reinforces professional standards every N tool calls
- **Layer 3:** On every tool call — scans for anti-patterns and injects warnings

---

## How They Connect — Full Flow

```
User types /implement
    └─ user-phase-gate.sh writes intent file

Agent reads /implement command file
    └─ calls workflow-cmd.sh agent_set_phase "implement"
           └─ workflow-state.sh: agent_set_phase()
                  ├─ reads intent file → authorized, user_initiated=true
                  ├─ gates bypassed (user-initiated)
                  └─ writes workflow.json: phase=implement

Agent tries to write a file
    └─ workflow-gate.sh: phase=implement → allowed

Agent tries to run a bash write
    └─ bash-write-guard.sh: phase=implement → allowed

Agent finishes a tool call
    └─ post-tool-navigator.sh fires coaching messages

Agent calls workflow-cmd.sh agent_set_phase "review"
    └─ workflow-state.sh: agent_set_phase()
           ├─ no intent file → not user-initiated
           ├─ autonomy=auto, review > implement → authorized
           ├─ _check_phase_gates: IMPLEMENT milestones all true? → pass
           └─ writes workflow.json: phase=review
```

---

## Milestone Resets

When entering a phase, `set_phase` automatically resets that phase's milestones to false — regardless of how you entered (user command, agent auto-transition, or direct call). This prevents stale flags from a previous session carrying over.

```
User runs /implement
    → set_phase("implement") called
    → reset_implement_status() runs automatically
    → plan_read=false, all_tasks_complete=false, tests_passing=false
    → clean slate guaranteed
```

## REVIEW Skip Protection

An agent cannot jump from IMPLEMENT directly to COMPLETE. `_check_phase_gates` checks that `review.findings_acknowledged=true` before allowing entry to COMPLETE.

```
Agent calls agent_set_phase "complete" (skipping review)
    → HARD GATE: findings_acknowledged not set
    → BLOCKED with explanation
    → Agent must run /review first

User runs /complete (skipping review)
    → user_initiated=true → gates bypassed
    → Allowed (user's explicit choice)
```

## Known Trust Gap

Milestone flags are self-certified by the agent. The gate trusts them. An agent that sets `tests_passing=true` without running tests will pass the gate. The structural mitigations are:

1. Milestones reset on phase entry — stale flags cannot carry over
2. REVIEW is mandatory before COMPLETE (agent path) — catching issues that IMPLEMENT missed
3. COMPLETE re-runs tests if code changed since `tests_last_passed_at`
