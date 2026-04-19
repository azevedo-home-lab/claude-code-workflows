Do not fix, modify, or delete anything unless explicitly asked. Default behavior is to investigate and report findings. Always ask before making changes.

## Version Bumping

When bumping the plugin version, you MUST update BOTH files:
- `.claude-plugin/plugin.json` — the plugin manifest (used by plugin.json-based resolution)
- `.claude-plugin/marketplace.json` — the marketplace catalog (used by `claude plugin install` to name the cache directory)

If these are out of sync, `claude plugin install` will install under the wrong version directory and users will get stale commands. This was the root cause of a major bug where slash commands (/discuss, /define, etc.) failed in all projects.
