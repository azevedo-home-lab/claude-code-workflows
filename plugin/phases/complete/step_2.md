# Step 2: Outcome Validation

**Find the outcome source** — check in this order:
1. Plan (from `get_plan_path`) → Problem section with outcomes
2. Design spec (check `docs/specs/`) → Problem section or Requirements
3. Implementation plan (check `docs/plans/`) → Goal and deliverables

Use the first source found. If the workflow started at `/discuss` (no plan), the spec and plan still define what success looks like.

Dispatch an **Outcome validator agent** — read `plugin/agents/outcome-validator.md`, then dispatch as `general-purpose`:

Context: "Outcome source: [OUTCOME_SOURCE_PATH]. Exception: do NOT re-run the full test suite. Reference the IMPLEMENT result (tests_passing=true) and verify test *coverage* by reading the test file instead. Flag manual steps that require user action."

Also dispatch a **Boundary tester agent** alongside the outcome validator — read `plugin/agents/boundary-tester.md`, then dispatch as `general-purpose` with `isolation: "worktree"`:

Context: "Changed files: [LIST from git diff --name-only main...HEAD]. Plan/spec: [PLAN_OR_SPEC_PATH]."

Finally, dispatch a **Devil's advocate agent** (runs after boundary tester, reads code not spec) — read `plugin/agents/devils-advocate.md`, then dispatch as `general-purpose` with `isolation: "worktree"`:

Context: "Implementation files from git diff main...HEAD. Your job is to break this implementation."

**If no outcome source found**: report "No outcome definition found — skipping outcome validation" and mark as done.

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "outcomes_validated" "true"
```
