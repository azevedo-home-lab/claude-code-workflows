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
| `/superpowers:brainstorming` | Requirements | Structured Q&A to refine requirements |
| `/superpowers:writing-plans` | Planning | Generate numbered implementation plan |
| `/superpowers:executing-plans` | Implementation | Batch execution with review checkpoints |
| `/superpowers:verification-before-completion` | Verification | Verify before claiming done |

## claude-mem Commands

| Command | What It Does |
|---------|-------------|
| `/claude-mem:mem-search` | Search previous session observations |
| `/claude-mem:make-plan` | Create implementation plan with context discovery |
| `/claude-mem:do` | Execute a plan using subagents |

