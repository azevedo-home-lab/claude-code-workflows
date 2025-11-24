# cc-sessions Guide

Complete guide to understanding and using the DAIC workflow with cc-sessions.

## What is cc-sessions?

cc-sessions is a session management tool that enforces the DAIC (Discuss → Align → Implement → Check) workflow for structured development.

**Key Features:**
- Task lifecycle management
- Git branch automation
- Context gathering before implementation
- Scope enforcement (prevents feature creep)
- Session logging and summaries
- Auto-commit with proper messages

## The DAIC Loop

The DAIC workflow has four phases that prevent scope creep and ensure quality:

```
┌─────────────┐
│  DISCUSS    │  Clarify what needs to be built
│     (D)     │
└──────┬──────┘
       ↓
┌─────────────┐
│   ALIGN     │  Plan how to build it
│     (A)     │
└──────┬──────┘
       ↓
┌─────────────┐
│ IMPLEMENT   │  Build it (locked to approved plan)
│     (I)     │
└──────┬──────┘
       ↓
┌─────────────┐
│   CHECK     │  Verify, commit, archive
│     (C)     │
└─────────────┘
```

### Why DAIC?

**Problem it solves:**
- **Without structure:** Requirements unclear → plan changes mid-implementation → scope creeps → rework → context explosion
- **With DAIC:** Requirements locked → plan approved → implementation scoped → verify before commit → controlled context

**Benefits:**
- Prevents "while we're at it..." feature creep
- Forces upfront clarification (saves 30-40% back-and-forth)
- Audit trail of decisions
- Proper commits with context

## DAIC Commands

### Discussion Phase

#### `mek: <task description>`

**Purpose:** Start new task

**What happens:**
```bash
mek: Add email notifications for order confirmations

# cc-sessions:
- Creates task tracking entry
- Initializes session log in sessions/logs/
- Enters Discussion mode
- Locks tool writes until plan approved
```

**Benefits:**
- Every task tracked from inception
- Session logs capture the "why" behind decisions
- Searchable history for future reference

**Example:**
```bash
mek: Add user authentication with JWT
mek: Fix race condition in payment processing
mek: Refactor order service for better testability
```

---

### Alignment Phase

#### `start^:`

**Purpose:** Gather context and prepare for planning

**What happens:**
```bash
start^:

# cc-sessions:
- Triggers context-gathering agent
- Analyzes codebase for THIS specific task
- Finds existing patterns, utilities, conventions
- Loads relevant past session summaries
- Creates comprehensive context manifest
- Prepares for plan generation
```

**This is when context gathering happens!** Not at session start, but after discussion when you know what you're building.

**Benefits:**
- Smart context - only loads relevant code
- Codebase awareness - understands existing patterns
- Avoids duplication - finds existing utilities first
- Informed planning - plans based on actual codebase

**Example output:**
```
Context Analysis Complete:
- Found existing EmailService base class in src/services/
- Located email templates in src/templates/
- Identified retry logic pattern in src/utils/retry.ts
- Loaded 3 relevant past session summaries

Ready for plan generation.
```

---

#### `yert`

**Purpose:** Approve plan and begin implementation

**What happens:**
```bash
yert

# cc-sessions:
- Locks plan as approved scope
- Allows code edits ONLY for approved todos
- Any deviation triggers return to Discussion mode
- Starts detailed logging of all actions
- Marks session as "Implementation" phase
```

**This is the approval gate!** After this, only approved plan items can be implemented.

**Benefits:**
- **Scope control:** Prevents feature creep
- **Predictability:** Implementation follows exact approved plan
- **Safety:** Can't accidentally break unrelated code
- **Audit trail:** Every change linked to approved plan item

**Example:**
```bash
# Approved plan:
1. Create EmailService
2. Add retry logic
3. Write tests

# If Claude tries to add:
4. Add rate limiting (NOT in plan)

# cc-sessions blocks it:
⚠️ Rate limiting not in approved plan
⚠️ Return to Discussion mode to add this feature
```

---

### Check Phase

#### `finito`

**Purpose:** Complete session with verification and commit

**What happens:**
```bash
finito

# cc-sessions executes:
1. Runs verification checks
2. Generates session summary
3. Auto-commits with descriptive message
4. Archives session logs
5. Cleans up task tracking
6. Optionally creates PR
```

