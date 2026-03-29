# Design: Continuous Learning (CL) Plugin

**Date:** 2026-03-28
**Scope:** `cl-plugin/` — new co-located plugin in ClaudeWorkflows repo
**Origin:** ECC Integration parked improvements (#3793) — Continuous Learning workstream
**Status:** DISCUSS phase — design approved, converge findings incorporated

---

## Problem

The Workflow Manager captures rich contextual observations in claude-mem across every session — discoveries, decisions, bugs, features — but this data is inert. It informs future sessions through manual `/obs-read` lookups but is never analyzed for patterns. Recurring mistakes, consistently successful approaches, and emergent heuristics get no formal feedback loop.

The `/proposals` command stub (added in v1.5.0) is ready to surface proposals, and claude-mem is the shared bus — but the CL plugin that generates proposals doesn't exist.

**Gap:** No mechanism to extract behavioral heuristics from accumulated session observations and surface them as actionable proposals.

---

## Chosen Approach: Staged Pipeline with Persistent Run State (Approach C)

Four independently-testable agents orchestrated by a command file (`evolve.md`) with shell-script state management (`evolve.sh`). Persistent state enables incremental analysis (only new observations since last run) and idempotent re-runs.

**Orchestration split:** `evolve.md` is the command file Claude interprets — it dispatches agents via the Agent tool (same pattern as `complete.md` dispatching review agents). `evolve.sh` handles only state management: read/write `cl-state.json`, counter logic, lock file acquisition/release. `evolve.md` calls `evolve.sh` for state operations, then dispatches agents based on the result. The `/complete` Step 9 trigger calls `evolve.sh --trigger=complete` which increments the counter; if threshold is met, it outputs a signal that `complete.md` picks up to invoke the full `/evolve` command.

### Why this over alternatives

- **Approach A (monolithic script):** Simpler today, unmaintainable when semantic clustering is added. A 300-line god script is not the right foundation.
- **Approach B (staged pipeline, no state):** Correct architecture but re-analyzes full observation history on every run — creates duplicate proposals and wastes API calls.
- **Approach C (staged pipeline + state):** Incremental analysis, idempotent, extensible. The right foundation.

### Co-location decision

CL lives in `cl-plugin/` in this repo (not a separate repo) because its prerequisites — claude-mem MCP and WFM — are hard dependencies. A separate repo creates version skew risk and a three-plugin install burden. The `.claude-plugin/marketplace.json` `plugins` array already supports multiple entries.

### Trade-offs accepted

- `complete.md` injection uses sentinel comments (`<!-- CL-INJECT-START -->` / `<!-- CL-INJECT-END -->`) — idempotent, reversible, stripped by `uninstall.sh`
- Sonnet used for proposal generation — higher cost than Haiku, justified by hallucination risk at this step (TopicGPT research, arXiv finding)
- `cl-state.json` in `.claude/state/` (already gitignored) — co-located with WFM state, avoids accidental git commit of behavioral observations
- No uninstall removes `cl-plugin/` itself — user must delete manually to preserve custom config

### Risks accepted

- **Agentic drift (indirect feedback loop):** Approved proposals shape future observations → re-detected as patterns. Mitigated by:
  - When a proposal is approved, `issue-creator` writes the proposal's `pattern_name` to `.claude/state/cl-active-rules.json` (a simple JSON array of active rule names).
  - During future sessions, if `cl-active-rules.json` exists and is non-empty, the `/evolve` pipeline passes it to the `observation-fetcher`, which tags observations whose narrative matches an active rule keyword with `source: cl-applied` (vs default `source: organic`).
  - `pattern-detector` down-weights `cl-applied` observations: a cluster where > 50% of supporting observations are `cl-applied` is flagged as `self-reinforcing` and excluded from proposal generation.
  - This is a heuristic, not a guarantee — it catches obvious amplification loops but cannot detect subtle indirect influence. Documented as a known limitation.
- `gh` auth expiry between generation and approval: issue-creator checks auth before running, leaves proposal in `pending` state with clear error message.
- Sonnet cost at scale: `max_per_run` (default 5) in `cl-config.json` caps per-run Sonnet calls. Hard ceiling of 20 enforced in `evolve.md` code only (not in config — prevents user from accidentally setting an unbounded value).

---

## Architecture

```
claude-mem observations (type: discovery|decision|bugfix|feature)
        │
        ▼
┌─────────────────────────────────────────────────────┐
│  /evolve command (cl-plugin/commands/evolve.md)     │
│  Claude interprets this, dispatches agents via Agent│
│                                                     │
│  1. Call evolve.sh to load cl-state.json + acquire  │
│     lock + check counter threshold                  │
│  2. If not enough signal: log, exit clean           │
│  3. Dispatch observation-fetcher agent              │
│     → query claude-mem, filter by type + last_obs_id│
│  4. Dispatch pattern-detector agent (Haiku)         │
│     → Stage 1: concept frequency pre-filter         │
│     → Stage 2: Haiku semantic clustering on cands   │
│     → discard spurious clusters (coherence check)   │
│  5. Dispatch proposal-generator agent (Sonnet)      │
│     → generate proposals from detected patterns     │
│     → save to claude-mem as type: proposal          │
│  6. Call evolve.sh to update cl-state.json          │
│     (last_run, last_obs_id, pending_proposals)      │
│  7. Release lock                                    │
└─────────────────────────────────────────────────────┘
        │
        ▼ (at /proposals time, user-initiated)
┌─────────────────────────────────────────────────────┐
│  /proposals command (WFM)                           │
│  Display: pattern, confidence, target, proposed change│
│  User: Approve / Reject / Defer                     │
│  Approve → issue-creator agent                      │
│           → gh issue create --label proposal,learning│
│           → update claude-mem proposal status       │
└─────────────────────────────────────────────────────┘
```

**Trigger points:**
- `/complete` Step 9 (after handover summary, before `/off` instruction): sentinel-wrapped guard call:
  ```bash
  <!-- CL-INJECT-START -->
  if [ -f "$(git rev-parse --show-toplevel)/cl-plugin/scripts/evolve.sh" ]; then
    bash "$(git rev-parse --show-toplevel)/cl-plugin/scripts/evolve.sh" --trigger=complete
  fi
  <!-- CL-INJECT-END -->
  ```
- `cl_completion_count` tracked in `.claude/state/cl-state.json` (not `workflow.json` — zero WFM state coupling)
- Every N completions (default: 5), pipeline runs; count resets on successful run
- `/evolve` command: manual trigger, bypasses counter, always runs full pipeline
- Lock file (`.claude/state/cl-state.lock`) prevents concurrent runs

---

## File Structure

```
cl-plugin/
├── .claude-plugin/
│   └── plugin.json              # name, version, description
├── agents/
│   ├── observation-fetcher.md   # queries claude-mem, filters by type + last_obs_id
│   ├── pattern-detector.md      # freq pre-filter + Haiku semantic clustering
│   ├── proposal-generator.md    # Sonnet proposal generation from patterns
│   └── issue-creator.md         # gh issue create on approval
├── commands/
│   └── evolve.md                # /evolve on-demand trigger
├── config/
│   ├── cl-config.json           # thresholds, models, labels
│   ├── analysis-prompt.md       # Haiku clustering prompt (user-overridable)
│   └── proposal-prompt.md       # Sonnet proposal prompt (user-overridable)
├── docs/
│   └── architecture.md          # architecture reference (this design, condensed)
├── scripts/
│   ├── evolve.sh                # state management only: read/write cl-state.json, counter, lock
│   ├── setup.sh                 # install: edit complete.md, init state, register in marketplace.json
│   └── uninstall.sh             # teardown: inverse of setup.sh
# NOTE: cl-state.json lives in .claude/state/ (already gitignored by WFM setup.sh)
# cl-plugin/state/ directory is not used
```

---

## Configuration

**`cl-plugin/config/cl-config.json`:**
```json
{
  "version": "0.1.0",
  "trigger": {
    "completions_per_run": 5,
    "min_new_observations": 20
  },
  "models": {
    "pattern_detector": "claude-haiku-4-5-20251001",
    "proposal_generator": "claude-sonnet-4-6"
  },
  "proposals": {
    "max_per_run": 5
  },
  "analysis_prompt": "cl-plugin/config/analysis-prompt.md",
  "proposal_prompt": "cl-plugin/config/proposal-prompt.md",
  "observation_types": ["discovery", "decision", "bugfix", "feature"],
  "observation_min_narrative_length": 50,
  "github": {
    "labels": ["proposal", "learning"],
    "duplicate_check": true
  }
}
```

**User overrides:** Place custom `analysis-prompt.md` or `proposal-prompt.md` in `cl-plugin/config/`. CL checks for user override first, falls back to defaults. Follows same pattern as WFM's `skill-overrides.json`.

**Default prompt content:** The default `analysis-prompt.md` content is specified in the Architecture section under "Agent 2: pattern-detector". The default `proposal-prompt.md` must instruct Sonnet to generate proposals conforming to the proposal JSON schema in "Agent 3: proposal-generator". Both default prompt files are created by setup.sh.

---

## The Pipeline in Detail

### Agent 1: `observation-fetcher`

Queries claude-mem via MCP search tool:
- `project`: derived from `git remote get-url origin`
- `type`: values from `cl-config.json` `observation_types` (excludes `proposal` — hardcoded safety constraint, not user-configurable)
- Filters to observations newer than `last_obs_id` in `cl-state.json`
- Filters out observations with narrative length < `observation_min_narrative_length` (default 50 chars) — prevents terse/incomplete entries from polluting pattern detection
- **Field availability:** claude-mem observations have `concepts` and `facts` fields, but these are frequently empty arrays (`"[]"`). Observations with non-empty concept/fact fields participate in Stage 1 frequency counting. Observations with empty concept/fact fields skip Stage 1 but are included in the full observation set passed to Stage 2 — Haiku performs semantic grouping from narrative text directly for these observations. This means Stage 1 acts as a fast pre-filter for observations that have structured metadata, while Stage 2 is the catch-all that handles unstructured narratives.
- On MCP connection error: abort with clear message, do NOT advance `last_obs_id`, do NOT reset `completion_count`
- Distinguishes MCP error (abort) from empty result set (log "no new observations", exit clean)
- Returns structured JSON list of `{id, type, title, narrative, created_at, source}`
- Exits with `insufficient_signal` if count < `min_new_observations`

### Agent 2: `pattern-detector`

Two-stage:

**Stage 1 — Frequency pre-filter (deterministic, zero LLM cost):**
- Extracts `concepts` and `facts` fields from each observation
- Groups by concept tag — any concept appearing in ≥ 3 observations becomes a candidate cluster (internal constant: `FREQUENCY_THRESHOLD=3`, not exposed in `cl-config.json` — keeps config surface small)


**Stage 2 — Haiku semantic pass (on candidates only):**
- Sends candidate clusters to Haiku with `analysis-prompt.md`
- Haiku returns patterns with: `pattern_name`, `insight`, `confidence`, `supporting_obs_ids`, `weak_obs_ids`, `cluster_coherence` (tight|loose|spurious)
- Orchestrator discards `cluster_coherence: spurious` before passing to proposal-generator

**Output:** JSON array of confirmed patterns with coherence scores.

### Agent 3: `proposal-generator`

- Receives confirmed patterns from pattern-detector
- Calls Sonnet (not Haiku) with `proposal-prompt.md` — justified by hallucination risk at label/proposal generation step (TopicGPT research finding)
- For each pattern, generates:
```json
{
  "id": "prop-2026-03-28-001",
  "pattern_name": "...",
  "insight": "...",
  "confidence": 0.87,
  "proposal_type": "skill|agent|config|command|behavior",
  "target_file": "...",
  "proposed_change": "...",
  "rationale": "...",
  "supporting_obs_ids": [1234, 1235],
  "obs_sources": {"1234": "organic", "1235": "cl-applied"},
  "status": "pending|approved|rejected|deferred",
  "deferred_count": 0,
  "issue_url": null
}
```
- Writes proposals to `cl-state.json` as `pending_proposals`
- Saves each proposal to claude-mem as `type: proposal` (consumed by `/proposals` command)

### Agent 4: `issue-creator`

Called only when user approves a proposal in `/proposals`:
1. Checks `gh auth status` — surfaces clear error if not authenticated
2. Calls `gh issue list --search "[proposal/learning] <pattern_name>"` — skips if duplicate found
3. Creates issue: title `[proposal/learning] <pattern_name>`, body with rationale + supporting obs IDs + proposed change + confidence, labels: `proposal`, `learning`
4. Updates claude-mem proposal with `status: approved, issue_url: <url>`

---

## State Schema

**`.claude/state/cl-state.json`** (co-located with WFM state, already gitignored):
```json
{
  "version": "0.1.0",
  "last_run": "2026-03-28T16:00:00Z",
  "last_obs_id": 5042,
  "completion_count": 3,
  "pending_proposals": [],
  "stats": {
    "total_runs": 0,
    "total_proposals_generated": 0,
    "total_proposals_approved": 0,
    "total_proposals_rejected": 0
  }
}
```

State file lives in `.claude/state/` (already gitignored by WFM's `setup.sh`). If missing or corrupted (`jq empty` fails), `evolve.sh` reinitializes with defaults and logs the reset. Written via temp file + `mv` for atomic update. Lock file: `.claude/state/cl-state.lock` — created at pipeline start, removed on exit; if lock exists and is < 10 minutes old, pipeline exits immediately.

---

## Safety Constraints

| Risk | Mitigation | Configurable? |
|------|-----------|---------------|
| ICRH direct loop (proposals re-analyzed as signal) | `proposal` type excluded from observation-fetcher — hardcoded | No |
| ICRH indirect loop (cl-applied obs re-detected as patterns) | `.claude/state/cl-active-rules.json` tracks approved rule names; observation-fetcher tags matching obs as `cl-applied`; pattern-detector excludes clusters where > 50% of obs are `cl-applied` | No |
| Spurious clusters from low N | `min_new_observations: 20` threshold | Yes (cl-config.json) |
| Terse observations polluting pattern detection | `observation_min_narrative_length: 50` filter in observation-fetcher | Yes (cl-config.json) |
| Haiku hallucination in proposals | Proposal generation uses Sonnet | Yes (models config) |
| Sonnet cost at scale | `max_per_run: 5` (configurable); hard ceiling of 20 enforced in code (not in config) | Soft yes, hard no |
| `complete.md` edit not reversible | Sentinel comment block (`<!-- CL-INJECT-START -->/END`); `uninstall.sh` strips by sentinel | No |
| Concurrent pipeline runs | Lock file in `.claude/state/cl-state.lock`; exits if lock < 10 min old | No |
| State file corruption | `jq empty` validation on startup; reinitialize to defaults on failure; atomic write via temp+mv | No |
| `cl-state.json` accidentally committed | Co-located in `.claude/state/` — already gitignored by WFM | No |
| MCP unavailability | Abort with error; do NOT advance `last_obs_id` or reset `completion_count` | No |
| Duplicate GitHub issues | `duplicate_check: true` — title search before create | Yes (cl-config.json) |
| `gh` auth expiry | Pre-check with `gh auth status`; leave proposal in `pending` with clear error | No |
| CL modifying own eval logic | issue-creator writes to GitHub only, not cl-plugin/ | No |

---

## WFM Integration

### `complete.md` (Step 9 addition — added by setup.sh, removed by uninstall.sh)

Placement: **after the handover summary block, before the "Run /off" instruction** (after all 8 milestones are true, state mutation is complete, nothing below this will mutate `workflow.json`).

**Anchor string for injection:** `setup.sh` locates the insertion point by matching `Run.*\/off.*to close the workflow` in `complete.md` (the actual line is ``Run `/off` to close the workflow.`` with backtick-wrapped `/off` and a trailing period). The sentinel block is inserted on the line immediately before that anchor.

```bash
<!-- CL-INJECT-START -->
if [ -f "$(git rev-parse --show-toplevel 2>/dev/null)/cl-plugin/scripts/evolve.sh" ]; then
  bash "$(git rev-parse --show-toplevel)/cl-plugin/scripts/evolve.sh" --trigger=complete
fi
<!-- CL-INJECT-END -->
```

`setup.sh` guards insertion: checks for `<!-- CL-INJECT-START -->` before inserting (idempotent).
`uninstall.sh` strips the sentinel block: removes all lines from `<!-- CL-INJECT-START -->` to `<!-- CL-INJECT-END -->` inclusive.

### `proposals.md` (updated display + approve flow)

Updated to:
1. Display full proposal fields: pattern, confidence, type, target, proposed change, rationale, supporting obs IDs
2. On approve: call `issue-creator` agent
3. On reject: update claude-mem proposal with `status: rejected`; update `cl-state.json` pending_proposals entry
4. On defer: update claude-mem proposal with `status: deferred`, increment `deferred_count`; shows "(deferred N times)" on next `/proposals` display so user sees accumulation

### `.claude-plugin/marketplace.json` (second entry added by setup.sh)

```json
{
  "plugins": [
    { "name": "workflow-manager", "version": "1.13.0", "source": "./plugin", ... },
    { "name": "continuous-learning", "version": "0.1.0", "source": "./cl-plugin", ... }
  ]
}
```

---

## Setup and Uninstall

**`setup.sh` conventions** (follows `plugin/scripts/setup.sh` patterns exactly):
- `set -euo pipefail` at top
- `PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` for self-location
- `PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"` — respects env override
- Guard `jq` presence before any JSON operations
- Symlink `cl-plugin/commands/evolve.md` → `.claude/commands/evolve.md` (idempotent `ln -sf`)

**`setup.sh` steps (idempotent):**
1. Check `ANTHROPIC_API_KEY` — error if not set
2. Check `gh auth status` — warn if not authenticated (non-blocking)
3. Initialize `.claude/state/cl-state.json` with `jq -n` if not exists
4. Add `.claude/state/` to `.gitignore` if not already present (idempotent `grep` guard — belt-and-suspenders in case WFM `setup.sh` has not been run)
5. Inject sentinel block into `complete.md` Step 9 (check for `<!-- CL-INJECT-START -->` before inserting)
6. Add CL entry to `.claude-plugin/marketplace.json` using `jq` (check for existing entry before adding)
7. Symlink `cl-plugin/commands/evolve.md` → `.claude/commands/evolve.md`
8. Print: "CL plugin ready. Will analyze after every 5 /complete cycles. Run /evolve to trigger manually."

**`uninstall.sh` (strict inverse):**
1. Strip sentinel block from `complete.md` (remove `<!-- CL-INJECT-START -->` through `<!-- CL-INJECT-END -->`)
2. Remove `.claude/state/cl-state.json`, `.claude/state/cl-state.lock`, and `.claude/state/cl-active-rules.json` if present
3. Remove CL entry from `.claude-plugin/marketplace.json` using `jq`
4. Remove `.claude/commands/evolve.md` symlink
5. Print: "CL plugin uninstalled. Remove cl-plugin/ directory manually to delete config and prompts."

---

## `/proposals` Data Contract

CL writes to claude-mem with this structure for each proposal:
```json
{
  "type": "proposal",
  "title": "[proposal/learning] <pattern_name>",
  "narrative": "<full proposal JSON as formatted text>",
  "project": "<repo name>"
}
```

The `/proposals` command queries `type=proposal` + current project — no changes to the query logic, only to display format and the approve→issue action.

---

## Approaches Considered (diverge)

### Approach A: Monolithic orchestrator script
Single shell script handles full pipeline.
- **Pro:** Simple, single entry point
- **Con:** Becomes unmaintainable at 300+ lines; hard to test stages independently; semantic v2 requires rewrite

### Approach B: Staged pipeline, no state
4 agents + orchestrator, no persistent state file.
- **Pro:** Independent stages, swappable
- **Con:** Re-analyzes full history on every run; creates duplicate proposals; no cost control

### Approach C (chosen): Staged pipeline + persistent run state
Same as B + `cl-state.json` for incremental analysis.
- **Pro:** Incremental, idempotent, cost-controlled, extensible
- **Con:** State file adds corruption risk (mitigated by graceful reinitialization)

---

## Decision

- **Chosen approach:** Approach C
- **Rationale:** Incremental analysis is not optional — without it, every trigger re-analyzes full history and creates duplicate proposals. Staged pipeline is the right architecture for a system that will evolve (semantic v2 = swap pattern-detector agent).
- **Trade-offs accepted:** WFM coupling via `complete.md` edit; Sonnet cost for proposals; manual `cl-plugin/` deletion on uninstall
- **Risks identified:** ICRH loop (mitigated), Haiku hallucination (mitigated via Sonnet), agentic drift (mitigated via configurable prompts), `gh` auth expiry (mitigated via pre-check)
- **Constraints applied:** claude-mem MCP as shared bus; co-location for zero version skew; `marketplace.json` array already supports multi-plugin
- **Tech debt acknowledged:**
  - Uninstall does not remove `cl-plugin/` directory — v2 concern
  - No rate limiting on Haiku/Sonnet calls within a single run — could be costly if many candidate clusters emerge; v2 concern
  - `/proposals` `proposals.md` update is a WFM file change driven by CL — same coupling pattern as `complete.md` edit

---

## Research Sources

- [Feedback Loops With Language Models Drive In-Context Reward Hacking — arXiv 2402.06627](https://arxiv.org/abs/2402.06627)
- [Reward Hacking in Reinforcement Learning — Lilian Weng](https://lilianweng.github.io/posts/2024-11-28-reward-hacking/)
- [Skill Learning: Bringing Continual Learning to CLI Agents — Letta](https://www.letta.com/blog/skill-learning)
- [TopicGPT — ArikReuter GitHub](https://github.com/ArikReuter/TopicGPT)
- [Text Clustering with LLM Embeddings — arXiv 2403.15112](https://arxiv.org/html/2403.15112v1)
- [MinHash LSH in Milvus — Milvus Blog](https://milvus.io/blog/minhash-lsh-in-milvus-the-secret-weapon-for-fighting-duplicates-in-llm-training-data.md)
- [Making it easier to build human-in-the-loop agents with interrupt — LangChain Blog](https://blog.langchain.com/making-it-easier-to-build-human-in-the-loop-agents-with-interrupt/)
- [Agent Orchestration Feedback Loops — LoopJar](https://loopjar.ai/blog/agent-orchestration-feedback-loop)
- [Startup's AI Tool Spams GitHub Repositories — OSnews](https://www.osnews.com/story/141134/startups-ai-tool-spams-github-repositories-with-bogus-commits-without-consent/)
- [Rate Limits — Anthropic API Docs](https://platform.claude.com/docs/en/api/rate-limits)
- [Demonstrating Specification Gaming in Reasoning Models — arXiv 2502.13295](https://arxiv.org/pdf/2502.13295)
