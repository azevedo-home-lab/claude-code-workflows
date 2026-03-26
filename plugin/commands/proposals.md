Query claude-mem for observations tagged with type "proposal" for
the current project.

```bash
# Derive project name for claude-mem query
PROJECT=$(git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/')
echo "Project: $PROJECT"
```

Search claude-mem for proposals:
- Use the search MCP tool with query: "type:proposal"
- Filter to current project
- Sort by date descending

If proposals found, present each with:
- What it proposes (coaching rule, skill, agent change, hook, registry override)
- The instinct(s) it's based on (confidence score, evidence count)
- The specific change (file to edit, content to add/modify)

For each proposal, ask: Approve / Reject / Defer

- **Approve**: Apply the proposed change (edit the target file)
- **Reject**: Dismiss the proposal (note rejection in claude-mem)
- **Defer**: Keep for later review

If no proposals found:
"No pending proposals. The Continuous Learning plugin captures
patterns from your workflow and proposes improvements over time.
Install it from [repo URL] to enable this feature."