**Benefits:**
- Quality assurance before commit
- Well-formatted commit messages
- Knowledge capture for future sessions
- Clean closure of task

**Example workflow:**
```bash
finito

# Verification:
🔍 Running checks:
✅ All tests passing (18/18)
✅ No console.logs or debug code
✅ TypeScript compilation successful
✅ No security vulnerabilities

# Auto-commit:
git commit -m "feat: Add email notifications

- Implemented EmailService with SendGrid
- Added retry logic (3 attempts, exponential backoff)
- Created React Email templates
- 18 tests covering all scenarios

🤖 Generated with Claude Code + cc-sessions
Co-Authored-By: Claude <noreply@anthropic.com>"

# Session summary:
✅ Summary saved to sessions/logs/2025-11-23_email-notifications.md
✅ Task marked complete
```

---

## Session Management

### Session Logs

**Location:** `sessions/logs/`

**What's stored:**
- Full task description and requirements
- Context gathering results
- Approved plan
- All implementation actions
- Verification results
- Decisions and rationale

**Retention:**
```bash
# Default: Keep last 30 summaries
ls -1t sessions/logs | tail +31 | xargs -I{} rm -f sessions/logs/{}
```

**Benefits:**
- Future sessions can load relevant summaries for warm starts
- Searchable history of past decisions
- Audit trail for debugging "why did we do this?"

---

### Context Gathering

**When it happens:** At `start^:` command (after Discussion, before planning)

**What it does:**
- Analyzes codebase structure
- Finds existing patterns and utilities
- Identifies architectural conventions
- Loads relevant past session summaries
- Creates manifest for this specific task

**Example manifest:**
```markdown
## Context for: Add Email Notifications

### Existing Code Found:
- EmailService base class (src/services/email.service.ts)
- Retry utility (src/utils/retry.ts)
- Email templates directory (src/templates/)
- SendGrid already configured (environment variables present)

### Architectural Patterns:
- Services use dependency injection
- Tests colocated in __tests__ directories
- Error handling uses custom AppError class

### Relevant Past Sessions:
- 2025-11-15: SMS notifications (similar pattern)
- 2025-11-10: Retry logic implementation

### Recommendations:
- Extend existing EmailService base class
- Reuse retry.ts utility
- Follow SMS notification pattern for consistency
```

**Benefits:**
- Plans based on actual codebase, not assumptions
- Avoids reinventing existing utilities
- Maintains consistency with established patterns
- Faster planning with relevant context loaded

---

### Scope Enforcement

**How it works:**

1. **Discussion mode (D):** Tool writes locked, discussion only
2. **Plan generated:** Detailed todos created
3. **Approval (yert):** Plan locked as approved scope
4. **Implementation (I):** Can ONLY edit files related to approved todos
5. **Deviation detected:** Returns to Discussion mode

**Example:**

```bash
# Approved plan:
1. Add email notification service
2. Create order confirmation template
3. Integrate with order.service.ts

# During implementation:
Claude: "While I'm here, let me also add SMS notifications"

# cc-sessions blocks:
⚠️ SMS notifications not in approved plan
⚠️ This violates scope control
⚠️ Options:
   1. Return to Discussion mode to add SMS to plan
   2. Continue with approved email notifications only

Which option? (1/2)
```

**Benefits:**
- Prevents "while we're at it..." scope creep
- Forces explicit discussion of new features
- Maintains audit trail of scope changes
- Predictable implementation time

---

## Integration with Superpowers

cc-sessions and Superpowers work together:

**cc-sessions provides:**
- Task lifecycle management
- Git branch automation
- Scope enforcement
- Session logging
- Commit workflow

**Superpowers provides:**
- Brainstorming technique (Discussion phase)
- Plan generation (Alignment phase)
- Batch execution with checkpoints (Implementation phase)
- Auto-activated skills (TDD, debugging, verification)

**Complete workflow:**

```bash
# 1. Start task (cc-sessions)
mek: Add feature X

# 2. Refine requirements (Superpowers)
/superpowers:brainstorm

# 3. Gather context (cc-sessions)
start^:

# 4. Generate plan (Superpowers)
/superpowers:write-plan

# 5. Approve plan (cc-sessions)
yert

# 6. Execute with checkpoints (Superpowers)
/superpowers:execute-plan

# 7. Complete session (cc-sessions)
finito
```

