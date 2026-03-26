# Decision Record: Tech Debt Cleanup + GitHub Issue Sync

**Date:** 2026-03-26
**Status:** In Progress
**Observations:** #4336 (v1.8.0 handover), #4337 (GitHub issue sync)

## Problem

Two issues:

1. **Six confirmed tech debt items** from v1.8.0 handover (#4336) — ranging from High (git commit chain blocked, pushed field missing) to Low (_plugin_version duplication).

2. **No bridge between claude-mem observations and GitHub issues** (#4337) — tech debt and open issues identified during `/complete` exist only as claude-mem observations with no corresponding GitHub issues. The statusline shows `Open:[#3793,#4259]` but these are observation IDs with no clickable links.

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: GitHub issues + no statusline links
- Create issues during `/complete`, show URLs in output only
- Pros: Simple, works everywhere
- Cons: No statusline integration, user must remember issue URLs

### Approach B: GitHub issues + statusline links (OSC 8)
- Create issues, render clickable links in statusline
- Pros: Best UX when it works
- Cons: OSC 8 stripped by Claude Code's Ink renderer in standalone terminals (iTerm2, Terminal.app). Only works in VS Code. Upstream issue: claude-code#26356

### Approach C: GitHub issues + statusline OSC 8 with graceful degradation
- Create issues during `/complete`, store observation→issue mapping in workflow.json
- Statusline renders OSC 8 links — clickable in VS Code, plain text elsewhere
- Issue creation is confirmable (prompt in ask mode, batch in auto mode)
- Pros: Best of both worlds, future-proof (when Ink fix lands, works everywhere)
- Cons: More complex state management, mixed terminal experience

## Decision (DISCUSS phase — converge)

- **Chosen approach:** Approach C — GitHub issues with OSC 8 graceful degradation
- **Rationale:** OSC 8 degradation is invisible (plain text fallback), the mapping is useful metadata, and upstream fix will enable it everywhere
- **Trade-offs accepted:** Links only work in VS Code until upstream Ink fix
- **Risks identified:** `gh` CLI may not be authenticated; issue creation could spam tracker
- **Constraints applied:** Issue creation is confirmable by default (respects autonomy level)
- **Tech debt acknowledged:** None — this is a tech debt reduction session
- Link to implementation plan: `docs/superpowers/plans/2026-03-26-tech-debt-github-sync-plan.md`
