---
description: Validate outcomes, commit, audit tech debt, and save handover
disable-model-invocation: true
---
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "complete"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "complete" && .claude/hooks/workflow-cmd.sh reset_completion_status && .claude/hooks/workflow-cmd.sh set_active_skill "completion-pipeline" && echo "Phase set to COMPLETE — running completion pipeline."; fi`

Present the output to the user.

If the output shows `SOFT_GATE_WARNING`, ask the user: "Review hasn't been run. Proceed anyway?" If no, stop. If yes, run the phase transition manually.

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and COMPLETE Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

---

## Completion Pipeline

**Execute all steps in order. Missing artifacts cause steps to be skipped gracefully — the pipeline never hard-blocks.**

**Autonomy-aware behavior:**
- **auto (▶▶▶):** Make operational decisions autonomously: auto-commit, auto-update docs (yes), auto-select recommended options. Only stop for git push (always requires confirmation) and validation failures that need user judgment.
- **ask (▶▶):** Ask the user at each decision point (doc updates, commit, push, tech debt actions).
- **off (▶):** After each pipeline step (validation, docs, commit, push, tech debt, handover), present the result and wait for explicit approval before proceeding to the next step. Never batch steps.

### Pre-validation: Test Evidence Gate

Before running the completion pipeline, check if tests need to re-run:

1. Read `tests_last_passed_at` from workflow state:
```bash
TESTS_COMMIT=$(.claude/hooks/workflow-cmd.sh get_tests_passed_at)
echo "Tests last passed at: $TESTS_COMMIT"
```

2. If set, check what changed since then:
```bash
git diff --name-only $TESTS_COMMIT..HEAD
```

3. Classify changed files using a **safe-to-skip whitelist** — only skip test re-run if ALL changed files match:
   - **Safe to skip** (non-code): `docs/**/*.md`, `*.txt`, `.gitignore`, `LICENSE`, `README.md`, `CHANGELOG.md`
   - **Everything else is code** — treat as requiring test re-run
   - Rule: if in doubt, treat as code (run tests)

4. If ALL changed files are safe to skip:
   - Present evidence: "No code files changed since tests passed at commit [hash]. Git diff shows only: [list]. Using previous test results as evidence."
   - Skip test re-run

5. If code files changed OR `tests_last_passed_at` is not set:
   - Run full test suite
   - Store the result: `.claude/hooks/workflow-cmd.sh set_tests_passed_at "$(git rev-parse HEAD)"`

### Step 1: Plan Validation

**Before starting validation**, invoke the `superpowers:verification-before-completion` skill to load evidence-before-assertions rules into context.

Read the decision record path:
```bash
echo "Decision record: $(.claude/hooks/workflow-cmd.sh get_decision_record)"
```

**If a plan file exists** (check `docs/superpowers/plans/`, `docs/plans/`, or any plan referenced in the decision record):

Dispatch a **Plan validator agent** — read `plugin/agents/plan-validator.md`, then dispatch as `general-purpose`:

Context: "Plan file: [PLAN_PATH]. Exception: do NOT re-run the full test suite. The IMPLEMENT phase already ran it as an exit gate. Instead, verify test *coverage* by reading the test file — check that tests exist for each deliverable and reference the IMPLEMENT result (tests_passing=true) as evidence."

**If no plan file exists**: report "No plan file found — skipping plan validation" and mark as done.

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "plan_validated" "true"
```

### Step 2: Outcome Validation

**Find the outcome source** — check in this order:
1. Decision record (from `get_decision_record`) → Problem section with outcomes
2. Design spec (check `docs/superpowers/specs/`) → Problem section or Requirements
3. Implementation plan (check `docs/superpowers/plans/`, `docs/plans/`) → Goal and deliverables

Use the first source found. If the workflow started at `/discuss` (no decision record), the spec and plan still define what success looks like.

Dispatch an **Outcome validator agent** — read `plugin/agents/outcome-validator.md`, then dispatch as `general-purpose`:

Context: "Outcome source: [OUTCOME_SOURCE_PATH]. Exception: do NOT re-run the full test suite. Reference the IMPLEMENT result (tests_passing=true) and verify test *coverage* by reading the test file instead. Flag manual steps that require user action."

Also dispatch a **Boundary tester agent** alongside the outcome validator — read `plugin/agents/boundary-tester.md`, then dispatch as `general-purpose` with `isolation: "worktree"`:

Context: "Changed files: [LIST from git diff --name-only main...HEAD]. Plan/spec: [PLAN_OR_SPEC_PATH]."

The boundary tester's results are presented in Step 3 as a **Boundary Tests** table alongside Plan Deliverables and Outcomes.

Finally, dispatch a **Devil's advocate agent** (runs after boundary tester, reads code not spec) — read `plugin/agents/devils-advocate.md`, then dispatch as `general-purpose` with `isolation: "worktree"`:

Context: "Implementation files from git diff main...HEAD. Your job is to break this implementation."

The devil's advocate's results are presented in Step 3 as a **Devil's Advocate** table.

