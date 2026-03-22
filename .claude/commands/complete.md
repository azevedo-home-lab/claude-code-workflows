Transition the workflow to COMPLETE phase. First check for soft gate warnings:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh"
WARN=$(check_soft_gate "complete")
if [ -n "$WARN" ]; then
    echo "WARNING: $WARN"
fi
```

If a warning was shown, ask the user: "Review hasn't been run. The workflow should be followed for best results. Proceed anyway?" If they say no, stop. If yes or no warning, continue:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete" && reset_completion_status && set_active_skill "completion-pipeline"
echo "Phase set to COMPLETE — running completion pipeline. Code edits blocked, doc updates allowed."
```

Then confirm the phase change and execute the completion pipeline below.

Before proceeding:
1. Read `docs/reference/professional-standards.md` — apply the Universal Standards and COMPLETE Phase Standards throughout this phase.

---

## Completion Pipeline

**Execute all steps in order. Missing artifacts cause steps to be skipped gracefully — the pipeline never hard-blocks.**

**Autonomy-aware behavior:**
- **Level 3 (▶▶▶):** Make operational decisions autonomously: auto-commit, auto-update docs (yes), auto-select recommended options. Only stop for git push (always requires confirmation) and validation failures that need user judgment.
- **Level 1-2:** Ask the user at each decision point (doc updates, commit, push, tech debt actions).

### Step 1: Plan Validation

**Before starting validation**, invoke the `superpowers:verification-before-completion` skill to load evidence-before-assertions rules into context.

Read the decision record path:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh"
echo "Decision record: $(get_decision_record)"
```

**If a plan file exists** (check `docs/superpowers/plans/`, `docs/plans/`, or any plan referenced in the decision record):

Dispatch a **Plan validator agent** to:
1. Read the plan file
2. Extract every deliverable, acceptance criterion, and expected outcome
3. Classify each as structural (file exists) or behavioral (must demonstrate)
4. For behavioral deliverables: exercise and show output, don't just grep
5. Return a checklist with PASS/FAIL and evidence for each

**If no plan file exists**: report "No plan file found — skipping plan validation" and mark as done.

Mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "plan_validated" "true"
```

### Step 2: Outcome Validation

**Find the outcome source** — check in this order:
1. Decision record (from `get_decision_record`) → Problem section with outcomes
2. Design spec (check `docs/superpowers/specs/`) → Problem section or Requirements
3. Implementation plan (check `docs/superpowers/plans/`, `docs/plans/`) → Goal and deliverables

Use the first source found. If the workflow started at `/discuss` (no decision record), the spec and plan still define what success looks like.

Dispatch an **Outcome validator agent** to:
1. Read the outcome source document
2. Extract every outcome, success metric, and acceptance criterion
3. For each outcome, require behavioral evidence — demonstrate, don't just grep
4. For each success metric: verify if immediately testable, flag as "TO MONITOR" if long-term
5. **Flag manual steps** — if the spec defines steps that require user action (key generation, service registration, hardware setup), list them as outcomes that need E2E verification. Guide the user through verification rather than skipping.
6. Return an outcome checklist with PASS/FAIL/MANUAL and evidence

**If no outcome source found**: report "No outcome definition found — skipping outcome validation" and mark as done.

Mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "outcomes_validated" "true"
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

#### Step 3 Review Gate

After presenting validation results, dispatch a **review agent** (subagent_type: `superpowers:code-reviewer`) to verify presentation quality:

Prompt: "Review the validation results just presented to the user. Read the decision record at [DECISION_RECORD_PATH]. Quality criteria: (1) Every plan deliverable is listed in a table with columns: Task, Deliverable, Status, Evidence. No deliverables are summarized as just 'N/N PASS' without individual rows. (2) Every outcome is listed in a table with columns: #, Outcome, Status, Evidence. Each row has specific evidence (file:line, test name, command output) — not vague claims. (3) The Outcome Verification section in the decision record matches what was presented. Return: PASS if all criteria met, or REDO with specific issues to fix."

If REDO: fix the issues and re-dispatch the reviewer. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 3 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "results_presented" "true"
```

### Step 4: Smart Documentation Detection

Dispatch a **Docs detector agent** to:
- Analyze `git diff --name-only main...HEAD` plus unstaged/untracked files
- Recommend which docs/README need updating based on what changed
- Return specific recommendations

Present recommendations and ask: "Update these now? (yes / no / skip)"
- If **yes** → make the documentation updates
- If **no/skip** → proceed without docs update

#### Step 4 Review Gate

After presenting doc recommendations (whether updates were made or skipped), dispatch a **review agent** (subagent_type: `superpowers:code-reviewer`) to verify completeness:

Prompt: "Review the documentation detection results. Changed files: [LIST FROM git diff]. Recommendations made: [LIST]. Quality criteria: (1) Every changed code file that introduces new user-facing behavior, commands, or configuration was checked for doc impact. (2) If updates were made, verify the updates match what actually changed (no stale or inaccurate doc claims). (3) If updates were skipped, the user was told what they're skipping. Return: PASS if complete, or REDO with specific gaps."

If REDO: fix and re-dispatch. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 4 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "docs_checked" "true"
```

