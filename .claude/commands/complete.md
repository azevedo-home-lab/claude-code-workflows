Transition the workflow back to DISCUSS phase after a successful review. Run this command:

```bash
source $CLAUDE_PROJECT_DIR/.claude/hooks/workflow-state.sh && set_phase "discuss" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Task complete. Phase set to DISCUSS — ready for the next task."
```

Then confirm to the user that the task is complete and the workflow has reset to DISCUSS phase for the next task. Code edits are now blocked until a new plan is approved with `/approve`.
