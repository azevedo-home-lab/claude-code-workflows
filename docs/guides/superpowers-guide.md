# Superpowers Guide

Complete guide to using Superpowers with Claude Code for structured development workflows.

## What is Superpowers?

Superpowers is a third-party plugin for Claude Code created by @obra that provides:
- Structured workflow commands for DAIC phases
- 17+ skills that auto-activate contextually
- Battle-tested development patterns
- Quality gates and verification workflows

**Repository:** https://github.com/obra/superpowers

## Installation

### Add Marketplace and Install

```bash
plugin marketplace add obra/superpowers-marketplace
plugin install superpowers@superpowers-marketplace
```

### Verify Installation

```bash
/help
```

You should see Superpowers commands:
- `/superpowers:brainstorm`
- `/superpowers:write-plan`
- `/superpowers:execute-plan`
- Plus 17+ skills available for contextual activation

### Repository Status (verified Nov 23, 2025)

- **Actively maintained:** Created Oct 9, 2025; latest release v3.3.1 (Oct 28, 2025)
- **Activity:** 119 commits, ongoing development
- **Compatibility:** Works with Claude Code v2.0.49+

## Core Commands

### `/superpowers:brainstorm`

**When to use:** Discussion phase - refining requirements

**What it does:**
- Interactive Q&A to clarify all requirements
- Catches gaps and ambiguities upfront
- Saves refined scope to `docs/vision.md`

**Example:**

```
You: I want to add user authentication
Claude: Let me use /superpowers:brainstorm

Questions:
- What auth provider? (local, OAuth, both?)
- Password requirements?
- Session timeout duration?
- Token storage strategy?
```

**Benefits:**
- 30-40% less back-and-forth during implementation
- Comprehensive planning - nothing missed
- Documented assumptions for team alignment

---

### `/superpowers:write-plan`

**When to use:** Alignment phase - generating implementation plan

**What it does:**
- Creates detailed, numbered implementation plan
- Breaks work into logical steps
- Includes testing, monitoring, documentation
- Saves to `docs/plans/YYYY-MM-DD-<feature-name>.md`

**Example output:**

```markdown
## Authentication Implementation Plan

1. Database schema (users table, tokens table)
2. Password hashing service (bcrypt)
3. JWT generation/validation middleware
4. Login/logout/refresh endpoints
5. Protected route middleware
6. Unit tests for each component
7. Integration tests for auth flow
```

**Benefits:**
- See exactly what will be built before coding
- Judge effort and identify blockers upfront
- Approval gate prevents runaway implementation
- Clear milestones for progress tracking

---

### `/superpowers:execute-plan`

**When to use:** Implementation phase - batch execution

**What it does:**
- Executes plan steps in sequence
- Pauses at checkpoints for review
- Auto-activates relevant skills (TDD, error-fix, etc.)
- Logs all actions for session summary

**Example:**

```
✅ Checkpoint 1 complete: Database schema created
Continue? (y/n)

✅ Checkpoint 2 complete: Password service implemented
Continue? (y/n)

⏸️ Checkpoint 3: Review JWT middleware before proceeding?
```

**Benefits:**
- Quality gates let you review before proceeding
- Catch issues early, not after full implementation
- Skill automation (TDD/debugging/verification)
- Batch efficiency - no constant prompting needed

## Skills Library

### Auto-Activated Skills

These skills activate automatically when contextually relevant:

#### Testing & Development

**TDD Skill**
- **Activates:** When creating new functions/modules
- **Enforces:** Red-green-refactor cycle
- **Prevents:** "Code first, test later (never)"

**Example:**
```typescript
// TDD skill guides through:
1. Red: Write failing test for formatDate()
2. Green: Minimal implementation to pass
3. Refactor: Clean up implementation
4. Repeat for edge cases
```

---

#### Debugging & Errors

**Systematic Debugging Skill**
- **Activates:** When error logs/stack traces present
- **Provides:** Structured debugging workflow
- **Steps:** Identify pattern → analyze code → suggest fix → add regression test

