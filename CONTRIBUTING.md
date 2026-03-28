# Contributing to Claude Code Workflows

Thank you for your interest in contributing.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/azevedo-home-lab/claude-code-workflows.git
   cd claude-code-workflows
   ```

2. Prerequisites:
   - Bash 4+
   - jq (for JSON manipulation in hooks)
   - Git
   - [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) (for testing the full workflow)

3. Install the plugin and verify hooks are active:
   ```bash
   claude  # start Claude Code in the project directory
   /define  # verify phase transitions work
   /off
   ```

## Making Changes

1. Fork the repository and create a feature branch
2. Make your changes
3. Verify the workflow pipeline works end-to-end
4. Add tests for new functionality
5. Add GPL v3 license headers to new source files
6. Submit a pull request

## Code Style

- **Shell scripts**: Use `set -euo pipefail`, quote variables, use `[ ]` for conditionals (POSIX style, consistent with existing codebase)
- **Markdown**: ATX-style headers (`##`), fenced code blocks with language tags
- **JSON**: 2-space indentation, trailing newline
- **Commits**: Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`)

## Testing

Testing is done via manual end-to-end verification:
- Phase transitions (`/define` -> `/discuss` -> `/implement` -> `/review` -> `/complete`)
- Write blocking in non-implement phases
- Guard-system self-protection (enforcement files blocked in all phases)
- Agent auto-transition in `auto` autonomy mode

## Pull Request Process

1. Verify manually: run the workflow through at least one full IMPLEMENT → REVIEW → COMPLETE cycle and confirm no regressions
2. Update documentation if behavior changes
3. One feature per PR — keep changes focused
4. Describe what and why in the PR description

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to uphold this code.

## License

By contributing, you agree that your contributions will be licensed under the GPL v3 license.
