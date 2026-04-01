# Step 9: Present Summary and Close

All 8 milestones must be marked true before the workflow can close.

**Present the handover summary NOW — before asking the user to run `/off`.** The `/off` command clears workflow state, so this is the last chance to present a meaningful summary.

```
## Session Complete

**Handover observation:** #<ID> (saved to claude-mem, project: <repo-name>)
**Commit:** <hash> on <branch>
**Tests:** <count> passing

### What was done
- <1-2 sentence summary of each work stream>

### Open issues / next steps
- <tech debt items from Step 7, prioritized>
- <tracked observation IDs still open>

### For next session
Load handover: `get_observations([<ID>])`
Load open issues: `get_observations([<TRACKED_IDS>])`
```

## Issue Closure

After presenting the summary, close any GitHub issues that were resolved by this work:

1. Check issue mappings: `.claude/hooks/workflow-cmd.sh get_field "issue_mappings"`
2. Get the shipping commit hash: `git rev-parse --short HEAD`
3. For each mapped issue that was fully resolved:

```bash
gh issue close <ISSUE_NUMBER> --comment "Shipped in commit <HASH> on branch <BRANCH>.

Spec: <SPEC_PATH>
Plan: <PLAN_PATH>"
```

Only close issues where all tasks are completed. If partial, add a progress comment instead.

If `gh` is not available, skip gracefully.

After presenting the summary, tell the user:

```
Run `/off` to close the workflow.
```
