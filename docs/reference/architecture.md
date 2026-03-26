# Architecture

How Workflow Manager, Superpowers, and claude-mem work together in Claude Code.

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                        User                             │
│            /define  /implement  /discuss                   │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ↓
        ┌──────────────────────────┐
        │     Claude Code CLI      │
        └──┬──────────┬────────┬──┘
           │          │        │
     ┌─────┘          │        └──────┐
     ↓                ↓               ↓
┌──────────┐  ┌──────────────┐  ┌───────────┐
│ Workflow │  │ Superpowers  │  │ claude-mem│
│ Hooks    │  │ (Skills &    │  │ (Cross-   │
│ (Hard    │  │  Techniques) │  │  session  │
│  gates)  │  │              │  │  memory)  │
└──────────┘  └──────────────┘  └───────────┘
 Deterministic   Behavioral       Persistence
 enforcement     guidance         & recall
```

## Two-Layer Enforcement

| Layer | Mechanism | What it does | Can Claude bypass? |
|-------|-----------|-------------|-------------------|
| **Hooks** | PreToolUse deny | Blocks Write/Edit in DEFINE, DISCUSS, and COMPLETE phases | No |
| **Superpowers** | Prompt instructions | Guides brainstorm → plan → execute → verify | Yes (but less likely with hooks backing it up) |

The hooks enforce the **discuss-before-code boundary**. Superpowers handles the **quality of each phase**.

## Phase Model

```
         ┌──(/define)──> DEFINE ──(/discuss)──┐
OFF ─────┤                                    ├──> DISCUSS ──(/implement)──> IMPLEMENT ──(/review)──> REVIEW ──(/complete)──> COMPLETE ──> OFF
         └──(/discuss)────────────────────────┘

Any /phase command can jump directly to any phase. Soft gates warn when skipping recommended steps.

