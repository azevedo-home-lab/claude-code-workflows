# Step 3: Output

Create the plan at `docs/plans/YYYY-MM-DD-<topic>.md` with the **Problem** section populated:

```markdown
# Decision Record: <topic>

## Problem (DEFINE phase)
- Problem statement
- Who is affected and why it matters now
- Current state / workarounds
- Measurable outcomes with verification methods
- Success metrics with targets
- Scope: in / out / constraints
```

Only the structured, converged version is written to the plan (raw diverge findings are conversation context, not persisted).

Commit the plan (use separate commands):

```bash
git add docs/plans/YYYY-MM-DD-<topic>.md
```
```bash
git commit -m "docs: add plan for <topic>"
```

Register the plan path:

```bash
.claude/hooks/workflow-cmd.sh set_plan_path "docs/plans/YYYY-MM-DD-<topic>.md"
```

### Decision Record to Issue Linking

Get the commit hash and link the plan to the originating GitHub issue (if one exists):

```bash
COMMIT_HASH=$(git rev-parse --short HEAD)
```

If there are tracked observation IDs with GitHub issue mappings, or if the user mentioned a specific issue number, post a comment:

```bash
gh issue comment <ISSUE_NUMBER> --body "## Problem Defined

**Commit:** <COMMIT_HASH>
**Plan:** \`<DECISION_RECORD_PATH>\`

Problem: <one-line problem statement>
Outcomes: <N> measurable outcomes defined"
```

If no issue is mapped, skip this step silently.

Confirm to the user: "Problem and outcomes saved to the plan. Run `/discuss` to proceed to solution design."
