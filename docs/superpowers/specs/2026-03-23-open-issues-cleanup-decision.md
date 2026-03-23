# Decision Record: Open Issues Cleanup & Tracked Observations

**Date:** 2026-03-23
**Phase:** DISCUSS
**Observation context:** #3416 (consolidated open issues list)

## Problem

13 accumulated open issues and tech debt items since plugin conversion. Ranging from bash compatibility bugs (#4) to missing adversarial validation in the COMPLETE pipeline (#1, #2) to a partially-implemented tracked observations feature with a race condition (#13).

The user wants all 13 items addressed in a single coordinated effort, properly designed and validated.

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Fix items individually as independent PRs
- Description: Each item gets its own branch, spec, and PR
- Pros: Minimal blast radius per change, easy to review
- Cons: 13 separate cycles is excessive overhead for items that are mostly S-effort. Many items touch the same files. Interactions between COMPLETE pipeline changes (#1, #2, #3, #13) would be hard to coordinate.

### Approach B: Phased implementation in dependency order (CHOSEN)
- Description: Group items into 4 phases by dependency and priority. Foundation fixes first (unblock everything), then tracked observations lifecycle, then COMPLETE pipeline improvements, then test coverage.
- Pros: Natural dependency ordering. Mechanical fixes done first reduce noise. Design-heavy items (#13, #1-3) done together since they interact. Tests last to validate everything.
- Cons: Larger single commit scope. If one phase has issues, it blocks subsequent phases.

### Approach C: Fix only HIGH priority items, defer the rest
- Description: Address #1, #2, #13 now, defer medium/low items
- Pros: Faster completion
- Cons: User explicitly asked for all items. Deferring again defeats the purpose of the cleanup.

## Decision (DISCUSS phase — converge)

- **Chosen approach:** B — Phased implementation in dependency order
- **Rationale:** All 13 items are in scope per user request. Grouping by dependency prevents blocked work. Mechanical fixes first clears the noise.
- **Trade-offs accepted:** Larger commit scope means more to review if something goes wrong. Acceptable because test coverage (Phase 4) validates everything.
- **Risks identified:** The jq consolidation (#7) changes statusline parsing — a bug here affects every prompt refresh. Mitigated by testing with real session data.
- **Constraints applied:** Tracked observations lifecycle must use atomic replace (option a) — no partial writes, crash-safe by design.
- **Tech debt acknowledged:** #11 (duplicate plugin.json) deliberately left unfixed — mitigated by existing version sync check.
- **Additional item discovered:** #14 — COMPLETE pipeline doesn't bump the plugin version before push. Added a versioning agent to Step 5 that determines bump type (major/minor/patch) from phase history and applies it autonomously.
- **Design spec:** `docs/superpowers/specs/2026-03-23-open-issues-cleanup-design.md`
