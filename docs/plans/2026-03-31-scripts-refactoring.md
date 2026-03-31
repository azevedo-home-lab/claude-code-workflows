# Scripts Directory Refactoring

## Problem

The `plugin/scripts/` directory (2,507 lines across 8 files) has accumulated complexity through incremental feature additions. Three files concentrate most of the problems:

- **`workflow-state.sh`** (776 lines) — god module sourced by every hook, loads coaching/observation/issue/milestone helpers even when only phase reads are needed
- **`post-tool-navigator.sh`** (786 lines) — monolithic 3-layer coaching system with inline parsers, throttle logic, and 10+ anti-pattern checks in one procedural flow
- **`bash-write-guard.sh`** (320 lines) — security-critical regex engine with 14 stitched-together patterns and complex git commit chain parsing

### Specific Issues

1. **God module**: `workflow-state.sh` is sourced by all hooks but most only need `get_phase()` and `emit_deny()`. Every PreToolUse invocation loads 777 lines of unused functions.
2. **Monolith coaching**: `post-tool-navigator.sh` mixes observation tracking, throttle state, 3 coaching layers, and 10 check implementations in one file.
3. **Regex fragility**: `bash-write-guard.sh` has 14 regex fragments with string concatenation. The `PIPE_SHELL` pattern uses `+=`. The git commit chain parser has 3 sed/awk strategies.
4. **Duplicated state template**: The jq state schema is copy-pasted between `user-set-phase.sh` and `agent_set_phase()` with a "intentional duplication" comment, but they already share `_safe_write()` and `_read_preserved_state()`.
5. **Excessive jq**: Each `post-tool-navigator.sh` call spawns 15-25 jq processes. Every `_update_state` is 3+ process spawns (read, jq, validate, mv).
6. **Python for path canonicalization**: `workflow-gate.sh` shells out to `python3` for `os.path.realpath()`, adding ~100ms per Write/Edit hook.
7. **Unquoted jq interpolation**: `_should_fire()` interpolates check names directly into jq filter strings.
8. **Debug inconsistency**: `workflow-gate.sh` still checks `$DEBUG_MODE = "true"` (legacy boolean) while all other scripts use `_log`/`_show` from `debug-log.sh`.
9. **Invisible coupling**: `_read_preserved_state()` writes to caller-scope variables that must be pre-declared with `local`.

## Approaches Considered (DISCUSS phase — diverge)

### Approach A: Modular Split (Extract & Isolate)

Split `workflow-state.sh` into focused modules. Extract coaching checks into individual files. Keep bash, stay within current architecture.

- **Pros**: Incremental, low risk, each module testable in isolation, no new dependencies
- **Cons**: Still bash for complex logic, doesn't solve jq spawn overhead fundamentally
- **Source**: Direct analysis of current codebase

### Approach B: Rewrite Core in a Compiled Language

Move state management and pattern matching to a small Go/Rust binary. Bash scripts become thin wrappers.

- **Pros**: Eliminates jq overhead, proper error handling, type safety, single binary distribution
- **Cons**: New language dependency, much larger change, harder for users to inspect/modify, breaks plugin portability
- **Source**: Common pattern in mature CLI tools

### Approach C: Hybrid — Modular Split + Batch jq

Split modules (Approach A) plus consolidate jq calls into batch read/write operations. Keep bash but optimize the hot path.

- **Pros**: Best of Approach A with performance fix, no new dependencies, incremental
- **Cons**: Batch jq adds complexity to the state API, still bash for regex
- **Source**: Synthesis of analysis findings

## Decision (DISCUSS phase — converge)

- **Chosen approach:** Approach A — Modular Split (Extract & Isolate)
- **Rationale:** The primary problems are structural (god module, monolith), not performance. Splitting into focused modules makes each file understandable, testable, and maintainable. jq overhead is annoying but not user-visible (hooks run in background).
- **Trade-offs accepted:** jq spawn count unchanged; will address in a follow-up if profiling shows it matters.
- **Risks identified:** Sourcing order between split modules; backward compatibility for any external scripts sourcing `workflow-state.sh` directly.
- **Constraints applied:** Must stay pure bash (plugin portability). Must not change the public API surface (`workflow-cmd.sh` case statement). Must not break security boundaries.
- **Tech debt acknowledged:** Batch jq optimization deferred. Regex patterns in `bash-write-guard.sh` need a test harness but that's a separate effort.

