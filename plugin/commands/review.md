!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "review"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "review" && .claude/hooks/workflow-cmd.sh reset_review_status && .claude/hooks/workflow-cmd.sh set_active_skill "review-pipeline" && echo "Phase set to REVIEW — running review pipeline."; fi`

If the output shows `SOFT_GATE_WARNING`, ask the user: "Proceed anyway? (yes/no)". If yes, run the phase transition manually. If no, stop.

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and REVIEW Phase Standards throughout this phase.

---

## Review Pipeline

**You MUST execute all steps in order. Do not skip any step.**

### Step 1: Run Tests

Look for test commands in the project:
- `tests/run-tests.sh` or similar test scripts in `tests/` directory
- `package.json` with test scripts (`npm test`)
- `pytest`, `make test`, `cargo test`, etc.

If tests found, run them and capture the output.
- If tests **pass**: report the result and continue.
- If tests **fail**: report the failures and ask: "Tests failed. Fix now or continue review?"
- If **no tests found**: report "No tests found — skipping verification" and continue.

Update state after this step:
```bash
.claude/hooks/workflow-cmd.sh set_review_field "verification_complete" "true"
```

### Step 2: Detect Changed Files

Run these three commands and combine the results (deduplicate):
```bash
# Committed changes since main
git diff --name-only main...HEAD 2>/dev/null || true
# Unstaged changes
git diff --name-only
# Untracked files
git ls-files --others --exclude-standard
```

If no changes detected, report "No changes to review" and skip to the end. Update state with `agents_dispatched: true`, `findings_presented: true`, `findings_acknowledged: true`.

### Step 3: Dispatch 4 Review Agents in Parallel

Launch all four agents simultaneously using the Agent tool (4 parallel calls in one message). Pass each agent the list of changed files as runtime context.

**Agent 1 — Code Quality Reviewer** (subagent_type: "workflow-manager:code-quality-reviewer")
Context: "Changed files: [LIST]"

**Agent 2 — Security Reviewer** (subagent_type: "workflow-manager:security-reviewer")
Context: "Changed files: [LIST]"

**Agent 3 — Architecture & Plan Compliance Reviewer** (subagent_type: "workflow-manager:architecture-reviewer")

Before dispatching Agent 3, find the plan file path: check `docs/superpowers/plans/` and `docs/plans/` for the most recent `.md` file. If found, include it in the context.

Context: "Changed files: [LIST]. Plan file: [PLAN_PATH or 'no plan file found']"

**Agent 4 — Governance & Production Readiness Reviewer** (subagent_type: "workflow-manager:governance-reviewer")
Context: "Changed files: [LIST]"

If any agent fails or times out, note which agent failed and proceed with findings from agents that succeeded.

### Step 4: Dispatch Verification Agent

After all 4 review agents return, dispatch a single verification agent (subagent_type: "workflow-manager:review-verifier"):

Context: "Candidate findings from 4 review agents: [ALL FINDINGS FROM STEP 3]"

### Step 5: Consolidate, Persist, and Present Findings

Take the verified findings and:

1. Deduplicate: same file+line from multiple agents → merge
2. Rank by severity: Critical → Warning → Suggestion
3. **Persist to decision record**: Read `get_decision_record` for the path. If a decision record exists, write the findings to its Review Findings section. If no decision record, skip persistence and note it.

4. Present the report:

```
## Review Findings

### Critical (must fix before merge)
Prefix findings with category: [QUAL] code quality, [SEC] security, [ARCH] architecture, [GOV] governance
- [findings or "None"]

### Warnings (should fix)
- [findings or "None"]

### Suggestions (nice to have)
- [findings or "None"]

---
Would you like to:
1. Fix issues now (stay in REVIEW phase, re-run /review after fixing)
2. Proceed to /complete (acknowledge findings as-is)
```

Update state:
```bash
.claude/hooks/workflow-cmd.sh set_review_field "agents_dispatched" "true"
.claude/hooks/workflow-cmd.sh set_review_field "findings_presented" "true"
```

Wait for the user's response. If they choose option 2 (acknowledge):
```bash
.claude/hooks/workflow-cmd.sh set_review_field "findings_acknowledged" "true"
```

**Auto-transition:** If autonomy is auto: fix ALL findings — critical, warnings, and suggestions. Only stop if there are critical findings or decisions that require user judgment. Do not acknowledge findings without fixing them unless the user has explicitly accepted them. After all findings are fixed, invoke `/complete` now. Do not wait for the user.
