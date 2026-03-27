---
description: Run 5-agent review pipeline on changed files (quality, security, architecture, governance, hygiene)
disable-model-invocation: true
---
<!-- Do NOT invoke this command via the Skill tool. Use the native /command path only. -->
!`WARN=$(.claude/hooks/workflow-cmd.sh check_soft_gate "review"); if [ -n "$WARN" ]; then echo "SOFT_GATE_WARNING: $WARN"; else WF_SKIP_AUTH=1 .claude/hooks/workflow-cmd.sh set_phase "review" && .claude/hooks/workflow-cmd.sh reset_review_status && .claude/hooks/workflow-cmd.sh set_active_skill "review-pipeline" && echo "Phase set to REVIEW — running review pipeline."; fi`

Present the output to the user.

If the output shows `SOFT_GATE_WARNING`, ask the user: "Proceed anyway? (yes/no)". If yes, run the phase transition manually. If no, stop.

Before proceeding:
1. Read `plugin/docs/reference/professional-standards.md` — apply the Universal Standards and REVIEW Phase Standards throughout this phase.

**Skill Resolution:** Follow the process in `plugin/docs/reference/skill-resolution.md` before invoking skills.

**Agent Dispatch:** Follow `plugin/docs/reference/agent-dispatch.md` — read each agent's `.md` file, then dispatch as `general-purpose` with the file content + runtime context as the prompt.

---

## Review Pipeline

**You MUST execute all steps in order. Do not skip any step.**

### Step 1: Verify Tests Passed

The IMPLEMENT phase runs the full test suite as an exit gate (`tests_passing` milestone). Do NOT re-run the test suite here — use the IMPLEMENT result.

```bash
TESTS_PASSED=$(.claude/hooks/workflow-cmd.sh get_implement_field "tests_passing")
echo "IMPLEMENT tests_passing: $TESTS_PASSED"
```

- If `"true"`: report "Tests verified in IMPLEMENT phase" and continue.
- If not `"true"` or empty: tests may not have run or code changed since IMPLEMENT. Run the test suite now and report results.

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

### Step 3: Dispatch 5 Review Agents in Parallel

Launch all five agents simultaneously using the Agent tool (5 parallel calls in one message). Pass each agent the list of changed files as runtime context.

**Agent 1 — Code Quality Reviewer** — read `plugin/agents/code-quality-reviewer.md`, dispatch as `general-purpose`
Context: "Changed files: [LIST]"

**Agent 2 — Security Reviewer** — read `plugin/agents/security-reviewer.md`, dispatch as `general-purpose`
Context: "Changed files: [LIST]"

**Agent 3 — Architecture & Plan Compliance Reviewer** — read `plugin/agents/architecture-reviewer.md`, dispatch as `general-purpose`

Before dispatching Agent 3, find the plan file path: check `docs/superpowers/plans/` and `docs/plans/` for the most recent `.md` file. If found, include it in the context.

Context: "Changed files: [LIST]. Plan file: [PLAN_PATH or 'no plan file found']"

**Agent 4 — Governance & Production Readiness Reviewer** — read `plugin/agents/governance-reviewer.md`, dispatch as `general-purpose`
Context: "Changed files: [LIST]"

**Agent 5 — Codebase Hygiene Reviewer** — read `plugin/agents/codebase-hygiene-reviewer.md`, dispatch as `general-purpose`
Context: "Changed files: [LIST]"

If any agent fails or times out, note which agent failed and proceed with findings from agents that succeeded.

### Step 4: Dispatch Verification Agent

After all 5 review agents return, dispatch a single verification agent — read `plugin/agents/review-verifier.md`, dispatch as `general-purpose`:

Context: "Candidate findings from 5 review agents: [ALL FINDINGS FROM STEP 3]"

### Step 5: Consolidate, Persist, and Present Findings

Take the verified findings and:

1. Deduplicate: same file+line from multiple agents → merge
2. Rank by severity: Critical → Warning → Suggestion
3. **Persist to decision record**: Read `get_decision_record` for the path. If a decision record exists, write the findings to its Review Findings section. If no decision record, skip persistence and note it.

4. Present the report:

```
## Review Findings

### Critical (must fix before merge)
Prefix findings with category: [QUAL] code quality, [SEC] security, [ARCH] architecture, [GOV] governance, [HYG] codebase hygiene
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

**Autonomy-aware behavior:**
- **off (▶):** After each review agent returns, present its findings individually and wait for user review before dispatching the next agent. Do not batch all 5 agents in parallel — dispatch one at a time, presenting results between each.
- **ask (▶▶):** Dispatch all 5 agents in parallel, present consolidated findings, wait for user response.

**Step expectations — what each step must produce before you move on:**

| Step | What you do | Evidence required before next step | Milestone |
|------|-------------|-------------------------------------|-----------|
| Verify tests | Check `tests_passing` from IMPLEMENT | If not set: run tests now and show output | `verification_complete=true` |
| Detect changes | Run git diff + ls-files | File list visible | — |
| 5 agents | Dispatch all 5 in parallel | All agents returned (or noted if timed out) | `agents_dispatched=true` |
| Verification agent | Dispatch verifier on agent findings | Verifier returned | — |
| Present findings | Show consolidated Critical/Warning/Suggestion table | User sees the full table — never compress to "N issues" | `findings_presented=true` |
| Acknowledge | User chooses fix or proceed | User response received | `findings_acknowledged=true` |

**Auto-transition:** If autonomy is auto: fix ALL findings — critical, warnings, and suggestions. Only stop if there are critical findings or decisions that require user judgment. Do not acknowledge findings without fixing them unless the user has explicitly accepted them. After all findings are fixed, invoke `/complete` now. Do not wait for the user.