## Implementation Plan

### Phase 1: Split `workflow-state.sh` (god module decomposition)

**Goal:** Break 776-line god module into focused modules, each under 200 lines.

#### Task 1.1: Extract `state-io.sh` — core I/O primitives
- Move: `_safe_write()`, `_update_state()`, `STATE_DIR`/`STATE_FILE` vars, `_show` stub
- This becomes the foundation that all other modules source
- ~60 lines

#### Task 1.2: Extract `phase.sh` — phase management
- Move: `get_phase()`, `_phase_ordinal()`, `get_message_shown()`, `set_message_shown()`
- Sources: `state-io.sh`
- ~50 lines

#### Task 1.3: Extract `phase-gates.sh` — gate checks and transitions
- Move: `_check_phase_gates()`, `_read_preserved_state()`, `agent_set_phase()`, `check_soft_gate()`
- Move: `RESTRICTED_WRITE_WHITELIST`, `COMPLETE_WRITE_WHITELIST`
- Sources: `state-io.sh`, `phase.sh`, `milestones.sh`
- ~200 lines

#### Task 1.4: Extract `milestones.sh` — generic section/milestone helpers
- Move: `_reset_section()`, `_get_section_field()`, `_set_section_field()`, `_section_exists()`, `_check_milestones()`
- Move: Public API wrappers (`reset_review_status`, `get_review_field`, etc.)
- Sources: `state-io.sh`
- ~120 lines

#### Task 1.5: Extract `tracking.sh` — observation IDs, issue mappings
- Move: All `*_observation*`, `*_issue_*` functions
- Sources: `state-io.sh`
- ~120 lines

#### Task 1.6: Extract `coaching-state.sh` — coaching counters and throttle state
- Move: `increment_coaching_counter`, `reset_coaching_counter`, `add_coaching_fired`, `has_coaching_fired`, `check_coaching_refresh`, `*_pending_verify`, `set_autonomy_level`, `get_autonomy_level`
- Sources: `state-io.sh`
- ~80 lines

#### Task 1.7: Extract `settings.sh` — debug, active skill, plan/spec paths, tests
- Move: `get_debug`, `set_debug`, `*_active_skill`, `*_plan_path`, `*_spec_path`, `*_tests_passed_at`
- Sources: `state-io.sh`
- ~80 lines

#### Task 1.8: Create `workflow-state.sh` facade
- Replace the 776-line file with a thin facade that sources all split modules
- Existing scripts that `source workflow-state.sh` continue to work unchanged
- ~20 lines

#### Task 1.9: Update hook scripts to source only what they need
- `workflow-gate.sh`: source `state-io.sh`, `phase.sh`, `milestones.sh` (skip coaching, tracking)
- `bash-write-guard.sh`: source `state-io.sh`, `phase.sh`, `settings.sh` (skip coaching, tracking)
- `post-tool-navigator.sh`: keep sourcing full `workflow-state.sh` (needs everything)
- `workflow-cmd.sh`: keep sourcing full `workflow-state.sh` (exposes full API)

### Phase 2: Split `post-tool-navigator.sh` (coaching decomposition)

**Goal:** Break 786-line monolith into a dispatcher + individual check modules.

#### Task 2.1: Extract coaching check runner
- Create `scripts/coaching-runner.sh` — the throttle engine (`_should_fire`, `_reset_throttle`) and message collection (`_append_l3`, `_emit_output`)
- ~80 lines

#### Task 2.2: Extract Layer 3 checks into individual files
- Create `scripts/checks/` directory
- One file per check: `short-agent-prompt.sh`, `generic-commit.sh`, `all-findings-downgraded.sh`, `minimal-handover.sh`, `missing-project-field.sh`, `skipping-research.sh`, `options-without-recommendation.sh`, `no-verify-after-edits.sh`, `stalled-auto-transition.sh`, `step-ordering.sh`
- Each file exports a single function: `check_<name>()` that returns a message or empty string
- ~40-80 lines each

