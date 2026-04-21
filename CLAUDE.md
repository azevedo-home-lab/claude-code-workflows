Do not fix, modify, or delete anything unless explicitly asked. Default behavior is to investigate and report findings. Always ask before making changes.

## Guard-System Integrity

Never use Bash to bypass Edit/Write tool blocks. If the guard-system blocks an edit, stop and tell the user. Do not use interpreters (python, node, ruby, perl), heredocs, or any indirect method to write files that the guard-system would block via the Edit/Write tools. The guard-system exists to keep the user in control — circumventing it defeats its purpose.

## Version Bumping

When bumping the plugin version, you MUST update ALL THREE files:
- `.claude-plugin/plugin.json` — repo-level manifest (development, setup.sh dev mode)
- `.claude-plugin/marketplace.json` — marketplace catalog (`claude plugin install` uses this version to name the cache directory)
- `plugin/.claude-plugin/plugin.json` — cache-level manifest (gets copied into the cache; Claude Code needs this to discover commands and agents)

If these are out of sync, `claude plugin install` creates the cache under the wrong version, or Claude Code fails to discover plugin commands. This was the root cause of a major bug where slash commands (/discuss, /define, etc.) failed in all projects.
