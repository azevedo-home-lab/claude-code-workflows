Transition the workflow to IMPLEMENT phase. First check for soft gate warnings:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh"
WARN=$(check_soft_gate "implement")
if [ -n "$WARN" ]; then
    echo "WARNING: $WARN"
fi
```

If a warning was shown, ask the user: "Proceed anyway? (yes/no)". If they say no, stop. If yes or no warning, continue:

```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_phase "implement" && set_active_skill ""
echo "Phase set to IMPLEMENT — code edits are now allowed."
```

Then confirm to the user that the phase has changed and they can now proceed with implementation.

**You are now in IMPLEMENT phase.** Before proceeding:
1. Read `docs/reference/professional-standards.md` — apply the Universal Standards and IMPLEMENT Phase Standards throughout this phase.

Follow this workflow:
1. Use `superpowers:executing-plans` to implement the approved plan with review checkpoints
2. Use `superpowers:test-driven-development` — write tests before implementation code
3. When implementation is complete, the user will run `/review` to enter the review phase

**Important:** When you invoke a superpowers skill, update the active skill tracker:
```bash
WF_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" && source "$WF_DIR/.claude/hooks/workflow-state.sh" && set_active_skill "SKILL_NAME"
```
Replace SKILL_NAME with the skill being used (e.g., "executing-plans", "test-driven-development").