#### Task 2.3: Simplify `post-tool-navigator.sh` to dispatcher
- Layer 1 stays inline (simple, phase-dependent, once-per-phase)
- Layer 2 stays inline (trigger matching is phase-specific, not extractable without over-engineering)
- Layer 3 becomes: source check files, call each `check_*()` function
- Target: ~250 lines (down from 786)

### Phase 3: Clean up `bash-write-guard.sh`

**Goal:** Make regex patterns maintainable and fix debug inconsistency.

#### Task 3.1: Move regex patterns to a patterns config section
- Group related patterns with clear comments
- Replace string concatenation (`+=`) with single multi-line assignments
- No functional change, just readability

#### Task 3.2: Extract git commit chain parser
- Move the 3-strategy commit parsing (lines 99-132) into a helper function `_is_safe_git_chain()`
- Single responsibility, testable in isolation

#### Task 3.3: Fix debug logging inconsistency
- Replace all `if [ "$DEBUG_MODE" = "true" ]` checks in `workflow-gate.sh` with `_log` calls
- Ensure debug-log.sh is sourced before any `_log` calls (move the OFF early-exit after debug init)

### Phase 4: Fix remaining issues

#### Task 4.1: Fix `_should_fire()` jq interpolation
- Use `--arg` instead of string interpolation for check names in jq filters
- Change: `.coaching.throttle["${check_name}"]` → `--arg cn "$check_name" '.coaching.throttle[$cn]'`

#### Task 4.2: Replace python3 path canonicalization
- Use `realpath` (available on macOS 12.3+, all modern Linux)
- Keep python3 as fallback for older systems
- Reduces ~100ms per Write/Edit hook call

#### Task 4.3: Fix `_read_preserved_state()` invisible coupling
- Return values via a single JSON blob instead of writing to caller-scope variables
- Or: document the required pre-declarations in the function header and add a validation check

#### Task 4.4: Evaluate duplicated state template
- If security separation argument doesn't hold (both paths share `_safe_write` already), extract to a shared `_build_state_json()` function in `state-io.sh`
- If keeping duplication, add a checksum/test that verifies both templates produce identical schema

### Phase 5: Verification

#### Task 5.1: Manual smoke test
- Run through a full workflow cycle (define → discuss → implement → review → complete → off) with debug mode on
- Verify all hooks fire correctly, coaching messages appear, state transitions work

#### Task 5.2: Verify security boundaries
- Confirm `user-set-phase.sh` is still blocked from Bash tool
- Confirm guard-system self-protection still blocks edits to enforcement files
- Confirm destructive git operations are still blocked
- Test path traversal protection still works

#### Task 5.3: Line count validation
- No single file should exceed 300 lines (except `bash-write-guard.sh` which may be ~250)
- Total line count should stay roughly the same (structural split, not deletion)

## File Impact Summary

| Current File | Lines | Action | Result |
|---|---|---|---|
| `workflow-state.sh` | 776 | Split into 7 modules + facade | 7 files, ~20-200 lines each |
| `post-tool-navigator.sh` | 786 | Extract checks to `scripts/checks/` | ~250 lines + 10 check files (~50 each) |
| `bash-write-guard.sh` | 320 | Refactor in-place | ~280 lines (cleaner) |
| `workflow-gate.sh` | 136 | Fix debug logging, source optimization | ~130 lines |
| `user-set-phase.sh` | 112 | Evaluate template dedup | ~100 lines |
| `workflow-cmd.sh` | 114 | No change (facade, already clean) | 114 lines |
| `setup.sh` | 214 | No change (already fixed statusline bug) | 214 lines |
| `debug-log.sh` | 49 | No change (already clean) | 49 lines |

## Estimated New File Count

Current: 8 scripts
After: ~25 files (8 state modules + facade + coaching runner + 10 checks + 5 existing + 1 git helper)

## Risk Mitigation

- **Sourcing order**: Each module declares its dependencies explicitly via `source` at the top
- **Backward compat**: `workflow-state.sh` facade ensures existing `source workflow-state.sh` calls work
- **Security**: No changes to the user/agent path separation or guard-system protection logic
- **Rollback**: Each phase is independently committable; can stop after any phase
