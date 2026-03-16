Override the workflow phase. Use this to jump directly to any phase.

Valid phases: `off`, `discuss`, `implement`, `review`

The user must specify the target phase as an argument: `/override <phase>`

Parse the argument from "$ARGUMENTS". If no argument or invalid phase, show usage:

```
Usage: /override <phase>
Valid phases: off, discuss, implement, review

  off       — Disable workflow enforcement (normal Claude Code operation)
  discuss   — Brainstorming and planning (code edits blocked)
  implement — Code implementation (all edits allowed)
  review    — Review pipeline (all edits allowed)
```

If the argument is a valid phase, run:

```bash
source $CLAUDE_PROJECT_DIR/.claude/hooks/workflow-state.sh && set_phase "$ARGUMENTS" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Phase overridden to: $ARGUMENTS"
```

Then confirm the phase change to the user.
