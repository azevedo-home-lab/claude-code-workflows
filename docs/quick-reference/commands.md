# Command Reference

## DAIC Workflow

| Command | Phase | What It Does |
|---------|-------|-------------|
| `mek: <task>` | Discussion | Start task, initialize session log |
| `/superpowers:brainstorm` | Discussion | Structured Q&A to refine requirements |
| `start^:` | Alignment | Gather codebase context, load past summaries |
| `/superpowers:write-plan` | Alignment | Generate numbered implementation plan |
| `yert` | Implementation | Approve plan, lock scope |
| `/superpowers:execute-plan` | Implementation | Batch execution with review checkpoints |
| `finito` | Check | Verify, commit, archive session summary |

## Auto-Activated Skills

| Skill | Triggers When |
|-------|--------------|
| TDD | Creating new functions/modules |
| Systematic Debugging | Error logs or stack traces present |
| Code Review | Refactoring existing code |
| Error Fix | Errors detected during implementation |
| Verification | Before `finito` completion |
| Worktrees | Working on multiple features in parallel |

## Quick Sequence

```
mek: Add feature X          → Define what to build
/superpowers:brainstorm      → Clarify requirements
start^:                      → Gather codebase context
/superpowers:write-plan      → Generate plan
yert                         → Approve and lock scope
/superpowers:execute-plan    → Implement with checkpoints
finito                       → Verify, commit, archive
```
