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

### Step 4: Smart Documentation Detection

Dispatch a **Docs detector agent** — read `plugin/agents/docs-detector.md`, then dispatch as `general-purpose`:

Context: "Changed files: [LIST from git diff --name-only main...HEAD plus unstaged/untracked]."

Present recommendations and ask: "Update these now? (yes / no / skip)"
- If **yes** → make the documentation updates
- If **no/skip** → proceed without docs update

#### Step 4 Review Gate

After presenting doc recommendations (whether updates were made or skipped), dispatch a **review agent** — read `plugin/agents/docs-reviewer.md`, then dispatch as `general-purpose` — to verify completeness:

Context: "Changed files: [LIST FROM git diff]. Recommendations made: [LIST]."

If REDO: fix and re-dispatch. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 4 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "docs_checked" "true"
```

### Step 5: Commit & Push

Stage all changed files relevant to the task and commit:

1. Run `git status` and `git diff --stat`
2. Stage the relevant files (prefer specific files over `git add -A`)
2b. **Version verification:** Verify the version bump was done during IMPLEMENT.

Run `scripts/check-version-sync.sh` to validate both version files match.
Then verify the version is greater than the last release tag:
```bash
CURRENT=$(jq -r '.plugins[0].version // .version' .claude-plugin/marketplace.json)
LAST_TAG=$(git tag -l 'v*' --sort=-v:refname | head -1 | sed 's/^v//')
echo "Current: $CURRENT, Last tag: ${LAST_TAG:-none}"
```

If version bump was not done (version matches or is less than last tag), flag as validation failure:
> "Version bump missing — loop back to `/implement` and run the versioning step."

Include version files in the commit staging if they were modified.
3. Draft a concise conventional commit message explaining why
4. Commit using conventional commit format. Use your current model name (from the "You are powered by the model named..." line in your environment context) in the Co-Authored-By line:

       Co-Authored-By: <your model name> <noreply@anthropic.com>
If clean working tree: skip and note "Nothing to commit."

#### Push to Remote

After committing, push to the remote:

1. Check if there are commits to push:
```bash
AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || git rev-list --count origin/$(git symbolic-ref --short HEAD)..HEAD 2>/dev/null || echo "unknown")
echo "Commits ahead of remote: $AHEAD"
```

2. If ahead > 0, ask: "Push to remote? (yes / no)"
   - At **all autonomy levels**: always ask before pushing. Push is never automatic.
   - If **yes**: warn about YubiKey, then push:
     ```
     ========== YUBIKEY: TOUCH NOW FOR GIT PUSH ==========
     ```
     ```bash
     git push origin HEAD
     ```
   - If **no**: note "Push deferred — run `git push` manually when ready."

3. If no upstream or unknown: skip push, note "No remote tracking branch — push skipped."

4. After push (or skip), mark informational milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "pushed" "true"
```
This is NOT an exit gate — just tracks whether push happened.

#### Step 5 Review Gate

After committing (or skipping), dispatch a **review agent** — read `plugin/agents/commit-reviewer.md`, then dispatch as `general-purpose` — to verify commit quality:

Context: "Review the most recent commit."

If REDO: fix (amend commit or create new commit) and re-dispatch. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 5 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."
If step was skipped (nothing to commit): skip this gate.

Mark milestone (also mark if skipped — clean tree means committed is N/A):
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "committed" "true"
```

### Step 6: Branch Integration & Worktree Cleanup

Check if work was done on a feature branch or in a worktree:

```bash
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
MAIN_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || echo "main")
IN_WORKTREE=$(git rev-parse --git-common-dir 2>/dev/null | grep -q "\.git/worktrees" && echo "true" || echo "false")
echo "Current branch: $CURRENT_BRANCH"
echo "Main branch: $MAIN_BRANCH"
echo "In worktree: $IN_WORKTREE"
```

**If on a feature branch (not main/master):**

Use `superpowers:finishing-a-development-branch` to present integration options:
1. **Create PR and merge** — create a pull request, review it, merge to main
2. **Merge directly** — fast-forward or merge commit to main locally
3. **Leave on branch** — keep changes on the feature branch for later

Recommend option 1 (PR) for non-trivial changes, option 2 for small fixes.

After merge, push main to remote if the user approves.

**If in a worktree:**

After the branch is merged, clean up:
```bash
# From the main project directory (not the worktree)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
MAIN_PROJECT=$(git rev-parse --git-common-dir | sed 's|/\.git/worktrees/.*||')
echo "Worktree at: $WORKTREE_PATH"
echo "Main project at: $MAIN_PROJECT"
echo "Clean up worktree? (yes / no)"
```
If **yes**: first verify the branch was merged:
```bash
# Verify branch was merged before cleanup
UNMERGED=$(git log origin/$MAIN_BRANCH..$CURRENT_BRANCH --oneline 2>/dev/null)
if [ -n "$UNMERGED" ]; then
    echo "WARNING: Branch has unmerged commits:"
    echo "$UNMERGED"
    echo "Proceed with cleanup anyway? (yes / no)"
