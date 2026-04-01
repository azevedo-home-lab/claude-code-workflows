# Step 2: Converge

After the user narrows to 2-3 candidate approaches, **dispatch converge agents**:

1. **Codebase analyst** — Read `plugin/agents/codebase-analyst.md`, then dispatch as `general-purpose`. Context: "Shortlisted approaches: [APPROACH_LIST]. Analyze which fit the current architecture."
2. **Risk assessor** — Read `plugin/agents/risk-assessor.md`, then dispatch as `general-purpose`. Context: "Shortlisted approaches: [APPROACH_LIST]. Assess risks for each."

Present 2-3 viable approaches (discovered possibilities filtered through codebase reality) with your recommendation. Include trade-offs and tech debt implications for each.

After user selects an approach, enrich the plan with:

```markdown
## Approaches Considered (DISCUSS phase — diverge)
### Approach A: <name>
- Description, Pros/cons, Source

### Approach B: <name>
- Description, Pros/cons, Source

## Decision (DISCUSS phase — converge)
- **Chosen approach:** <which and why>
- **Rationale:** Why this over alternatives
- **Trade-offs accepted:** What downsides we're taking on
- **Risks identified:** What could go wrong
- **Constraints applied:** What codebase factors narrowed options
- **Tech debt acknowledged:** Deliberate shortcuts
```

After updating the plan with the chosen approach, mark the milestone:
```bash
.claude/hooks/workflow-cmd.sh set_discuss_field "approach_selected" "true"
```

### Spec to Issue Linking

After the spec passes review, commit the spec file (use separate commands):

```bash
git add <SPEC_PATH>
```
```bash
git commit -m "docs: add spec for <feature>"
```

Then get the commit hash for traceability:

```bash
COMMIT_HASH=$(git rev-parse --short HEAD)
```

Check if this work maps to an existing GitHub issue. If there are tracked observation IDs with GitHub issue mappings, or if the user mentioned a specific issue number, post a comment linking to the spec and commit:

```bash
gh issue comment <ISSUE_NUMBER> --body "## Design

**Commit:** <COMMIT_HASH>
**Spec:** \`<SPEC_PATH>\`

Approach: <chosen approach name>"
```

If no issue is mapped, skip this step silently — not all work originates from a GitHub issue.