DEFINE:     Write/Edit BLOCKED (except specs/plans), Bash writes BLOCKED (except specs/plans)
DISCUSS:    Write/Edit BLOCKED (except specs/plans), Bash writes BLOCKED (except specs/plans)
IMPLEMENT:  Everything ALLOWED
REVIEW:     Everything ALLOWED (fixes from review)
COMPLETE:   Write/Edit BLOCKED (except docs), Bash writes BLOCKED (except docs)
```

### Detailed Workflow Diagram

```mermaid
flowchart LR
    subgraph OFF_BOX ["OFF"]
        OFF["No enforcement\nAll edits allowed"]
    end

    subgraph DEFINE_BOX ["DEFINE — Diamond 1: Problem Space"]
        direction TB
        D1["Problem Discovery\nwho, what pain, why now\n<b>skill: brainstorming</b>"]
        D2["Diverge: Research Agents\ndomain research, context\nassumption challenging"]
        D3["Problem Statement\nHow Might We framing"]
        D4["Converge: Structure Agents\noutcomes, scope, metrics"]
        D5["Decision Record\nProblem section"]
        D1 --> D2 --> D3 --> D4 --> D5
    end

    subgraph DISCUSS_BOX ["DISCUSS — Diamond 2: Solution Space"]
        direction TB
        P1["Diverge: Solution Research\nweb search, case studies\nprior art\n<b>skill: brainstorming</b>"]
        P2["Converge: Codebase Analysis\narchitecture fit, risks\ntrade-offs\n<b>skill: brainstorming</b>"]
        P3["Decision Record\napproaches, rationale\nchosen approach"]
        P4["Write the Plan\nstep-by-step implementation\n<b>skill: writing-plans</b>"]
        P1 --> P2 --> P3 --> P4
    end

    subgraph IMPLEMENT_BOX ["IMPLEMENT"]
        direction TB
        I1["Execute the Plan\nstep-by-step with checkpoints\n<b>skill: executing-plans</b>"]
        I2["Test-Driven Development\nwrite tests before code\n<b>skill: test-driven-development</b>"]
        I3["Code + Tests\ncommit after each task\n<b>skill: subagent-driven-development</b>"]
        I1 --> I2 --> I3
    end

    subgraph REVIEW_BOX ["REVIEW"]
        direction TB
        R1["Run Test Suite\n<b>skill: verification-before-completion</b>"]
        R2["Detect Changed Files"]
        subgraph R3 ["5 Parallel Review Agents"]
            direction LR
            R3A["Code Quality\nDRY, SOLID, YAGNI\ncomplexity, naming\n<b>skill: requesting-code-review</b>"]
            R3B["Security\ninjection, credentials\nunsafe operations\n<b>skill: requesting-code-review</b>"]
            R3C["Architecture\nplan compliance\npatterns, boundaries\n<b>skill: requesting-code-review</b>"]
            R3D["Governance\nproduction readiness\n<b>skill: requesting-code-review</b>"]
            R3E["Codebase Hygiene\ndead code, orphans\n<b>skill: requesting-code-review</b>"]
        end
        R4["Verification Agent\nfilter false positives"]
        R5["Consolidated Report\nfindings by severity"]
        R6["Fix Findings\napply fixes, re-review\nuntil clean or acknowledged\n<b>skill: systematic-debugging</b>"]
        R1 --> R2 --> R3 --> R4 --> R5 --> R6
    end

    subgraph COMPLETE_BOX ["COMPLETE"]
        direction TB
        C1["Plan Validation\nverify each deliverable\nwith behavioral evidence\n<b>skill: verification-before-completion</b>"]
        C2["Outcome Validation\ncheck decision record outcomes\nand success metrics\n<b>skill: verification-before-completion</b>"]
        C3["Smart Docs Detection\nrecommend doc updates"]
        C4["Commit and Push\nstage, sign, push"]
        C5["Branch Integration\nmerge PR, clean worktree\n<b>skill: finishing-a-development-branch</b>"]
        C6["Tech Debt Audit\nreview accepted trade-offs"]
        C7["Handover\nclaude-mem observation\ncommit hash, decisions\n<b>tool: claude-mem</b>"]
        C1 --> C2 --> C3 --> C4 --> C5 --> C6 --> C7
    end

    OFF_END(("OFF"))

    OFF -- "/define" --> DEFINE_BOX
    OFF -. "/discuss\n(skip define)" .-> DISCUSS_BOX
    DEFINE_BOX -- "/discuss" --> DISCUSS_BOX
    DISCUSS_BOX -- "/implement" --> IMPLEMENT_BOX
    IMPLEMENT_BOX -- "/review" --> REVIEW_BOX
    REVIEW_BOX -- "/complete" --> COMPLETE_BOX
    COMPLETE_BOX --> OFF_END

    style OFF_BOX fill:#f5f5f5,stroke:#999,color:#333
    style DEFINE_BOX fill:#dbeafe,stroke:#3b82f6,color:#1e40af
    style DISCUSS_BOX fill:#fef9c3,stroke:#eab308,color:#854d0e
    style IMPLEMENT_BOX fill:#dcfce7,stroke:#22c55e,color:#166534
    style REVIEW_BOX fill:#cffafe,stroke:#06b6d4,color:#155e75
    style COMPLETE_BOX fill:#fce7f3,stroke:#ec4899,color:#9d174d
    style OFF_END fill:#f5f5f5,stroke:#999,color:#333
    style R3 fill:#e0f2fe,stroke:#0ea5e9,color:#0c4a6e

    style OFF fill:#f5f5f5,stroke:#999,color:#333
    style D1 fill:#dbeafe,stroke:#3b82f6,color:#1e40af
    style D2 fill:#dbeafe,stroke:#3b82f6,color:#1e40af
    style D3 fill:#dbeafe,stroke:#3b82f6,color:#1e40af
    style D4 fill:#dbeafe,stroke:#3b82f6,color:#1e40af
    style D5 fill:#dbeafe,stroke:#3b82f6,color:#1e40af
    style P1 fill:#fef9c3,stroke:#eab308,color:#854d0e
    style P2 fill:#fef9c3,stroke:#eab308,color:#854d0e
    style P3 fill:#fef9c3,stroke:#eab308,color:#854d0e
    style P4 fill:#fef9c3,stroke:#eab308,color:#854d0e
    style I1 fill:#dcfce7,stroke:#22c55e,color:#166534
    style I2 fill:#dcfce7,stroke:#22c55e,color:#166534
    style I3 fill:#dcfce7,stroke:#22c55e,color:#166534
    style R1 fill:#cffafe,stroke:#06b6d4,color:#155e75
    style R2 fill:#cffafe,stroke:#06b6d4,color:#155e75
    style R3A fill:#e0f2fe,stroke:#0ea5e9,color:#0c4a6e
    style R3B fill:#e0f2fe,stroke:#0ea5e9,color:#0c4a6e
    style R3C fill:#e0f2fe,stroke:#0ea5e9,color:#0c4a6e
    style R3D fill:#e0f2fe,stroke:#0ea5e9,color:#0c4a6e
    style R3E fill:#e0f2fe,stroke:#0ea5e9,color:#0c4a6e
    style R4 fill:#cffafe,stroke:#06b6d4,color:#155e75
    style R5 fill:#cffafe,stroke:#06b6d4,color:#155e75
    style R6 fill:#cffafe,stroke:#06b6d4,color:#155e75
    style C1 fill:#fce7f3,stroke:#ec4899,color:#9d174d
    style C2 fill:#fce7f3,stroke:#ec4899,color:#9d174d
    style C3 fill:#fce7f3,stroke:#ec4899,color:#9d174d
    style C4 fill:#fce7f3,stroke:#ec4899,color:#9d174d
    style C5 fill:#fce7f3,stroke:#ec4899,color:#9d174d
    style C6 fill:#fce7f3,stroke:#ec4899,color:#9d174d
    style C7 fill:#fce7f3,stroke:#ec4899,color:#9d174d
