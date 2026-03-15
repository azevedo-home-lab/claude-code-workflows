Transition the workflow to REVIEW phase. Run this command:

```bash
source $CLAUDE_PROJECT_DIR/.claude/hooks/workflow-state.sh && set_phase "review" && cat > "$STATE_DIR/active-skill.json" <<'SK'
{"skill": "", "updated": "phase-transition"}
SK
echo "Phase set to REVIEW — verify and review before completing."
```

Then confirm to the user that the phase has changed.

**You are now in REVIEW phase.** Follow this workflow:
1. Use `superpowers:verification-before-completion` — run tests, check output, verify all claims with evidence
2. Use `superpowers:requesting-code-review` — review for security, best practices, and requirements compliance
3. Fix any issues found (edits are still allowed in this phase)
4. When review passes, the user will run `/complete` to finish the task

**Important:** When you invoke a superpowers skill, update the active skill tracker:
```bash
echo '{"skill": "SKILL_NAME", "updated": "now"}' > $CLAUDE_PROJECT_DIR/.claude/state/active-skill.json
```
Replace SKILL_NAME with the skill being used (e.g., "verification-before-completion", "requesting-code-review").
