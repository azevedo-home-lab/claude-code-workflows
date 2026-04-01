# Step 8: Handover (Claude-Mem Observation)

Dispatch a **Handover writer agent** — read `plugin/agents/handover-writer.md`, then dispatch as `general-purpose`:

Context: "Prepare a claude-mem handover observation. Project name: [derived from git remote get-url origin]. Plan: [PLAN_PATH]. Include commit hash, verification results, key decisions, gotchas, files modified, tech debt."

Save via the `save_observation` MCP tool. **Set `project` to the GitHub repo name.** Derive it: `git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/'`

#### Step 8 Review Gate

After saving the handover observation, dispatch a **review agent** — read `plugin/agents/handover-reviewer.md`, then dispatch as `general-purpose`:

Context: "Review the handover observation just saved."

If REDO: fix and re-save the observation, then re-dispatch. Max 3 iterations, then surface to user.
Present summary: "Step 8 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."

After saving the handover observation, build the final tracked observations list atomically:

1. Take `KEEP_IDS` from Step 7 (still-open items)
2. Add any new tech debt observation IDs saved in Step 7
3. Do NOT add the handover observation ID — it is a one-time reference
4. Write the complete list in a single call:

```bash
.claude/hooks/workflow-cmd.sh set_tracked_observations "<KEEP_IDS>,<NEW_TECH_DEBT_IDS>"
```

Mark milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "handover_saved" "true"
```
