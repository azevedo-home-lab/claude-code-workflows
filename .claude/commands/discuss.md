Transition the workflow back to DISCUSS phase. Run this command:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "discuss" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Phase set to DISCUSS — code edits are now blocked until plan is approved."
```

Then confirm to the user that the phase has changed and code edits are blocked.

**You are now in DISCUSS phase.** Follow this workflow:
1. Use `superpowers:brainstorming` to explore requirements, constraints, and design options
2. Use `superpowers:writing-plans` to create a step-by-step implementation plan
3. Present the plan to the user for review
4. When the user is satisfied, they will run `/approve` to unlock code edits

**Important:** When you invoke a superpowers skill, update the active skill tracker:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && echo '{"skill": "SKILL_NAME", "updated": "now"}' > "$WF_DIR/.claude/state/active-skill.json"
```
Replace SKILL_NAME with the skill being used (e.g., "brainstorming", "writing-plans").
