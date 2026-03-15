Transition the workflow to IMPLEMENT phase. Run this command:

```bash
source $CLAUDE_PROJECT_DIR/.claude/hooks/workflow-state.sh && set_phase "implement" && echo "Phase set to IMPLEMENT — code edits are now allowed."
```

Then confirm to the user that the phase has changed and they can now proceed with implementation.
