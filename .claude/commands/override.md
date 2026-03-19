Override the workflow phase. Use this to jump directly to any phase.

Valid phases: `off`, `define`, `discuss`, `implement`, `review`

The user must specify the target phase as an argument: `/override <phase>`

Parse the argument from "$ARGUMENTS". If no argument or invalid phase, show usage:

```
Usage: /override <phase>
Valid phases: off, define, discuss, implement, review

  off       — Disable workflow enforcement (normal Claude Code operation)
  define    — Problem and outcome definition (code edits blocked)
  discuss   — Brainstorming and planning (code edits blocked)
  implement — Code implementation (all edits allowed)
  review    — Review pipeline (all edits allowed)
```

If the argument is a valid phase, run:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "$ARGUMENTS" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
if [ "$ARGUMENTS" = "review" ]; then
    reset_review_status
    set_review_field "verification_complete" "true"
    set_review_field "agents_dispatched" "true"
    set_review_field "findings_presented" "true"
    set_review_field "findings_acknowledged" "true"
    echo "Phase overridden to: review (review gates pre-approved — /complete will proceed)"
else
    echo "Phase overridden to: $ARGUMENTS"
fi
```

Then confirm the phase change to the user. Note: `/override review` pre-approves all review gates since the user is explicitly choosing to override. If they want to re-run the review pipeline, they should use `/review` instead.
