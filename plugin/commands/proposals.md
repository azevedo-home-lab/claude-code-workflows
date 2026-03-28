---
description: Manage workflow improvement proposals from claude-mem
---
Query claude-mem for observations tagged with type "proposal" for
the current project.

```bash
PROJECT=$(git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$//' | sed 's/.*[:/]\([^/]*\)$//')
echo "Project: $PROJECT"
```

Search claude-mem for proposals:
- Use the search MCP tool with query: "type:proposal"
- Filter to current project
- Sort by date descending

If the MCP tool returns an error, display: "claude-mem unavailable — cannot fetch proposals."

If no proposals found:
"No pending proposals. Run /evolve to trigger analysis, or wait for automatic analysis after 5 /complete cycles."

If proposals found, present each with:
- **Pattern:** pattern_name
- **Confidence:** confidence score (0.0–1.0)
- **Type:** proposal_type (skill|agent|config|command|behavior)
- **Target:** target_file
- **Proposed change:** proposed_change
- **Rationale:** rationale
- **Evidence:** supporting_obs_ids (link to /obs-read)
- **Deferred:** "(deferred N times)" if deferred_count > 0

For each proposal, ask: **Approve** / **Reject** / **Defer**

### Approve

Read `cl-plugin/agents/issue-creator.md`, then dispatch as `general-purpose` with runtime context:
- proposal: the full proposal JSON
- labels: from cl-config.json github.labels
- duplicate_check: from cl-config.json github.duplicate_check

Present the issue URL to the user on success.

### Reject

Update the proposal in claude-mem: set status to "rejected".
Ask user for optional rejection reason. If provided, include in the update.

### Defer

Update the proposal in claude-mem: set status to "deferred", increment deferred_count.
