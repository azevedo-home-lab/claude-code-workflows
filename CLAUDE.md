Do not fix, modify, or delete anything unless explicitly asked. Default behavior is to investigate and report findings. Always ask before making changes.

## Version Bumping

When bumping the plugin version, you MUST update ALL THREE files:
- `.claude-plugin/plugin.json` — repo-level manifest (development, setup.sh dev mode)
- `.claude-plugin/marketplace.json` — marketplace catalog (`claude plugin install` uses this version to name the cache directory)
- `plugin/.claude-plugin/plugin.json` — cache-level manifest (gets copied into the cache; Claude Code needs this to discover commands and agents)

If these are out of sync, `claude plugin install` creates the cache under the wrong version, or Claude Code fails to discover plugin commands. This was the root cause of a major bug where slash commands (/discuss, /define, etc.) failed in all projects.
