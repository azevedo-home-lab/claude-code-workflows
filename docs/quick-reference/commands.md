# Command Reference

## Superpowers Skills

| Command | Phase | What It Does |
|---------|-------|-------------|
| `/superpowers:brainstorm` | Requirements | Structured Q&A to refine requirements |
| `/superpowers:write-plan` | Planning | Generate numbered implementation plan |
| `/superpowers:execute-plan` | Implementation | Batch execution with review checkpoints |
| `/superpowers:verification-before-completion` | Verification | Verify before claiming done |

## Auto-Activated Skills

| Skill | Triggers When |
|-------|--------------|
| TDD | Creating new functions/modules |
| Systematic Debugging | Error logs or stack traces present |
| Code Review | Refactoring existing code |
| Verification | Before claiming completion |
| Worktrees | Working on multiple features in parallel |

## claude-mem Commands

| Command | What It Does |
|---------|-------------|
| `/claude-mem:mem-search` | Search previous session observations |
| `/claude-mem:make-plan` | Create implementation plan with context discovery |
| `/claude-mem:do` | Execute a plan using subagents |

## Quick Sequence

```
Describe what you want
/superpowers:brainstorm          → Clarify requirements
/superpowers:write-plan          → Generate plan
Review and approve
/superpowers:execute-plan        → Implement with checkpoints
/superpowers:verification-before-completion → Verify
Commit
```
