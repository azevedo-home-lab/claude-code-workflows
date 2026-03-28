---
description: Analyze workflow observations and generate improvement proposals
---

Trigger the Continuous Learning analysis pipeline.

## Setup

```bash
PROJECT=$(git remote get-url origin 2>/dev/null | sed 's/.*[:/]\([^/]*\)\.git$/\1/' | sed 's/.*[:/]\([^/]*\)$/\1/')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
EVOLVE_SH="$PROJECT_DIR/cl-plugin/scripts/evolve.sh"
CONFIG="$PROJECT_DIR/cl-plugin/config/cl-config.json"
STATE_FILE="$PROJECT_DIR/.claude/state/cl-state.json"
ACTIVE_RULES="$PROJECT_DIR/.claude/state/cl-active-rules.json"
```

## Step 1: Acquire lock and load state

```bash
bash "$EVOLVE_SH" --lock
```

If lock acquisition fails (another pipeline is running), inform the user and stop.

Read state:
```bash
LAST_OBS_ID=$(bash "$EVOLVE_SH" --read last_obs_id)
echo "Last processed observation: #$LAST_OBS_ID"
```

Read config values:
```bash
MIN_OBS=$(jq -r '.trigger.min_new_observations // 20' "$CONFIG")
MAX_PROPOSALS=$(jq -r '.proposals.max_per_run // 5' "$CONFIG")
OBS_TYPES=$(jq -c '.observation_types' "$CONFIG")
MIN_NARRATIVE=$(jq -r '.observation_min_narrative_length // 50' "$CONFIG")
```

Read active rules (for cl-applied tagging):
```bash
if [ -f "$ACTIVE_RULES" ]; then
  RULES=$(cat "$ACTIVE_RULES")
else
  RULES="[]"
fi
```

## Step 2: Dispatch observation-fetcher

Read `cl-plugin/agents/observation-fetcher.md`, then dispatch as `general-purpose` with runtime context:

```
Project: $PROJECT
last_obs_id: $LAST_OBS_ID
observation_types: $OBS_TYPES
min_narrative_length: $MIN_NARRATIVE
active_rules: $RULES
```

Check the agent's response:
- If `status: "error"`: print the error, release lock (`bash "$EVOLVE_SH" --unlock`), stop
- If `count: 0`: print "No new observations since last run", release lock, stop
- If `count < $MIN_OBS`: print "Only N new observations (need $MIN_OBS). Not enough signal yet.", release lock, stop
- If `count >= $MIN_OBS`: continue to Step 3

## Step 3: Dispatch pattern-detector

Read `cl-plugin/agents/pattern-detector.md`, then dispatch as `general-purpose` with runtime context:

```
observations: <full JSON array from observation-fetcher>
analysis_prompt_path: $PROJECT_DIR/cl-plugin/config/analysis-prompt.md
frequency_threshold: 3
```

Check the agent's response:
- If `pattern_count: 0`: print "No recurring patterns detected.", update state, release lock, stop
- If patterns found: print summary ("Found N patterns, discarded M spurious, K self-reinforcing"), continue

## Step 4: Dispatch proposal-generator

Read `cl-plugin/agents/proposal-generator.md`, then dispatch as `general-purpose` with runtime context:

```
patterns: <JSON array from pattern-detector>
proposal_prompt_path: $PROJECT_DIR/cl-plugin/config/proposal-prompt.md
max_proposals: $MAX_PROPOSALS (hard ceiling: 20)
project: $PROJECT
```

Check the agent's response:
- If `proposals_generated: 0`: print "Patterns detected but no actionable proposals generated."
- If proposals generated: print summary for each proposal (pattern_name, confidence, target)

## Step 5: Update state

```bash
# Get the highest observation ID from fetched observations
NEW_LAST_OBS_ID=<max id from observation-fetcher results>

bash "$EVOLVE_SH" --update ".last_run = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .last_obs_id = $NEW_LAST_OBS_ID | .completion_count = 0 | .stats.total_runs += 1 | .stats.total_proposals_generated += $PROPOSALS_COUNT | .pending_proposals = $PROPOSALS_JSON"
```

## Step 6: Release lock and report

```bash
bash "$EVOLVE_SH" --unlock
```

Print summary:
```
## CL Analysis Complete

- Observations analyzed: N
- Patterns detected: M
- Proposals generated: P
- Run /proposals to review and approve/reject proposals.
```
