# Claude Code Workflows

A comprehensive guide to using cc-sessions and Superpowers together for structured, accountable development workflows.

## 🚀 Quick Start

New to this workflow? Start here:
- [Getting Started Guide](docs/guides/getting-started.md) - Your first steps
- [Workflow Cheatsheet](docs/quick-reference/workflow-cheatsheet.md) - Quick command reference

## 📖 Documentation

### Quick Reference
- [Command Reference](docs/quick-reference/commands.md) - All DAIC commands with descriptions
- [Workflow Cheatsheet](docs/quick-reference/workflow-cheatsheet.md) - Daily-use quick reference

### Guides
- [Getting Started](docs/guides/getting-started.md) - Installation and first workflow
- [Superpowers Guide](docs/guides/superpowers-guide.md) - Deep dive into Superpowers features
- [cc-sessions Guide](docs/guides/cc-sessions-guide.md) - Understanding the DAIC workflow
- [Examples](docs/guides/examples.md) - Real-world usage scenarios

### Reference
- [Architecture](docs/reference/architecture.md) - How the pieces fit together
- [Benefits Analysis](docs/reference/benefits-analysis.md) - Detailed benefits breakdown

### Research
- [Source Analysis](docs/research/source_analysis.md) - Original research notes
- [Workflow Proposal](docs/research/workflow_proposal.md) - Development history (archived)

## 🔧 Templates

- [CLAUDE.md Template](claude.md.template) - Security rules and project-specific guidelines

## 💡 Quick Command Reference

```bash
# DAIC Workflow
mek: <task>                    # Start new task
/superpowers:brainstorm        # Refine requirements
start^:                        # Load context & plan
/superpowers:write-plan        # Generate plan
yert                          # Approve & implement
/superpowers:execute-plan      # Execute with checkpoints
finito                        # Verify & commit
```

## 📚 What's Inside

This repository provides:
- **Structured workflow** combining cc-sessions DAIC loop with Superpowers skills
- **Context management** through session summaries and smart loading
- **Accountability** with task tracking and session archival
- **Quality gates** via TDD, verification, and proper commits
- **Templates** for reusing this workflow in your projects

## 🎯 Benefits

- 30-40% less back-and-forth during implementation
- Full session logs with decision rationale
- Smart context loading (only relevant code)
- Prevents scope creep with plan approval gates
- Future session warm starts from summaries

## 🔒 Security

See [CLAUDE.md Template](claude.md.template) for security rules including:
- Token protection protocols
- Secret hygiene guidelines
- Ownership attribution rules

## 🤝 Contributing

This workflow is designed for reuse. Copy and customize for your projects.