**Error-Fix Skill**
- **Activates:** When errors detected during implementation
- **Adds:** Missing error handling, timeouts, validation
- **Example:** Detects missing network timeout, adds configuration

---

#### Code Quality

**Code-Review Skill**
- **Activates:** When refactoring/improving existing code
- **Analyzes:** Function responsibilities, SRP violations
- **Suggests:** Refactor steps with TDD enforcement

**Verification Skill**
- **Activates:** Before finito completion
- **Checks:** Tests passing, no debug code, no security vulnerabilities
- **Reports:** Missing items before commit

---

#### Workflow Tools

**Worktrees Skill**
- **Activates:** When juggling multiple features
- **Creates:** Isolated worktree with clean state
- **Benefits:** Work on multiple features in parallel, no context switching

**Deploy-Production Skill**
- **Activates:** When deploying to production
- **Provides:** Pre-deployment checklist
- **Executes:** Build → migrations → staging → production with monitoring

---

## Context Window Impact

### How It Works

- **On-demand loading:** Skills activate automatically when contextually relevant
- **Dynamic activation:** Debugging during troubleshooting, TDD during test work
- **Not preloaded:** Baseline system overhead + per-skill loading as needed

### Context Tradeoff

✅ **Benefits:**
- Structured workflows reduce re-explanation
- Battle-tested patterns save trial-and-error context
- Saved context from structure offsets overhead

⚠️ **Costs:**
- Activation system baseline overhead
- Loaded skills consume tokens

📊 **Net effect:**
- Likely neutral to positive
- Context cost manageable with DAIC structure
- Recommended: Monitor first few sessions

### Enforcement Note

> "When a skill exists for your task, using it becomes required"

Superpowers enforces mandatory workflow patterns when skills are available.

## Usage Examples

### Example 1: Full DAIC Cycle (Authentication)

**Scenario:** Add JWT-based authentication

**Discussion:**
```bash
You: I want to add JWT-based authentication with refresh tokens
Claude: /superpowers:brainstorm

# Clarifies:
- Auth provider? (local, OAuth, both?)
- Password requirements?
- Session timeout?
- Token storage strategy?

# Output: Refined scope in docs/vision.md
```

**Alignment:**
```bash
start^:  # cc-sessions gathers context
/superpowers:write-plan

# Output: 8-step plan
1. Database schema
2. Password hashing
3. JWT middleware
4. Endpoints
5. Tests
```

**Implementation:**
```bash
yert  # Approve plan
/superpowers:execute-plan

# Executes with checkpoints
✅ Checkpoint 1: Schema created
✅ Checkpoint 2: Password service done
⏸️ Review JWT middleware?
```

---

### Example 2: Debugging Production Issue

**Scenario:** Intermittent 500 errors on API endpoint

```bash
You: Getting 500 errors on /api/orders intermittently
Claude: [Debugging skill auto-activates]

# Structured workflow:
1. Reads error logs
2. Identifies pattern (high concurrency)
3. Analyzes for race conditions
4. Finds uncaught promise rejection
5. Suggests fix with error boundaries
6. Implements fix
7. Adds regression test
```

**Key benefit:** Structured debugging vs. ad-hoc exploration saves context

---

### Example 3: Refactoring Legacy Code

**Scenario:** 500-line god-function needs splitting

```bash
You: Refactor processOrder function in orders.service.ts

# Code-review skill auto-activates
# Analyzes function responsibilities
# Suggests SRP-compliant split:
- validateOrder()
- calculatePricing()
- applyDiscounts()
- processPayment()
- updateInventory()
- sendConfirmation()

# Uses /superpowers:write-plan for refactor steps
# Executes with /superpowers:execute-plan
# TDD skill ensures tests pass at each step
```

---

### Example 4: Git Worktrees for Parallel Features

**Scenario:** Work on feature-A while feature-B is in review

```bash
You: I need to start user-profiles while auth is in review

# Worktrees skill auto-activates
# Creates: ../user-profiles-worktree
# Copies minimal context (no node_modules)
# Sets up branch: feature/user-profiles
# Opens new Claude Code session in worktree
```

