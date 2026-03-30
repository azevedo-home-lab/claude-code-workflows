# Extract Coaching Messages from post-tool-navigator.sh

## Problem

The coaching messages in `plugin/scripts/post-tool-navigator.sh` are hardcoded as string literals (~26+ messages across ~628 lines). This creates four problems:

1. **Editorial friction** — Editing coaching tone/content requires navigating shell logic
2. **No user customization** — Plugin users can't adjust messages without forking the script
3. **No variant support** — Can't support terse/verbose or localized message sets
4. **Token waste** — Claude loads the entire script (all messages) even when only 1-2 fire per tool call
5. **Maintainability** — Message prose mixed with bash logic makes the script harder to read and modify

## Goals

- Coaching messages live in individual `.md` files, editable as prose
- Script contains only control flow logic — when and how messages fire
- Messages are lazy-loaded: only the triggered message file is read
- Missing message files silently skip (users can delete unwanted messages)
- The `[Workflow Coach — PHASE]` prefix remains in the script (structural, not editorial)

## Non-Goals

- Changing coaching logic (trigger conditions, counter thresholds, milestone checks)
- Adding new coaching messages
- Changing the hook output format (JSON with `systemMessage`)

## Decision

**Chosen approach:** Directory of individual markdown files (Approach B)

**Rationale:** Gives the best combination of editorial control, lazy-loading for token savings, simple loading mechanism (`cat` a file), and natural extensibility for future variants.

**Approaches considered:**
- **A: Single markdown file with heading-based sections** — Rejected because markdown parsing in bash is fragile, and no token savings (whole file loaded).
- **B: Directory of individual files** — Chosen. Simple `cat`-based loading. True lazy-loading. Each message independently editable.
- **C: Structured data file (JSON/YAML)** — Rejected because JSON is awkward for multi-line prose, and no token savings.

**Trade-offs accepted:** ~40 small files instead of inline strings. More filesystem overhead, but each file is tiny and the directory structure mirrors the architecture documentation.

## Design

### Directory Structure

```
plugin/coaching/
├── objectives/              # Phase entry messages (fire once per phase)
│   ├── define.md
│   ├── discuss.md
│   ├── implement.md
│   ├── review.md
│   ├── complete.md
│   └── error.md
├── nudges/                  # Contextual reminders (fire once per trigger per phase)
│   ├── agent_return_define.md
│   ├── plan_write_define.md
│   ├── agent_return_discuss.md
│   ├── plan_write_discuss.md
│   ├── source_edit_implement.md
│   ├── test_run_implement.md
│   ├── agent_return_review.md
│   ├── findings_present_review.md
│   ├── agent_return_complete.md
│   ├── project_docs_edit_complete.md
│   └── test_run_complete.md
├── checks/                  # Anti-laziness (fire on every match)
│   ├── short_agent_prompt.md
│   ├── generic_commit.md
│   ├── all_findings_downgraded.md
│   ├── minimal_handover.md
│   ├── missing_project_field.md
│   ├── skipping_research.md
│   ├── options_without_recommendation.md
│   ├── no_verify_after_edits.md
│   ├── stalled_auto_transition/
│   │   ├── implement.md
│   │   ├── discuss.md
│   │   └── review.md
│   └── step_ordering/
│       ├── complete_commit_before_validation.md
│       ├── complete_commit_before_docs.md
│       ├── complete_push_before_commit.md
│       ├── complete_handover_before_audit.md
│       ├── complete_pipeline_incomplete.md
│       ├── discuss_plan_before_research.md
│       ├── discuss_plan_before_approach.md
│       ├── discuss_pipeline_incomplete.md
│       ├── implement_code_before_plan.md
│       ├── implement_pipeline_incomplete.md
│       ├── review_findings_before_agents.md
│       ├── review_ack_before_findings.md
│       └── review_pipeline_incomplete.md
└── auto-transition/         # Autonomy=auto appendages
    ├── implement.md
    ├── review.md
    ├── complete.md
    └── default.md
```

### Message File Format

Each `.md` file contains only the message text. No frontmatter, no metadata, no prefix.

The `[Workflow Coach — PHASE]` prefix is added by the script at load time.

**Template variables** for messages that need dynamic values:
- `{{PHASE}}` — current phase name (uppercased)
- `{{COUNT}}` — numeric counter (context-dependent)

### Loading Mechanism

Helper function added to `post-tool-navigator.sh`:

```bash
COACHING_DIR="$SCRIPT_DIR/../coaching"

load_message() {
    local file="$COACHING_DIR/$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    local msg
    msg=$(cat "$file")
    if [ -n "${2:-}" ]; then
        msg=$(echo "$msg" | sed "s/{{PHASE}}/$2/g")
    fi
    if [ -n "${3:-}" ]; then
        msg=$(echo "$msg" | sed "s/{{COUNT}}/$3/g")
    fi
    echo "$msg"
}
```

**Error handling:** Missing files cause `load_message` to return 1 and produce no output. The script's existing `[ -n "$MSG" ]` checks handle this naturally — the message simply doesn't fire.

### Script Changes

Only string literals change. All logic stays identical.

| Section | Current | After |
|---------|---------|-------|
| Layer 1 (objectives) | 6 inline `MESSAGES="..."` blocks | `load_message "objectives/$PHASE.md"` |
| Layer 1 (auto-transition) | 4 inline appendages | `load_message "auto-transition/$PHASE.md"` with fallback to `default.md` |
| Layer 2 (nudges) | ~11 inline `L2_MSG="..."` | `load_message "nudges/$TRIGGER.md"` |
| Layer 3 (checks) | ~15 inline strings | `load_message "checks/$CHECK.md"` |
| Step ordering | ~13 inline strings | `load_message "checks/step_ordering/$KEY.md"` |

Estimated reduction: ~628 lines to ~500 lines in the script. ~40 new `.md` files.

### Architecture Documentation

The coaching section in `docs/reference/architecture.md` (line 64-70) already uses the correct terminology (objectives, nudges, checks). No changes needed there. The file organization section (line 80-100) should be updated to include the new `plugin/coaching/` directory.