fi
```
If no unmerged commits (or user confirms anyway): `git worktree remove <path>` and `git branch -d <branch>`
If user declines: note that worktree is still active with unmerged work
If **no**: note that worktree is still active

**If on main already:** skip this step.

### Step 7: Tech Debt Audit

**First, review tracked observations from prior sessions:**

```bash
TRACKED=$(.claude/hooks/workflow-cmd.sh get_tracked_observations)
echo "Tracked observations: ${TRACKED:-none}"
```

If the tracked list is non-empty, fetch them via `get_observations([IDs])` and for each:
- **Resolved this session?** → mark as RESOLVED in the table below (will be removed from tracked list in Step 8)
- **Still open?** → mark as OPEN in the table below (will be kept in tracked list in Step 8)

Build two in-memory lists: `KEEP_IDS` (still-open observation IDs) and `RESOLVED_IDS` (completed this session). These are used by Step 8 — **do not modify tracked_observations here**.

#### Collect and Categorize Findings

Gather all findings from these sources:
- Decision record's "accepted trade-offs" and "tech debt acknowledged" entries
- Review phase findings (if review was run — check the decision record's Review Findings section)
- Steps 1-3 validation results (boundary tester, devil's advocate findings)

Group findings into these categories:

| Category | GitHub Label | What goes here |
|----------|-------------|---------------|
| Security | `security` | Bypass vectors, injection risks, secret exposure, auth gaps |
| Robustness | `robustness` | Race conditions, error handling, fail-open/closed, resilience |
| Feature | `feature` | Missing capabilities, incomplete implementations |
| Tech Debt | `tech-debt` | Code quality, duplication, pattern inconsistency |
| Documentation | `documentation` | Stale references, missing docs, README drift |

**Skip empty categories.** Only present categories that have findings.

#### Present Categorized Table

For each non-empty category, present a table with concrete improvement proposals:

**[Category] ([N] items):**

| Item | Impact | Proposed Fix | Effort | Priority |
|---|---|---|---|---|
| <description> | <what could go wrong> | <specific fix> | S/M/L | High/Medium/Low |

Don't just list debt — recommend what to do about it. The user should leave this step with actionable next steps, not just a list of problems.

#### Save Category Observations

For each non-empty category, save a single claude-mem observation:
- **Title:** `Open Issue — [Category]: [summary] (YYYY-MM-DD)`
- **Type:** `discovery`
- **Project:** derived from git remote (`git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`)
- **Narrative:** All items in that category with details, effort estimates, priority, and related observation IDs

Autonomy gating for observations:
- **auto (▶▶▶):** Auto-save all category observations
- **ask (▶▶):** Auto-save all category observations
- **off (▶):** Ask per-category "Save observation? (y/n)"

#### GitHub Issue Creation

After saving observations, create GitHub issues per category:

- **auto (▶▶▶):** Auto-create for High/Medium priority categories. Skip Low.
- **ask (▶▶):** Ask per-category "Create GitHub issue? (y/n)"
- **off (▶):** Ask per-item "Create GitHub issue? (y/n)"

For each issue to create:
1. Check `gh` is available: `gh auth status 2>&1`. If not, skip gracefully: "Skipping GitHub issue creation — gh CLI not available."
2. Ensure label exists: `gh label create "<label>" --description "<desc>" 2>/dev/null || true`
3. Create: `gh issue create --title "[Category] Summary" --body "<all items with details, effort, priority>" --label "<category-label>"`
4. Capture the issue URL from output
5. Store mapping: `.claude/hooks/workflow-cmd.sh set_issue_mapping "<obs_id>" "<issue_url>"`
6. Report: "Created issue: <url>"

The issue mapping makes observation IDs clickable in the status line (links to GitHub issues via OSC 8 hyperlinks).

#### Temp File Cleanup

After issue creation, clean up agent artifacts:

```bash
rm .claude/tmp/* 2>/dev/null || true
echo "Cleaned up .claude/tmp/"
```

#### Step 7 Review Gate

After presenting the categorized tech debt table, dispatch a **review agent** — read `plugin/agents/tech-debt-reviewer.md`, then dispatch as `general-purpose` — to verify proposal quality:

Context: "Decision record: [DECISION_RECORD_PATH]. Categorized tech debt table: [TABLE]."

If REDO: fix and re-dispatch. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 7 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "tech_debt_audited" "true"
```

### Step 8: Handover (Claude-Mem Observation)

Dispatch a **Handover writer agent** — read `plugin/agents/handover-writer.md`, then dispatch as `general-purpose`:

Context: "Prepare a claude-mem handover observation. Project name: [derived from git remote get-url origin]. Decision record: [DECISION_RECORD_PATH]. Include commit hash, verification results, key decisions, gotchas, files modified, tech debt."

Save via the `save_observation` MCP tool. **Set `project` to the GitHub repo name.** Derive it: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`

#### Step 8 Review Gate

After saving the handover observation, dispatch a **review agent** — read `plugin/agents/handover-reviewer.md`, then dispatch as `general-purpose` — to verify handover quality:

Context: "Review the handover observation just saved."

If REDO: fix and re-save the observation, then re-dispatch. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 8 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

After saving the handover observation, build the final tracked observations list atomically:

1. Take `KEEP_IDS` from Step 7 (still-open items)
2. Add the handover observation ID
3. Add any new tech debt observation IDs saved during this step
4. Write the complete list in a single call:

```bash
.claude/hooks/workflow-cmd.sh set_tracked_observations "<KEEP_IDS>,<HANDOVER_ID>,<NEW_TECH_DEBT_IDS>"
```

This atomic replace ensures crash safety — if the session dies before this line, the previous tracked list is fully intact.

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "handover_saved" "true"
```

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
