# Step 1: Plan Validation

**Before starting validation**, invoke the `superpowers:verification-before-completion` skill to load evidence-before-assertions rules into context.

Read the plan path:
```bash
echo "Plan: $(.claude/hooks/workflow-cmd.sh get_plan_path)"
```

**If a plan file exists**:

Dispatch a **Plan validator agent** — read `plugin/agents/plan-validator.md`, then dispatch as `general-purpose`:

Context: "Plan file: [PLAN_PATH]. Exception: do NOT re-run the full test suite. The IMPLEMENT phase already ran it as an exit gate. Instead, verify test *coverage* by reading the test file — check that tests exist for each deliverable and reference the IMPLEMENT result (tests_passing=true) as evidence."

**If no plan file exists**: report "No plan file found — skipping plan validation" and mark as done.

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "plan_validated" "true"
```