### Step 5: Commit & Push

Stage all changed files relevant to the task and commit:

1. Run `git status` and `git diff --stat`
2. Stage the relevant files (prefer specific files over `git add -A`)
3. Draft a concise conventional commit message explaining why
4. Commit with YubiKey touch banner:
   ```bash
   echo "========== YUBIKEY: TOUCH NOW FOR GIT COMMIT ==========" && git commit -m "$(cat <<'EOF'
   <type>: <description>

   Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```
5. Ask: "Push to remote? (yes / no)"

If clean working tree: skip and note "Nothing to commit."

#### Step 5 Review Gate

After committing (or skipping), dispatch a **review agent** (subagent_type: `superpowers:code-reviewer`) to verify commit quality:

Prompt: "Review the most recent git commit. Run `git log -1 --format='%s%n%n%b'` and `git diff HEAD~1 --stat`. Quality criteria: (1) Commit message explains WHY, not just WHAT — it should describe the motivation, not just list changed files. (2) All files relevant to the task are included — check `git status` for leftover unstaged/untracked files that should be committed. (3) No sensitive files (.env, credentials, secrets) are committed. Return: PASS if all criteria met, or REDO with specific issues."

If REDO: fix (amend commit or create new commit) and re-dispatch. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 5 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."
If step was skipped (nothing to commit): skip this gate.

Mark milestone (also mark if skipped — clean tree means committed is N/A):
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "committed" "true"
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
If **yes**: `git worktree remove <path>` and `git branch -d <branch>`
If **no**: note that worktree is still active

**If on main already:** skip this step.

### Step 7: Tech Debt Audit

Before closing, review the decision record for any "accepted trade-offs" or "tech debt acknowledged" entries. **For each item, propose a concrete improvement:**

| Trade-off | Impact | Proposed Fix | Effort | Priority |
|---|---|---|---|---|
| <description> | <what could go wrong> | <specific fix> | <S/M/L> | <high/medium/low> |

Don't just list debt — recommend what to do about it. The user should leave this step with actionable next steps, not just a list of problems.

Present the table and ask: "Want to create tickets/issues for any of these, or note them for the next session?"

#### Step 7 Review Gate

After presenting the tech debt table, dispatch a **review agent** (subagent_type: `superpowers:code-reviewer`) to verify proposal quality:

Prompt: "Review the tech debt audit just presented. Read the decision record at [DECISION_RECORD_PATH] for trade-offs and tech debt entries. Quality criteria: (1) Every trade-off or tech debt entry from the decision record is addressed — none are silently dropped. (2) Each item has a concrete proposed fix (not just 'should be fixed later'). (3) Each item has an effort estimate (S/M/L) and priority (high/medium/low). (4) Impact column describes what could go wrong if not addressed, not just restating the debt. Return: PASS if all criteria met, or REDO with specific issues."

If REDO: fix and re-dispatch. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 7 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "tech_debt_audited" "true"
```

### Step 8: Handover (Claude-Mem Observation)

Dispatch a **Handover writer agent** to prepare a claude-mem observation. The handover must be useful to a stranger — include:
- What was built or changed
- Commit hash (from `git rev-parse --short HEAD`)
- Verification results (tests, deliverables, outcomes)
- Key decisions made
- Gotchas or learnings for future sessions
- Files modified (key files, not exhaustive)
- Tech debt and unresolved items

Save via the `save_observation` MCP tool. **Set `project` to the GitHub repo name.** Derive it: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`

#### Step 8 Review Gate

After saving the handover observation, dispatch a **review agent** (subagent_type: `superpowers:code-reviewer`) to verify handover quality:

Prompt: "Review the handover observation just saved. Quality criteria: (1) A stranger who knows nothing about this session can understand: what was built, why these choices, what's left to do. (2) Includes: commit hash, test results, key decisions, gotchas/learnings, files modified, tech debt items. (3) Minimum 500 characters (a useful handover cannot be shorter). (4) Does not contain vague claims like 'fixed the thing' or 'all tests pass' without specifying what tests and how many. Return: PASS if all criteria met, or REDO with specific issues."

If REDO: fix and re-save the observation, then re-dispatch. Max 3 iterations, then surface to user.
**After the gate passes (or on each iteration):** present a summary to the user: "Step 8 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_completion_field "handover_saved" "true"
```

### Step 9: Phase Transition

**HARD GATE: `set_phase("off")` will refuse if any completion milestone is incomplete. All 7 milestones must be marked true before the workflow can close.**

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
echo "Task complete. Phase set to OFF — workflow enforcement disabled."
```

Confirm to the user that the task is complete and the workflow has reset to OFF phase.
