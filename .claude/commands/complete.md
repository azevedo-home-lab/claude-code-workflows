Complete the current task after a successful review. Run the pre-completion checks first:

```bash
source ${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/workflow-state.sh
PHASE=$(get_phase)
if [ "$PHASE" != "review" ]; then
    echo "ERROR: Not in REVIEW phase (current: $PHASE). Run /review first."
    exit 1
fi
VC=$(get_review_field "verification_complete")
AD=$(get_review_field "agents_dispatched")
FP=$(get_review_field "findings_presented")
FA=$(get_review_field "findings_acknowledged")
echo "Pre-completion checks:"
echo "  verification_complete: $VC"
echo "  agents_dispatched: $AD"
echo "  findings_presented: $FP"
echo "  findings_acknowledged: $FA"
if [ "$VC" != "true" ] || [ "$AD" != "true" ] || [ "$FP" != "true" ] || [ "$FA" != "true" ]; then
    echo ""
    echo "BLOCKED: Review not complete. Run /review first and respond to findings."
    exit 1
fi
echo ""
echo "All checks passed. Proceeding with task completion."
```

If pre-completion checks fail, report what's missing and do NOT proceed. The user needs to run `/review` first.

If all checks pass, execute the completion pipeline below.

---

## Completion Pipeline

### Step 1: Claude-Mem Summary Observation

Save a summary observation to claude-mem using the `save_observation` MCP tool. Include:
- What was built or changed (summarize from `git diff --stat main...HEAD`)
- Key decisions made during the session
- Any gotchas or learnings discovered
- Files modified

This always runs — it ensures future sessions have context about this work.

### Step 2: Smart Documentation Detection

Analyze what changed (from `git diff --name-only main...HEAD`) and recommend documentation updates:
- Services modified → suggest updating relevant service doc in `docs/services/`
- CLAUDE.md-referenced features changed → suggest updating CLAUDE.md
- New scripts/commands added → suggest updating README or `docs/operations/script-reference.md`
- Infrastructure changed → suggest updating `docs/infrastructure/HARDWARE.md`
- Nothing needs updating → report "No documentation updates needed"

Present recommendations and ask: "Update these now? (yes / no / skip)"
- If **yes** → make the documentation updates
- If **no/skip** → proceed without docs update

### Step 3: Phase Transition

Run this command to complete the task:
```bash
source ${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/workflow-state.sh && set_phase "off" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Task complete. Phase set to OFF — workflow enforcement disabled."
```

Note: `set_phase("off")` automatically deletes `review-status.json` since we're leaving the review phase.

Confirm to the user that the task is complete and the workflow has reset to OFF phase (normal Claude Code operation). To start a new workflow cycle, use `/discuss`.