**Benefits:**
- No stashing/context switching
- Each worktree has clean state
- Parallel feature development

---

### Example 5: TDD Workflow

**Scenario:** Add date formatter utility

```bash
You: I want to add a date formatter utility using TDD

# TDD skill auto-activates
# Guides through red-green-refactor:

1. Red: Write failing test
   expect(formatDate('2025-11-23', 'MM/DD/YYYY'))

2. Green: Minimal implementation to pass

3. Refactor: Clean up

4. Red: Add edge case (null handling)

5. Green: Handle null

6. Repeat for timezones, invalid dates, etc.
```

---

### Example 6: Deploy to Production

**Scenario:** Feature tested, ready for production

```bash
You: Ready to deploy auth feature to production

# Deploy-production skill auto-activates
# Pre-deployment checklist:
✅ All tests passing?
✅ No console.logs or debug code?
✅ Environment variables documented?
✅ Database migrations ready?
✅ Rollback plan exists?

# Deployment steps:
1. Production build
2. Migrations (with backup)
3. Deploy to staging
4. Smoke tests on staging
5. Deploy to production
6. Monitor error rates
7. Send notification
```

---

### Example 7: Documentation Update

**Scenario:** Bug fixed, need to update docs

```bash
You: Update README to document new auth flow

# Docs-writer skill auto-activates
# Analyzes code changes
# Generates:
- Authentication flow diagram
- API endpoint descriptions
- Example usage code
- Environment variables needed

# Updates README with proper sections
```

## When Skills Auto-Activate vs Manual Commands

### Auto-Activation (Context-Driven)

- **Debugging skill** → Error logs/stack traces present
- **TDD skill** → Creating new functions/modules
- **Code-review** → Refactoring/improving existing code
- **Worktrees** → Juggling multiple features
- **Error-fix** → Errors detected during implementation

### Manual Commands (Workflow-Driven)

- **`/superpowers:brainstorm`** → Always manual, starts Discussion
- **`/superpowers:write-plan`** → Always manual, starts Alignment
- **`/superpowers:execute-plan`** → Always manual, starts Implementation

## Context Savings Comparison

### Without Superpowers

```
You: I want to add authentication
Claude: Sure, what kind?
You: JWT
Claude: Local or OAuth?
You: Local
Claude: Password requirements?
You: Standard... at least 8 chars
Claude: Okay, I'll implement...
[Writes code without plan]
[You realize later it's missing refresh tokens]
[More back-and-forth, context grows]
```

### With Superpowers

```
You: I want to add authentication
Claude: /superpowers:brainstorm
[Structured questionnaire covers all requirements upfront]
[Plan generated with all details]
[Execute once, correctly]
```

**Context saved:** ~30-40% fewer clarification rounds, no implementation rework

## Integration with cc-sessions

Superpowers provides the "how", cc-sessions provides the "when/where":

- **cc-sessions** manages task lifecycle, branches, logging
- **Superpowers** provides techniques (TDD, debugging, planning)

Use Superpowers skills **within** cc-sessions task workflow:
1. cc-sessions creates task and branch
2. Superpowers brainstorm refines requirements
3. cc-sessions gathers context
4. Superpowers write-plan creates detailed plan
5. cc-sessions locks approved scope
6. Superpowers execute-plan implements with quality gates
7. cc-sessions completes task with commit

## Troubleshooting

**Commands not appearing?**
- Verify installation: `plugin list`
- Reinstall: `plugin uninstall superpowers && plugin install superpowers@superpowers-marketplace`

**Skills not activating?**
- Skills activate based on context
- Try explicit trigger by mentioning the pattern (e.g., "let's use TDD")

**Too much context usage?**
- Monitor first few sessions
- Skills only load when needed
- Can uninstall if overhead problematic

## Next Steps

- Try `/superpowers:brainstorm` on your next feature
- Let skills auto-activate - observe when they trigger
- Review [Examples](examples.md) for more scenarios
- Check [cc-sessions Guide](cc-sessions-guide.md) for integration patterns
