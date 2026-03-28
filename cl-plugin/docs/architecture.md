# CL Plugin Architecture

## Overview

The Continuous Learning (CL) plugin detects behavioral patterns in
claude-mem observations and generates actionable improvement proposals.

## Pipeline

```
Observations → observation-fetcher → pattern-detector (Haiku)
→ proposal-generator (Sonnet) → proposals saved to claude-mem
→ /proposals → user approve → issue-creator → GitHub issue
```

## Trigger

- Automatic: every 5 `/complete` cycles (configurable in cl-config.json)
- Manual: `/evolve` command

## Key Files

| File | Purpose |
|------|---------|
| `commands/evolve.md` | Pipeline orchestrator (Claude interprets, dispatches agents) |
| `scripts/evolve.sh` | State management (read/write cl-state.json, counter, lock) |
| `scripts/setup.sh` | Install plugin (inject into complete.md, register in marketplace) |
| `scripts/uninstall.sh` | Remove plugin (strict inverse of setup.sh) |
| `config/cl-config.json` | Thresholds, models, labels, observation filters |
| `config/analysis-prompt.md` | Haiku clustering prompt (user-overridable) |
| `config/proposal-prompt.md` | Sonnet proposal prompt (user-overridable) |
| `agents/*.md` | 4 pipeline agent definitions |

## State Files (in .claude/state/, gitignored)

| File | Purpose |
|------|---------|
| `cl-state.json` | Last run, last obs ID, completion counter, run stats |
| `cl-state.lock` | Prevents concurrent pipeline runs |
| `cl-active-rules.json` | Tracks approved rule names for ICRH mitigation |

## Safety Constraints

- `type: proposal` observations are NEVER fed back into the pipeline (direct ICRH protection)
- `cl-active-rules.json` tracks approved rules; observations matching active rules are tagged
  `source: cl-applied` and down-weighted in clustering (indirect ICRH protection)
- Max 5 proposals per run (configurable); hard ceiling 20 (enforced in code)
- Haiku for clustering (cheap), Sonnet for proposals (accurate)
- Sentinel injection (`<!-- CL-INJECT-START/END -->`) in complete.md is reversible via uninstall.sh

## Known Deviations from Plan

| Deviation | Reason | Accepted |
|-----------|--------|----------|
| `evolve.md` Step 5 writes state directly via `jq` (not via `evolve.sh --update`) | Using `--argjson` safely requires access to `$STATE_FILE` directly; routing through `--update` would require passing a raw jq expression, which is the injection vector we fixed | Yes — safety improvement |
| `stats.total_proposals_approved/rejected` initialized but never incremented | Approve/reject flow runs through `proposals.md` + claude-mem; wiring back to `evolve.sh` deferred | Yes — tech debt, tracked |

## Configuration Override

Place custom `analysis-prompt.md` or `proposal-prompt.md` in `cl-plugin/config/` to
override defaults. The pipeline reads these files at runtime.
