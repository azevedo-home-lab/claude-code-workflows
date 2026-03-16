Transition the workflow to IMPLEMENT phase. Run this command:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Phase set to IMPLEMENT — code edits are now allowed."
```

Then confirm to the user that the phase has changed and they can now proceed with implementation.

**You are now in IMPLEMENT phase.** Follow this workflow:
1. Use `superpowers:executing-plans` to implement the approved plan with review checkpoints
2. Use `superpowers:test-driven-development` — write tests before implementation code
3. When implementation is complete, the user will run `/review` to enter the review phase

**Important:** When you invoke a superpowers skill, update the active skill tracker:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
echo '{"skill": "SKILL_NAME", "updated": "now"}' > "$WF_DIR/.claude/state/active-skill.json"
```
Replace SKILL_NAME with the skill being used (e.g., "executing-plans", "test-driven-development").