---

## Session Summaries

### What's in a summary?

```markdown
# Email Notifications Implementation - Session Summary

## Duration: 2.5 hours
## Tasks Completed: 8/8

### What was built:
- EmailService with SendGrid integration
- React Email template (OrderConfirmation)
- Retry logic with exponential backoff
- Job queue integration (Bull)
- Comprehensive test suite

### Key Decisions:
- Used SendGrid over AWS SES for simplicity
- React Email for maintainable templates
- Job queue for async processing (doesn't block order confirmation)
- Ethereal for testing (no real emails sent in dev)

### Testing:
- 18 tests written (unit + integration)
- 100% pass rate
- Includes retry logic tests
- Includes DLQ failure handling

### Next Steps (if needed):
- Monitor email success rates in production
- Add email templates for other order events (shipped, delivered)
- Consider rate limiting if volume increases
```

### How to use summaries

**Load for warm start:**
```bash
# Next session working on related feature:
"Load the email notifications session summary for context"

# Claude reads:
sessions/logs/2025-11-23_email-notifications-summary.md

# Now has context:
- How email system works
- Why SendGrid was chosen
- Where templates are located
- What testing patterns were used
```

**Benefits:**
- No need to re-explain past decisions
- Consistent patterns across sessions
- Faster warm-up for related tasks
- Institutional memory preserved

---

## Workflow Comparison

### Without cc-sessions

```
You: Add email notifications
Claude: [Starts coding immediately]
You: Wait, use SendGrid
Claude: [Rewrites for SendGrid]
You: Also need retries
Claude: [Adds retries]
You: And queue it so order confirmation isn't blocked
Claude: [Refactors to add queue]
You: [2 hours later] Wait, where are the tests?
Claude: [Adds tests after the fact]

Result:
- 2+ hours of back-and-forth
- 3 refactors
- Tests as afterthought
- No summary for future reference
```

### With cc-sessions

```
mek: Add email notifications
/superpowers:brainstorm
# Answers: SendGrid? Retries? Queue? Tests? [10 min]

start^:
# Context gathered [2 min]

/superpowers:write-plan
# 8-step plan with all decisions [5 min]

yert
# Plan locked [instant]

/superpowers:execute-plan
# Implementation with checkpoints [45 min]

finito
# Verified, committed, summarized [5 min]

Result:
- 67 minutes total
- 1 implementation pass (no refactors)
- Tests built-in via TDD
- Summary for future reference
- ~40% time savings vs ad-hoc
```

---

## Best Practices

### 1. Always use brainstorming

Even if requirements seem clear, run `/superpowers:brainstorm` - it catches edge cases you didn't consider.

### 2. Review plans carefully

The plan review happens BEFORE coding - this is when it's easy to change. After `yert`, scope is locked.

### 3. Trust the checkpoints

When `/superpowers:execute-plan` pauses for review, actually review. Catching issues early is cheaper than refactoring later.

### 4. Read your summaries

The session summary is your future context - read it before marking complete. It's what future-you will thank past-you for.

### 5. Don't fight scope enforcement

If cc-sessions blocks a change as out-of-scope, there's a reason. Either:
- Return to Discussion mode to add it properly, OR
- Create a new task for the additional feature

Don't try to sneak changes in - it breaks the audit trail.

---

## Troubleshooting

**Task stuck in Discussion mode?**
- Make sure you approved the plan with `yert`
- Check that a plan was actually generated

**Context gathering slow?**
- First run analyzes entire codebase (slow)
- Subsequent runs use cached context (fast)
- Use `.claudeignore` to exclude large directories (node_modules, etc.)

**Commits not happening automatically?**
- Check if `finito` is configured to auto-commit
- Some setups require manual `git commit` after `finito`

**Session summaries too verbose?**
- Summaries include all context for future warm starts
- You can customize summary format in cc-sessions config

---

## Next Steps

- Try a full DAIC cycle on a small feature
- Review [Superpowers Guide](superpowers-guide.md) for technique integration
- Browse [Examples](examples.md) for real-world scenarios
- Check [Benefits Analysis](../reference/benefits-analysis.md) for detailed rationale