**If no outcome source found**: report "No outcome definition found — skipping outcome validation" and mark as done.

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "outcomes_validated" "true"
```

### Step 3: Present Validation Results

**You MUST present the full evidence to the user — not just a summary.** The user cannot trust "24/24 PASS" without seeing what was checked and how.

Present validation results as two tables:

**Plan Deliverables:**

| Task | Deliverable | Status | Evidence |
|---|---|---|---|
| 1 | Function X exists | PASS | `file.sh:42` |
| 1 | Preserves state on transition | PASS | test "preserves across transitions" passes |
| ... | ... | ... | ... |

**Outcomes:**

| # | Outcome | Status | Evidence |
|---|---|---|---|
| 1 | User can select levels | PASS | `command.md` calls `set_level`, test passes |
| 2 | Status line shows symbols | PASS | `statusline.sh:107-114`, 5 tests pass |
| ... | ... | ... | ... |

**Boundary Tests:**

| # | Component | Edge Case | Expected | Actual | Status |
|---|-----------|-----------|----------|--------|--------|
| 1 | <component> | <edge case description> | <expected behavior> | <actual behavior> | PASS/FAIL |

**Devil's Advocate:**

| # | Attack Vector | Target | Result | Severity |
|---|--------------|--------|--------|----------|
| 1 | <attack type> | <target component> | <what happened> | Critical/Warning/Info |

Then enrich the decision record with the **Outcome Verification** section:

```markdown
## Outcome Verification (COMPLETE phase)
- [x] Outcome 1: <description> — PASS — evidence: <what was observed>
- [ ] Outcome 2: <description> — FAIL — evidence: <what went wrong>
- Success metric 1: <target> — MET/NOT MET/TO MONITOR
- **Unresolved items:** what's left for future work
- **Tech debt incurred:** what should be addressed next
```

**If any validation fails:**
- Present specific diagnosis with quantified fix effort
- Recommend the right next phase: "This is a code fix — I recommend `/implement` to address it, then `/review` to validate"
- Don't let the user skip without understanding consequences: "Acknowledging this gap means X. Are you comfortable shipping with that?"
- User decides: fix (jump to `/implement`), re-review, or acknowledge
- If validation finds critical issues:
  1. Document findings in the decision record's Open Issues section
  2. Save as claude-mem observations (one per category — Security, Robustness, Feature, etc.)
  3. Create GitHub issues for critical/high findings (autonomy-gated: auto → auto-create, ask → ask per-category, off → ask per-item)
  4. Continue the COMPLETE pipeline — commit what we have, the tech debt audit in Step 7 will include these findings
  5. Next session picks them up from tracked observations and GitHub issues

#### Step 3 Review Gate

After presenting validation results, dispatch a **review agent** — read `plugin/agents/results-reviewer.md`, then dispatch as `general-purpose` — to verify presentation quality:

Context: "Review the validation results. Decision record: [DECISION_RECORD_PATH]."

If REDO: fix the issues and re-dispatch the reviewer. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 3 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "results_presented" "true"
```

### Steps 4-6: Commit Pipeline

Dispatch a **commit-push-agent** — read `plugin/agents/commit-push-agent.md`, then dispatch as `general-purpose`:

Context: "Decision record: [DECISION_RECORD_PATH]. Changed files: [LIST from git diff --name-only main...HEAD plus unstaged/untracked]. Autonomy level: [LEVEL]."

Wait for the agent's result. Handle structured responses:

- If `PUSH_PENDING`: Ask the user "Push [N] commits to remote? (yes / no)". If yes, run `git push origin HEAD` and report. If no, note deferred.
- If `BRANCH_INTEGRATION_NEEDED`: Use `superpowers:finishing-a-development-branch` to present integration options.

All milestones (`docs_checked`, `committed`, `pushed`) are set by the agent.

### Step 7: Tech Debt Audit

Dispatch a **tech-debt-agent** — read `plugin/agents/tech-debt-agent.md`, then dispatch as `general-purpose`:

Context: "Decision record: [DECISION_RECORD_PATH]. Tracked observations: [LIST from get_tracked_observations]. Validation findings: [SUMMARY of Steps 1-3 results]. Autonomy level: [LEVEL]."

Wait for the agent's result. Present the categorized tech debt table to the user.

The `tech_debt_audited` milestone is set by the agent.

### Step 8: Handover

Dispatch a **handover-agent** — read `plugin/agents/handover-agent.md`, then dispatch as `general-purpose`:

Context: "Decision record: [DECISION_RECORD_PATH]. Project name: [derived from git remote]. Handoff data at .claude/tmp/tech-debt-handoff.json."

Wait for the agent's result. Report the handover observation ID to the user.

The `handover_saved` milestone is set by the agent.

### Step 9: Phase Transition

All 8 milestones must be marked true before the workflow can close.

Inform the user that the completion pipeline is finished and they should run `/off` to close the workflow:

```
Workflow complete. All milestones verified. Run `/off` to close the workflow.
```

After the user runs `/off` and the phase transition succeeds, output a **handover summary** for the user and for the next Claude Code session:

```
## Session Complete

**Handover observation:** #<ID> (saved to claude-mem, project: <repo-name>)
**Commit:** <hash> on <branch>
**Tests:** <count> passing

### What was done
- <1-2 sentence summary of each work stream>

### Open issues / next steps
- <tech debt items from Step 7, prioritized>

### For next session
Load handover: `get_observations([<ID>])`
```

This message serves two purposes: (1) the user sees a clean summary of what happened, and (2) the next Claude Code session can reference the observation ID to load full context.
