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
| DISCUSS | Solution design + approach selection | Agent |
| IMPLEMENT | Write code | Agent |
| REVIEW | 5 agents check the code | Agent |
| COMPLETE | Validate, commit, handover | Agent |

---

## Exit Gates (what must be true to LEAVE a phase)

```
DISCUSS exit requires:
  ├── problem_confirmed = true
  ├── research_done = true
  └── approach_selected = true

IMPLEMENT exit requires:
  ├── plan_written = true
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
User /command  → always works (!backtick calls user-set-phase.sh, which writes state directly — no gates)
Agent (auto)   → works if milestones complete + autonomy = auto
Agent (ask)    → blocked — must tell user to run /command
Agent → off    → always blocked (only user can close the workflow)
```

---

## Claude Code Permissions × WFM Autonomy

WFM autonomy levels control what the *agent* should do. Claude Code's permission mode controls which *tool calls* auto-approve without prompting you. These are independent systems — both must be configured for unattended operation to work.

**Evaluation order (highest to lowest precedence):**
1. CC deny rules — always block
2. CC allow rules — always permit
3. CC permission mode — fallback for unmatched tools

| CC Permission Mode | WFM `ask` autonomy | WFM `auto` autonomy | Notes |
|---|---|---|---|
| `default` | Works — Claude prompts on unlisted tools | Works partially — pipeline may stall if Write/Bash prompt appears | Add Write, Edit, Bash to allow list for unattended operation |
| `acceptEdits` | Intended use — edits auto-approve, Bash prompts | Works for edit-heavy pipelines — Bash still prompts | Best match for interactive supervision |
| `auto` | Over-permissive for supervised use | Intended use for unattended pipelines | All tools auto-approve |
| `dontAsk` | All prompts auto-denied — pipeline blocked | All prompts auto-denied — pipeline blocked | Not usable with WFM in any autonomy mode |
| `bypassPermissions` | **WFM enforcement does not apply** — hooks do not fire | **WFM enforcement does not apply** — hooks do not fire | Phase gates, write guards, and coaching are all bypassed |

**Recommended setup for `/autonomy auto` (unattended):** Use `auto` or `acceptEdits` CC mode and ensure Write, Edit, Bash are in your allow list in `.claude/settings.json`.

---

## The 6 Hook Scripts

### `workflow-state.sh`
**Type:** Library — not a hook itself, sourced by everything else.

**Contains:** `get_phase`, `agent_set_phase`, `_check_phase_gates`, milestone getters/setters, whitelist constants.

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

### `user-set-phase.sh`
**Type:** User-only script — called from `!backtick` in command files, never via Bash tool.

**What it does:** Writes phase state directly to `workflow.json`. No authorization checks, no gate checks. The user's intent is expressed by typing the slash command.

**Security:** `bash-write-guard.sh` blocks any Bash tool call that attempts to execute this script. Only `!backtick` pre-processing (which happens before Claude sees the prompt) can reach it.

```
User types /implement
    → !backtick in implement.md calls user-set-phase.sh "implement"
    → user-set-phase.sh writes workflow.json directly
    → Claude receives the command file content as its phase briefing
```

---

### `workflow-gate.sh`
**Type:** `PreToolUse` hook on `Write|Edit|MultiEdit|NotebookEdit`.

**What it does:** Checks current phase. Blocks file writes in DEFINE, DISCUSS, COMPLETE unless the target path is whitelisted. Passes everything in IMPLEMENT and REVIEW.

```
Whitelists:
  DEFINE/DISCUSS: .claude/state/, docs/plans/
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
  - gh read-only in DEFINE/DISCUSS (view, list only — no gh api)
  - gh all ops in COMPLETE (no pipe to file writers, no chaining)
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
    └─ !backtick calls user-set-phase.sh "implement"
           └─ writes workflow.json directly (no checks, no gates)

Agent reads /implement command file (the phase briefing)

Agent tries to write a file
    └─ workflow-gate.sh: phase=implement → allowed

Agent tries to run a bash write
    └─ bash-write-guard.sh: phase=implement → allowed

Agent finishes a tool call
    └─ post-tool-navigator.sh fires coaching messages

Agent calls workflow-cmd.sh agent_set_phase "review"
    └─ workflow-state.sh: agent_set_phase()
           ├─ autonomy=auto, review > implement → authorized (forward-only)
           ├─ _check_phase_gates: IMPLEMENT milestones all true? → pass
           └─ writes workflow.json: phase=review
```

---

## Milestone Resets

Phase milestones are NOT preserved across `agent_set_phase` or `user-set-phase.sh` transitions — the jq template rebuilds state from scratch, dropping all milestone sections. There is no need for explicit resets; milestones do not survive phase transitions.

Command files call `reset_*_status` after `user-set-phase.sh` to initialize the incoming phase's milestone section with all fields set to false.

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
