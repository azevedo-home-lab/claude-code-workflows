# Step 4: Smart Documentation Detection

Dispatch a **Docs detector agent** — read `plugin/agents/docs-detector.md`, then dispatch as `general-purpose`:

Context: "Changed files: [LIST from git diff --name-only main...HEAD plus unstaged/untracked]."

Present recommendations and ask: "Update these now? (yes / no / skip)"
- If **yes** → make the documentation updates
- If **no/skip** → proceed without docs update

#### Step 4 Review Gate

After presenting doc recommendations (whether updates were made or skipped), dispatch a **review agent** — read `plugin/agents/docs-reviewer.md`, then dispatch as `general-purpose`:

Context: "Changed files: [LIST FROM git diff]. Recommendations made: [LIST]."

If REDO: fix and re-dispatch. Max 3 iterations, then surface to user.
Present summary: "Step 4 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "docs_checked" "true"
```
