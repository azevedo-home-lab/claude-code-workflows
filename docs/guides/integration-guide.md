# Superpowers Integration Guide

How Superpowers skills work together to enforce structured development.

## Superpowers — Development Skills

Provides structured techniques that auto-activate contextually.

### Manual Commands (Workflow-Driven)

| Command | When | Output |
|---------|------|--------|
| `/superpowers:brainstorming` | Before any feature work | Structured Q&A, refined requirements |
| `/superpowers:writing-plans` | After requirements are clear | Numbered implementation plan with testing steps |
| `/superpowers:executing-plans` | When plan is approved | Batch execution with review checkpoints |

### Auto-Activated Skills (Context-Driven)

| Skill | Triggers When |
|-------|--------------|
| TDD | Creating new functions/modules |
| Systematic Debugging | Error logs or stack traces present |
| Code Review | Refactoring or improving existing code |
| Verification | Before claiming work is complete |
| Worktrees | Working on multiple features in parallel |

## Recommended Workflow

```
Describe what you want to build
    │
    ▼
/superpowers:brainstorming          # Clarify requirements
    │
    ▼
/superpowers:writing-plans          # Generate plan
    │
    ▼
Review and approve the plan
    │
    ▼
/superpowers:executing-plans        # Implement with checkpoints
    │  (auto-skills: TDD, debugging, etc.)
    ▼
/superpowers:verification-before-completion
    │
    ▼
Commit and done
```

## Best Practices

1. **Always brainstorm** — even if requirements seem clear, it catches edge cases
2. **Review plans before approving** — easier to change now than during coding
3. **Trust checkpoints** — review at each pause, catching issues early is cheap
4. **Use worktrees** — isolate feature work from the main branch

## Installation

```bash
plugin marketplace add obra/superpowers-marketplace
plugin install superpowers@superpowers-marketplace
```

## Troubleshooting

- **Commands not showing**: `plugin list` to verify, reinstall if needed
- **Skills not activating**: Mention the pattern explicitly (e.g., "let's use TDD")
- **Plugin outdated**: Pull latest marketplace and restart Claude Code
