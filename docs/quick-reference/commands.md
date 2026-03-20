# Command Reference

## Workflow Manager

| Command | Phase | What It Does |
|---------|-------|-------------|
| `/define` | DEFINE | Guide problem + outcome definition |
| `/discuss` | DISCUSS | Start brainstorming and planning |
| `/implement` | IMPLEMENT | Unlock code edits (soft gate: warns if no plan) |
| `/review` | REVIEW | Run multi-agent review pipeline (soft gate: warns if no changes) |
| `/complete` | COMPLETE | Verified completion with outcome validation (soft gate: warns if no review) |

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
/define                          → Define problem + outcomes (optional)
/discuss                         → Enter discussion
/superpowers:brainstorm          → Clarify requirements
/superpowers:write-plan          → Generate plan
/implement                       → Unlock code edits
/superpowers:execute-plan        → Implement with checkpoints
/superpowers:verification-before-completion → Verify
/complete                        → Validate outcomes + commit
```
