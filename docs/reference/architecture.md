# Architecture

How Workflow Manager, Superpowers, and claude-mem work together in Claude Code.

## System Overview

```mermaid
graph TD
    User["User<br/>/define /discuss /implement ..."]
    CLI["Claude Code CLI"]
    WFM["Workflow Manager<br/>(Hard gates)"]
    SP["Superpowers<br/>(Skills & Techniques)"]
    CM["claude-mem<br/>(Cross-session memory)"]

    User --> CLI
    CLI --> WFM
    CLI --> SP
    CLI --> CM

    WFM -.- |"Deterministic<br/>enforcement"| WFM
    SP -.- |"Behavioral<br/>guidance"| SP
    CM -.- |"Persistence<br/>& recall"| CM
```

## Phase Model

See [README — Workflow](../../README.md#workflow) for the phase summary table.

<table>
<tr>
<th style="width:16%">OFF</th>
<th style="width:8%; text-align:center">→<br/><em>none</em></th>
<th style="width:16%">DEFINE</th>
<th style="width:8%; text-align:center">→<br/><em>soft</em></th>
<th style="width:16%">DISCUSS</th>
<th style="width:8%; text-align:center">→<br/><em>plan_<br/>written</em></th>
<th style="width:16%">IMPLEMENT</th>
<th style="width:8%; text-align:center">→<br/><em>all<br/>milestones</em></th>
<th style="width:16%">REVIEW</th>
<th style="width:8%; text-align:center">→<br/><em>findings_<br/>ack'd</em></th>
<th style="width:16%">COMPLETE</th>
</tr>
<tr>
<td colspan="11" style="background: #f5f5f5; padding: 8px; font-size: 11px;"><em><strong>No enforcement.</strong> Use /define to start workflow.</em></td>
</tr>
<tr style="background: #f0f8ff;">
<td></td>
<td></td>
<td colspan="3" style="text-align: center; font-weight: bold; padding: 8px;">Understand the problem space</td>
<td></td>
<td colspan="3" style="text-align: center; font-weight: bold; padding: 8px;">Design the solution</td>
<td></td>
<td colspan="1" style="text-align: center; font-weight: bold; padding: 8px;">Execute &amp; verify</td>
</tr>
<tr>
<td></td>
<td></td>
<td><strong>1. Brainstorm</strong><br/>User Q&amp;A:<br/>• Who is affected?<br/>• What's the pain?<br/>• Current state/workarounds?<br/>• Why now?</td>
<td></td>
<td><strong>1. Clarify scope</strong><br/>Ask:<br/>• What exactly needs to change?<br/>• What's out of scope?<br/>• Constraints?</td>
<td></td>
<td><strong>1. Read &amp; understand</strong><br/>• Read plan file<br/>• Set milestone: plan_read<br/>• Note any gaps</td>
<td></td>
<td><strong>1. Verify tests</strong><br/>• Check tests_passing milestone from IMPLEMENT<br/>• If missing: run test suite now</td>
<td></td>
<td><strong>1. Validate outcomes</strong><br/>• Check plan goals met<br/>• Check measurable metrics</td>
</tr>
<tr>
<td></td>
<td></td>
<td><strong>2. Domain Researcher</strong><br/>Search problem domain for context &amp; patterns</td>
<td></td>
<td><strong>2. Solution Researcher A</strong><br/>Research technical approaches to the problem</td>
<td></td>
<td><strong>2. TDD: write tests</strong><br/>• Tests before code<br/>• Red-green-refactor cycle<br/>• Set milestone: tests_passing after run</td>
<td></td>
<td><strong>2. Code quality agent</strong><br/>Review for bugs, style, maintainability</td>
<td></td>
<td><strong>2. Update docs</strong><br/>• README accuracy<br/>• Architecture changes<br/>• Setup/install updates</td>
</tr>
<tr>
<td></td>
<td></td>
<td><strong>3. Context Gatherer</strong><br/>Search project history &amp; claude-mem for prior related work</td>
<td></td>
<td><strong>3. Solution Researcher B</strong><br/>Research case studies &amp; lessons learned from approaches</td>
<td></td>
<td><strong>3. Implement tasks</strong><br/>Follow plan step-by-step<br/>Test after each logical chunk<br/>Commit at milestones</td>
<td></td>
<td><strong>3. Security agent</strong><br/>Review for vulnerabilities, auth, secrets</td>
<td></td>
<td><strong>3. Commit &amp; push</strong><br/>• Stage changes<br/>• Create PR or commit directly<br/>• Push to remote</td>
</tr>
<tr>
<td></td>
<td></td>
<td><strong>4. Assumption Challenger</strong><br/>Challenge the problem framing. Is this the real problem?</td>
<td></td>
<td><strong>4. Prior Art Scanner</strong><br/>Search claude-mem &amp; codebase for prior implementations</td>
<td></td>
<td><strong>4. Run full test suite</strong><br/>• All tests pass<br/>• Coverage acceptable<br/>• Set milestone: all_tasks_complete</td>
<td></td>
<td><strong>4. Architecture agent</strong><br/>Review against design patterns &amp; plan compliance</td>
<td></td>
<td><strong>4. Tech debt audit</strong><br/>• List known tech debt<br/>• Quantify cleanup effort<br/>• Document for next iteration</td>
</tr>
<tr>
<td></td>
<td></td>
<td><strong>5. Converge: outcomes</strong><br/>Dispatch Outcome Structurer &amp; Scope Boundary Checker. Agree on measurable outcomes &amp; scope boundaries. Create plan at docs/plans/YYYY-MM-DD-<topic>.md with Problem section. Mark: problem_confirmed</td>
<td></td>
<td><strong>5. Converge: approach</strong><br/>Dispatch Codebase Analyst &amp; Risk Assessor. Present 2-3 viable approaches with tradeoffs. User selects. Enrich plan with Approaches + Decision sections. Mark: approach_selected, plan_written</td>
<td></td>
<td><strong>5. Version bump</strong><br/>Update version per semver based on changes. Commit version bump.</td>
<td></td>
<td><strong>5. Verification agent</strong><br/>Verify findings from 4 agents above. Deduplicate. Assess severity (critical/warning/suggestion)</td>
<td></td>
<td><strong>5. Handover</strong><br/>Write claude-mem observation with:<br/>• What was built &amp; why<br/>• Key decisions &amp; gotchas<br/>• What's left for next session</td>
</tr>
</table>

\*`tests_passing` is skipped if no test suite is detected. Any `/phase` command can jump directly to any phase. Soft gates warn but never block.

## Autonomy Levels

See [README — Autonomy Levels](../../README.md#autonomy-levels) for the autonomy table.

Hooks (`workflow-gate.sh`, `bash-write-guard.sh`) are the single source of truth for write permissions. Autonomy controls checkpoint granularity (how often Claude pauses for user input), not enforcement. All autonomy levels follow the same phase-based write rules.

## Enforcement

| Mechanism | What it does | Fires | Bypassable? |
|-----------|-------------|-------|-------------|
| **Hard gates** (hooks) | Block Write/Edit/Bash writes in DEFINE, DISCUSS, COMPLETE | Every tool call | No |
| **Layer 1: Phase entry** | Coaching message with objective and done criteria | Once per phase entry | Yes |
| **Layer 2: Standards** | Contextual reinforcement (e.g., "tests first?" on source edit) | Once per trigger type, resets after 30 idle calls | Yes |
| **Layer 3: Anti-laziness** | Red-flag detection (short prompts, generic commits, skipped research) | Every match | Yes |

**Hard gates** are the only mechanism that blocks operations. `workflow-gate.sh` blocks Write/Edit/MultiEdit; `bash-write-guard.sh` blocks Bash write operations (redirects, `sed -i`, `cp`, `mv`, `rm`, `tee`, heredocs, scripted file writes, pipe-to-shell). Both use phase-specific whitelists — see [Write Blocking](#write-blocking).

**Layer 1** fires once when entering a phase and a tracked tool is used. Provides the phase objective and done criteria. In auto autonomy, also includes auto-transition instructions.

**Layer 2** fires once per trigger type per phase (e.g., agent return in DEFINE, source edit in IMPLEMENT). Resets after 30 tool calls without firing, so it can re-fire in long phases.

**Layer 3** fires on every match. Detects: short agent prompts (<150 chars), generic commit messages (<30 chars), all review findings downgraded, minimal handover (<200 chars), missing project field on `save_observation`, skipped research (10+ calls without agent dispatch), no test run after 5+ source edits, and stalled auto-transitions. Pipeline-abandoned detection (e.g., approach selected but plan not written) is also Layer 3.

## Gates and Milestones

### Hard Gates

| Transition | Required Milestones | Rationale |
|-----------|---------------------|-----------|
| DISCUSS → any | `plan_written` | Plan is the contract between DISCUSS and IMPLEMENT |
| IMPLEMENT → any | `plan_read`, `tests_passing`\*, `all_tasks_complete` | Proves plan was executed and tests pass |
| → COMPLETE (skipping REVIEW) | `findings_acknowledged` | Review is mandatory before completion |
| COMPLETE → OFF | All 9: `plan_validated`, `outcomes_validated`, `results_presented`, `docs_checked`, `committed`, `pushed`, `issues_reconciled`, `tech_debt_audited`, `handover_saved` | Each step produces artifacts for future sessions |

\*`tests_passing` is skipped if no test suite is detected.

### Soft Gates

- → IMPLEMENT: warns if no plan registered
- → REVIEW: warns if no code changes detected
- → COMPLETE: warns if review hasn't been run

### Milestones Per Phase

| Phase | Milestones |
|-------|-----------|
| DEFINE | *(guidance only — no tracked milestones)* |
| DISCUSS | `problem_confirmed`, `research_done`, `approach_selected`, `plan_written` |
| IMPLEMENT | `plan_read`, `tests_passing`, `all_tasks_complete` |
| REVIEW | `verification_complete`, `agents_dispatched`, `findings_presented`, `findings_acknowledged` |
| COMPLETE | `plan_validated`, `outcomes_validated`, `results_presented`, `docs_checked`, `committed`, `pushed`, `issues_reconciled`, `tech_debt_audited`, `handover_saved` |

## Write Blocking

| Tier | Phases | Allowed Writes | Blocked |
|------|--------|---------------|---------|
| Restrictive | DEFINE, DISCUSS | `.claude/state/`, `docs/plans/`, `docs/specs/` | All source code, config, other docs |
| Docs-allowed | COMPLETE | `.claude/state/`, `docs/`, root `*.md` | Source code, implementation files |
| Open | IMPLEMENT, REVIEW | Everything | Nothing |

Edits to `.claude/hooks/`, `plugin/scripts/`, and `plugin/commands/` are blocked in all phases (guard-system self-protection). Users can override via `!backtick`.

The bash write guard (`bash-write-guard.sh`) pattern-matches ~95% of shell write operations. Claude isn't adversarial — common patterns are sufficient.

## File Organization

```
your-project/
├── .claude/
│   ├── hooks/                         # Enforcement hooks
│   │   ├── workflow-state.sh         # State utility
│   │   ├── workflow-cmd.sh           # Shell-independent wrapper
│   │   ├── workflow-gate.sh          # Write/Edit gate
│   │   ├── bash-write-guard.sh       # Bash write gate
│   │   └── post-tool-navigator.sh    # 3-layer coaching system
│   ├── commands/                      # Phase commands (/define, /discuss, etc.)
│   ├── state/
│   │   └── workflow.json              # Workflow state (gitignored)
│   └── settings.json                  # Hook configuration
├── docs/
│   ├── guides/                        # Getting started, claude-mem, statusline
│   ├── reference/                     # Architecture, hooks, commands
│   ├── plans/                         # Implementation plans (per-feature)
│   └── specs/                         # Design specs (per-feature)
├── CLAUDE.md                          # Project rules (committed)
└── src/                               # Your code
```

## Security

- `token_do_not_commit/` in `.gitignore`
- `.claude/state/` in `.gitignore` (session state, not committed)
- YubiKey FIDO2 signing optional (see CLAUDE.md template)
- Never commit credentials; use vault-managed secrets
- Guard-system self-protection prevents the workflow from rewriting its own rules
