# Decision Record: ECC — Continuous Learning Plugin

**Date:** 2026-03-28
**Scope:** New companion plugin for WFM; CL plugin has its own repo/design cycle
**Origin:** ECC Integration parked improvements (#3793) — this is the one remaining unimplemented workstream

## Problem

The WFM captures rich contextual observations in claude-mem across every session, but that data is currently inert — it informs future sessions through manual `/obs-read` lookups but is never analyzed for patterns. Recurring mistakes, consistently successful approaches, and emergent heuristics get no formal feedback loop.

ECC's design spec identified a Continuous Learning companion plugin that would:
1. Capture workflow observations as training signal
2. Detect patterns (via Haiku) and generate instinct YAMLs with confidence scores
3. Produce proposals stored in claude-mem
4. Surface proposals via WFM's `/proposals` command for user approve/reject
5. Apply approved proposals as config changes (registry overrides, skill configs, agent tweaks)

WFM currently has a `/proposals` stub command ready to receive proposals, and `claude-mem` as the shared bus — but the CL plugin that generates proposals doesn't exist.

## Context

**What's already done (v1.5.0):**
- All 27 agent files in `plugin/agents/` ✅
- Governance agent ✅
- Skill registry (`plugin/config/skill-registry.json`) ✅
- `/proposals` command stub ✅

**What's missing:**
- The Continuous Learning plugin itself (separate repo/project per the spec)
- Pattern detection pipeline
- Instinct YAML format + confidence scoring
- Proposal generation agent
- `/evolve` command trigger

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Monolithic orchestrator script
Single shell script handles full pipeline (fetch → filter → detect → propose → issue).
- **Pros:** Simple, single entry point, easy to follow
- **Cons:** Becomes a 300-line god file; hard to test stages independently; adding semantic v2 requires a rewrite

### Approach B: Staged pipeline, no state
4 agents + thin orchestrator, no persistent state file.
- **Pros:** Independent stages, each swappable; consistent with WFM's agent dispatch pattern
- **Cons:** Re-analyzes full observation history on every trigger; creates duplicate proposals; no cost control

### Approach C: Staged pipeline + persistent run state (chosen)
Same as B + `cl-state.json` tracking last_obs_id, completion_count, pending_proposals, stats.
- **Pros:** Incremental analysis (only new obs since last run); idempotent re-runs; extensible (semantic v2 = swap pattern-detector)
- **Cons:** State file adds corruption risk (mitigated by graceful reinitialization to defaults)

## Decision (DISCUSS phase — converge)

- **Chosen approach:** Approach C — Staged pipeline with persistent run state
- **Rationale:** Incremental analysis is not optional. Without `last_obs_id` tracking, every trigger re-analyzes full history and creates duplicate proposals. The staged pipeline is the right foundation for a system that will evolve — semantic clustering v2 means swapping the pattern-detector agent, not rewriting a monolith.
- **Trade-offs accepted:** WFM coupling via `complete.md` edit (setup.sh adds, uninstall.sh removes); Sonnet cost for proposal-generator (justified by hallucination risk at label generation step per TopicGPT research); manual `cl-plugin/` directory deletion on uninstall
- **Risks identified:** ICRH loop (mitigated — proposal type excluded from observation-fetcher); Haiku hallucination (mitigated — Sonnet for proposals); agentic drift (mitigated — configurable prompt files); gh auth expiry (mitigated — pre-check before issue creation)
- **Constraints applied:** claude-mem MCP as shared bus; co-location in repo for zero version skew; marketplace.json plugins array already supports multiple entries
- **Tech debt acknowledged:**
  - Uninstall does not remove `cl-plugin/` directory itself — v2 concern
  - No per-run rate limiting on Haiku/Sonnet calls — could be costly if many clusters; v2 concern
  - `proposals.md` update is a WFM file change driven by CL — same coupling class as `complete.md` edit
- **Link to spec:** `docs/superpowers/specs/2026-03-28-cl-plugin-design.md`
