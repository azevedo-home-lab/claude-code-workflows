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
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "complete" && set_active_skill "completion-pipeline"
echo "Phase set to COMPLETE — running completion pipeline. Code edits blocked, doc updates allowed."
```

Then confirm the phase change and execute the completion pipeline below.

Before proceeding:
1. Read `docs/reference/professional-standards.md` — apply the Universal Standards and COMPLETE Phase Standards throughout this phase.

---

## Completion Pipeline

**Execute all steps in order. Missing artifacts cause steps to be skipped gracefully — the pipeline never hard-blocks.**

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

**If no plan file exists**: report "No plan file found — skipping plan validation" and continue.

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

**If no outcome source found**: report "No outcome definition found — skipping outcome validation" and continue.

### Step 3: Present Validation Results

Combine plan and outcome validation results. Enrich the decision record with the **Outcome Verification** section:

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

### Step 4: Smart Documentation Detection

Dispatch a **Docs detector agent** to:
- Analyze `git diff --name-only main...HEAD` plus unstaged/untracked files
- Recommend which docs/README need updating based on what changed
- Return specific recommendations

Present recommendations and ask: "Update these now? (yes / no / skip)"
- If **yes** → make the documentation updates
- If **no/skip** → proceed without docs update

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

Before closing, review the decision record for any "accepted trade-offs" or "tech debt acknowledged" entries. Present them:

"During this cycle we accepted these trade-offs: [list]. These should be tracked for future work."

### Step 8: Handover (Claude-Mem Observation)

Dispatch a **Handover writer agent** to prepare a claude-mem observation. The handover must be useful to a stranger — include:
- What was built or changed
- Commit hash (from `git rev-parse --short HEAD`)
- Verification results (tests, deliverables, outcomes)
- Key decisions made
- Gotchas or learnings for future sessions
- Files modified (key files, not exhaustive)
- Tech debt and unresolved items

Save via the `save_observation` MCP tool. Set `project` to match the current project.

### Step 9: Phase Transition

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "off"
echo "Task complete. Phase set to OFF — workflow enforcement disabled."
```

Confirm to the user that the task is complete and the workflow has reset to OFF phase.
