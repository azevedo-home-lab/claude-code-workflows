# Command Reference

Complete reference for all cc-sessions and Superpowers commands.

## DAIC Workflow Commands

### Discussion Phase

#### `mek: <task description>`

**Purpose:** Start new task and enter Discussion mode

**What it does:**
- Creates task tracking entry in cc-sessions
- Initializes session log
- Enters Discussion mode

**Benefits:**
- ✅ **Accountability:** Every task tracked from inception
- ✅ **Context preservation:** Session logs capture the "why" behind decisions
- ✅ **Searchable history:** Future you can search past tasks and reasoning
- ✅ **No lost work:** Everything documented, nothing forgotten

**Example:**
```bash
mek: Add email notifications for order confirmations
```

---

#### `/superpowers:brainstorm`

**Purpose:** Refine requirements through structured Q&A

**What it does:**
- Interactive Q&A to clarify requirements
- Saves refined scope to `docs/vision.md`

**Benefits:**
- ✅ **Prevents rework:** Catches gaps and ambiguities upfront
- ✅ **Comprehensive planning:** Structured questions ensure nothing is missed
- ✅ **Shared understanding:** Documents assumptions for team alignment
- ✅ **Context efficiency:** 30-40% less back-and-forth during implementation

**Example output:**
```
- Use SendGrid
- 3 retry attempts
- React Email templates
```

---

### Alignment Phase

#### `start^:`

**Purpose:** Load context and prepare for planning

**What it does:**
- Triggers context-gathering agent to analyze codebase
- Creates comprehensive context manifest specific to this task
- Loads relevant past session summaries
- Prepares for plan generation

**Benefits:**
- ✅ **Smart context:** Only loads what's relevant to THIS task
- ✅ **Codebase awareness:** Understands existing patterns, conventions, architecture
- ✅ **Avoids duplication:** Finds existing utilities/services before creating new ones
- ✅ **Informed planning:** Plans based on actual codebase, not assumptions

**Example:** Discovers existing EmailService base class, suggests extending instead of rewriting

---

#### `/superpowers:write-plan`

**Purpose:** Generate structured implementation plan

**What it does:**
- Creates detailed, numbered implementation plan
- Breaks work into logical steps
- Includes testing, monitoring, documentation

**Benefits:**
- ✅ **Clarity:** See exactly what will be built before code is written
- ✅ **Estimation:** Judge effort and identify blockers upfront
- ✅ **Approval gate:** Prevents runaway implementation that goes off-track
- ✅ **Progress tracking:** Clear milestones to track against

**Example plan:** 8 steps from infrastructure setup → testing → documentation

---

### Implementation Phase

#### `yert`

**Purpose:** Approve plan and begin implementation

**What it does:**
- Locks plan as approved scope
- Allows code edits ONLY for approved todos
- Any deviation triggers return to Discussion mode
- Starts detailed logging of all actions

**Benefits:**
- ✅ **Scope control:** Prevents feature creep and wandering implementation
- ✅ **Predictability:** Implementation follows the exact approved plan
- ✅ **Safety:** Can't accidentally break unrelated code
- ✅ **Audit trail:** Every change linked to approved plan item

**Example:** If Claude tries to add rate limiting (not in plan), cc-sessions blocks it

---

#### `/superpowers:execute-plan`

**Purpose:** Execute plan with checkpoints

**What it does:**
- Executes plan steps in sequence
- Pauses at checkpoints for review
- Auto-activates relevant skills (TDD, error-fix, etc.)
- Logs all actions for session summary

**Benefits:**
- ✅ **Quality gates:** Checkpoints let you review before proceeding
- ✅ **Error recovery:** Catch issues early, not after full implementation
- ✅ **Skill automation:** TDD/debugging/verification happen automatically
- ✅ **Batch efficiency:** Executes multiple steps without constant prompting

**Example checkpoints:** After infrastructure, after templates, after service, etc.

---

### Check Phase

#### `finito`

**Purpose:** Complete session with verification and commit

**What it does:**
- Runs verification checks
- Generates session summary
- Auto-commits with descriptive message
- Archives session logs
- Cleans up task tracking

**Benefits:**
- ✅ **Quality assurance:** Final verification before commit
- ✅ **Proper commits:** Well-formatted, descriptive commit messages
- ✅ **Knowledge capture:** Summary documents decisions and rationale
- ✅ **Context for future:** Next session can load summary for warm start
- ✅ **Clean closure:** Task marked complete, logs archived

**Example output:** Session summary markdown with decisions, duration, next steps

---

## Superpowers Skills (Auto-Activated)

These skills activate automatically when contextually relevant:

- **TDD skill** - Activates when creating new functions/modules
- **Debugging skill** - Activates when error logs/stack traces present
- **Code-review skill** - Activates when refactoring/improving existing code
- **Error-fix skill** - Activates when errors detected during implementation
- **Verification skill** - Activates before finito completion
- **Worktrees skill** - Activates when juggling multiple features

## Quick Reference Table

| Command | Phase | Purpose | Key Benefit |
|---------|-------|---------|-------------|
| `mek:` | Discussion | Start task | Accountability |
| `/superpowers:brainstorm` | Discussion | Refine requirements | Prevents rework |
| `start^:` | Alignment | Load context | Smart context |
| `/superpowers:write-plan` | Alignment | Generate plan | Approval gate |
| `yert` | Implementation | Approve plan | Scope control |
| `/superpowers:execute-plan` | Implementation | Execute | Quality gates |
| `finito` | Check | Complete & commit | Knowledge capture |