```

## Autonomy Levels

Phase and autonomy are two orthogonal dimensions of control:

- **Phase** (WHAT) — which operations are allowed at each stage of the workflow
- **Autonomy** (HOW MUCH) — how independently Claude proceeds within those permissions

| Symbol | Level | Name | Description |
|--------|-------|------|-------------|
| `▶` | off | Supervised | Step-by-step pair programming. Claude executes one plan step at a time, presents the change, and waits for review before proceeding. Writes follow phase rules. |
| `▶▶` | ask | Semi-Auto | Claude works freely within each phase but stops at phase boundaries for review and guidance before transitioning. No auto-commits. **Default.** |
| `▶▶▶` | auto | Unattended | Full autonomy. Claude auto-transitions between phases, auto-fixes review findings, auto-commits. Stops only when user input is genuinely needed or before git push. |

**Enforcement**: Hooks (`workflow-gate.sh`, `bash-write-guard.sh`) are the single source of truth and apply the autonomy check before the phase gate. Claude Code permission modes (`plan`/`default`/`acceptEdits`) are best-effort convenience that mirror the active autonomy level but are not relied upon for enforcement.

Set via `/autonomy off|ask|auto`. Only the user can change it.

## Component Responsibilities

### Workflow Manager — Hard Gates

- `workflow-gate.sh` — blocks Write/Edit/MultiEdit in DEFINE, DISCUSS, and COMPLETE phases (with different whitelist tiers)
- `bash-write-guard.sh` — blocks Bash write operations in DEFINE, DISCUSS, and COMPLETE phases
- `workflow-state.sh` — state read/write utility
- State: `.claude/state/workflow.json` (gitignored)

### Superpowers — Development Techniques

- `/superpowers:brainstorming` — requirements refinement
- `/superpowers:writing-plans` — plan generation
- `/superpowers:executing-plans` — batch execution with checkpoints
- Auto-activated skills: TDD, debugging, code review, verification, worktrees

Skills load on-demand when contextually relevant, not preloaded.

### claude-mem — Cross-Session Memory

- Persists observations (decisions, discoveries, preferences) across sessions
- `mem-search` for loading prior context at session start
- `make-plan` / `do` for plan creation and execution

## Workflow

```
DEFINE PHASE (Diamond 1 — Problem Space, edits blocked, optional):
  /define → brainstorming with problem-discovery context
  Diverge: domain research, context gathering, assumption challenging agents
  Converge: outcome structurer, scope boundary checker agents
  Output: decision record with Problem section

TRANSITION: /discuss → proceed to solution design

DISCUSS PHASE (Diamond 2 — Solution Space, edits blocked):
  /discuss → brainstorming with solution-design context
  Diverge: solution researchers, prior art scanner agents
  Converge: codebase analyst, risk assessor agents
  Output: decision record enriched with Approaches + Decision sections
  /superpowers:writing-plans → implementation plan

TRANSITION: /implement → unlock edits (soft gate: warns if no plan)

IMPLEMENT PHASE (edits allowed):
  /superpowers:executing-plans → step-by-step with checkpoints
  /superpowers:test-driven-development → tests before code

TRANSITION: /review → enter review (soft gate: warns if no changes)

REVIEW PHASE (edits allowed for fixes):
  5 parallel review agents: code quality, security, architecture, governance, codebase hygiene
  Verification agent filters false positives
  Findings persisted to decision record
  Fix issues or acknowledge

TRANSITION: /complete → enter completion (soft gate: warns if no review)

COMPLETE PHASE (code blocked, docs allowed):
  Plan validation → verify deliverables with behavioral evidence
  Outcome validation → check decision record outcomes and metrics
  Smart docs detection → recommend doc/README updates
  Commit and push
  Tech debt audit → review accepted trade-offs
  Handover → claude-mem observation with commit hash and decisions

TRANSITION: completes → back to OFF

Note: Any /phase command can jump directly to any phase.
Soft gates warn when skipping recommended steps but never block.
```

## File Organization

```
your-project/
├── .claude/
│   ├── hooks/
│   │   ├── workflow-state.sh       # State utility
│   │   ├── workflow-cmd.sh         # Shell-independent wrapper
│   │   ├── workflow-gate.sh        # Write/Edit gate
│   │   ├── bash-write-guard.sh     # Bash write gate
│   │   ├── user-phase-gate.sh      # User prompt phase authorization
│   │   └── post-tool-navigator.sh  # Phase guidance messages
│   ├── commands/
│   │   ├── define.md               # /define command
│   │   ├── discuss.md              # /discuss command
│   │   ├── implement.md            # /implement command
│   │   ├── review.md               # /review command
│   │   ├── complete.md             # /complete command
│   │   ├── off.md                  # /off command
│   │   └── autonomy.md             # /autonomy command
│   ├── state/
│   │   └── workflow.json           # Consolidated workflow state (gitignored)
│   └── settings.json               # Hook configuration
├── docs/
│   └── plans/                      # Implementation plans
├── CLAUDE.md                       # Project rules (committed)
└── src/                            # Your code
```

## Security

- `token_do_not_commit/` in `.gitignore`
- `.claude/state/` in `.gitignore` (session state, not committed)
- YubiKey FIDO2 signing optional (see CLAUDE.md template)
- Never commit credentials; use vault-managed secrets
