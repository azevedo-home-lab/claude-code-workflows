# Architecture

How cc-sessions and Superpowers work together to create structured development workflows.

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                        User                             │
│                   (You/Developer)                        │
└───────────────────┬─────────────────────────────────────┘
                    │
                    │ Issues commands
                    ↓
        ┌──────────────────────────┐
        │     Claude Code CLI      │
        │   (Official Platform)    │
        └──────────┬────────┬──────┘
                   │        │
        ┌──────────┘        └──────────┐
        ↓                                ↓
┌──────────────┐              ┌─────────────────┐
│  cc-sessions │              │  Superpowers    │
│  (Workflow)  │◄────────────►│  (Techniques)   │
└──────┬───────┘              └────────┬────────┘
       │                               │
       │ Controls:                     │ Provides:
       │ - Task lifecycle              │ - Brainstorming
       │ - Git branches                │ - Plan generation
       │ - Scope enforcement           │ - Batch execution
       │ - Session logging             │ - Auto-skills
       │ - Commit workflow             │   (TDD, debug)
       │                               │
       └───────────┬───────────────────┘
                   │
                   ↓
        ┌──────────────────────┐
        │    Your Codebase     │
        │  (Git Repository)    │
        └──────────────────────┘
```

## Component Responsibilities

### Claude Code (Official Platform)

**Role:** Hosting environment for extensions/plugins

**Provides:**
- Terminal interface for commands
- Tool execution (Read, Write, Edit, Bash, etc.)
- Plugin system (marketplace, installation)
- Context management
- User interaction

**Does NOT provide:**
- Workflow structure (added by cc-sessions)
- Development techniques (added by Superpowers)

---

### cc-sessions (Workflow Manager)

**Role:** Task management and DAIC workflow enforcement

**Provides:**

1. **Task Lifecycle:**
   - Task creation (`mek:`)
   - Status tracking (pending → in-progress → completed)
   - Session logs in `sessions/logs/`

2. **Git Integration:**
   - Branch creation per task
   - Auto-commit with descriptive messages
   - Optional PR creation

3. **Context Gathering:**
   - Triggers at `start^:` command
   - Analyzes codebase for specific task
   - Loads relevant past session summaries

4. **Scope Enforcement:**
   - Locks plan after `yert` approval
   - Blocks edits outside approved scope
   - Returns to Discussion mode if deviation detected

5. **Session Summaries:**
   - Generates after `finito`
   - Stores in `sessions/logs/`
   - Enables future warm starts

**Configuration:**
- Trigger phrases (mek, start^, yert, finito)
- Retention policy (default: 30 summaries)
- Auto-commit settings
- PR creation settings

---

### Superpowers (Technique Provider)

**Role:** Implementation techniques and quality gates

**Provides:**

1. **Core Commands:**
   - `/superpowers:brainstorm` - Requirements refinement
   - `/superpowers:write-plan` - Plan generation
   - `/superpowers:execute-plan` - Batch execution

2. **Auto-Activated Skills:**
   - **TDD** - Red-green-refactor enforcement
   - **Systematic Debugging** - Structured bug investigation
   - **Code Review** - Pre-commit review
   - **Error Fix** - Auto-detects missing error handling
   - **Verification** - Pre-completion checklist
   - **Worktrees** - Parallel feature development

3. **Context Awareness:**
   - Skills load when contextually relevant
   - On-demand loading (not preloaded)
   - Minimal baseline overhead

**Configuration:**
- Plugin installation via marketplace
- Skills available but load dynamically
- No forced activation (optional use)

---

## Integration Points

### How They Work Together

```
DISCUSSION PHASE:
┌─────────────────────────┐
│ User: mek: Add feature  │
│ cc-sessions: Create task│
│ cc-sessions: Lock tools │
└──────────┬──────────────┘
           │
           ↓
┌──────────────────────────────┐
│ User: /superpowers:brainstorm│
│ Superpowers: Q&A refinement  │
│ Superpowers: Save to vision  │
└──────────┬───────────────────┘
           │
           ↓
ALIGNMENT PHASE:
┌─────────────────────────┐
│ User: start^:           │
│ cc-sessions: Gather ctx │
│ cc-sessions: Load history│
└──────────┬──────────────┘
           │
           ↓
┌──────────────────────────────┐
│ User: /superpowers:write-plan│
│ Superpowers: Generate plan   │
│ cc-sessions: Display plan    │
└──────────┬───────────────────┘
           │
           ↓
┌─────────────────────────┐
│ User: yert              │
│ cc-sessions: Lock scope │
│ cc-sessions: Enable edit│
└──────────┬──────────────┘
           │
           ↓
IMPLEMENTATION PHASE:
┌────────────────────────────────┐
│ User: /superpowers:execute-plan│
│ Superpowers: Execute step 1    │
│ cc-sessions: Log action        │
│ Superpowers: Checkpoint        │
│ User: continue                 │
│ Superpowers: Execute step 2    │
│ ... (repeat for all steps)     │
└──────────┬─────────────────────┘
           │
           ↓
CHECK PHASE:
┌─────────────────────────┐
│ User: finito            │
│ Superpowers: Verify     │
│ cc-sessions: Summary    │
│ cc-sessions: Commit     │
│ cc-sessions: Archive    │
└─────────────────────────┘
```

---

## Data Flow

### Session Logs

**Location:** `sessions/logs/`

**Format:** JSON + Markdown summary

**Contents:**
```json
{
  "taskId": "add-email-notifications",
  "startTime": "2025-11-23T14:30:00Z",
  "endTime": "2025-11-23T16:00:00Z",
  "phase": "completed",
  "requirements": "docs/vision.md",
  "plan": {
    "steps": [...]
  },
  "actions": [
    { "type": "file_write", "path": "src/services/email.service.ts" },
    { "type": "test_run", "result": "18/18 passed" }
  ],
  "summary": "sessions/logs/email-notifications-summary.md"
}
```

### Context Manifest

**Created at:** `start^:` command

**Purpose:** Task-specific context

**Contents:**
```markdown
## Context for: Add Email Notifications

### Existing Code:
- EmailService base class (src/services/)
- Retry utility (src/utils/retry.ts)
- Email templates (src/templates/)

### Patterns:
- Services use dependency injection
- Tests in __tests__ directories
- Errors use AppError class

### Past Sessions:
- 2025-11-15: SMS notifications
- 2025-11-10: Retry logic

### Recommendations:
- Extend EmailService base
- Reuse retry.ts utility
- Follow SMS pattern
```

### Plan Documents

**Location:** `docs/plans/YYYY-MM-DD-<feature>.md`

**Created by:** `/superpowers:write-plan`

**Format:** Markdown with code snippets

**Used by:**
- cc-sessions for scope enforcement
- Superpowers execute-plan for batch execution
- Developer for manual implementation

---

## Scope Enforcement Mechanism

### How It Works

1. **Discussion Mode (default):**
   ```
   Edit/Write tools: BLOCKED
   Read/Search tools: ALLOWED
   Purpose: Force requirements clarity
   ```

2. **Plan Generated:**
   ```
   Approved todos: NONE (yet)
   Edit/Write tools: BLOCKED (waiting for approval)
   ```

3. **Plan Approved (yert):**
   ```
   Approved todos: [Step 1, Step 2, ..., Step N]
   Edit/Write tools: UNLOCKED (for approved files only)
   ```

4. **Implementation:**
   ```
   Attempt to edit approved file:
     ✅ ALLOWED - proceed

   Attempt to edit non-approved file:
     ❌ BLOCKED - show warning:
        "File X not in approved plan.
         Return to Discussion mode to add? (y/n)"
   ```

5. **Completion (finito):**
   ```
   All todos complete:
     ✅ Return to Discussion mode
     ✅ Lock tools again
     ✅ Generate summary
     ✅ Commit changes
   ```

---

## Skills Activation System

### Context-Driven Activation

**How Superpowers decides to activate skills:**

```python
# Pseudo-code for skill activation

if detecting_error_logs() or has_stack_trace():
    activate_skill("systematic-debugging")

if creating_new_function() and no_existing_tests():
    activate_skill("test-driven-development")

if editing_existing_code() and complexity_high():
    activate_skill("code-review")

if about_to_commit() and todos_marked_complete():
    activate_skill("verification-before-completion")

if user_mentions("parallel features") or user_mentions("worktree"):
    activate_skill("using-git-worktrees")
```

**Benefits:**
- No manual skill triggering needed
- Skills load only when relevant
- Minimal context overhead

---

## File Organization

### Directory Structure

```
your-project/
├── .claude/
│   ├── commands/          # Custom slash commands
│   ├── context/           # Compact session mirrors (optional)
│   └── settings.json      # Claude Code config
│
├── sessions/
│   └── logs/              # Session summaries (authoritative)
│       ├── 2025-11-23_email-notifications.md
│       └── 2025-11-22_user-auth.md
│
├── docs/
│   ├── vision.md          # Requirements (from brainstorm)
│   └── plans/             # Implementation plans
│       └── 2025-11-23-email-notifications.md
│
├── src/                   # Your code
│   ├── services/
│   ├── utils/
│   └── __tests__/
│
└── CLAUDE.md              # Project-specific rules
```

### What Gets Committed

**Committed to git:**
- ✅ `CLAUDE.md` (project rules)
- ✅ `.claude/commands/` (team slash commands)
- ✅ `.claude/settings.json` (team settings)
- ✅ `docs/plans/` (implementation plans)
- ✅ `docs/vision.md` (requirements)

**Ignored (.gitignore):**
- ❌ `sessions/` (private session logs)
- ❌ `.claude/context/` (local mirrors)
- ❌ `.claude/.chats/` (conversation history)
- ❌ `.claude/settings.local.json` (user-specific)

---

## Extension Points

### Custom Slash Commands

**Location:** `.claude/commands/my-command.md`

**Example:** `.claude/commands/workflow.md`
```markdown
# DAIC Workflow Quick Reference

Display quick reference for DAIC commands.

---

## Commands
...
```

**Usage:** `/workflow`

### Custom Skills

**For Superpowers:** Create local skill wrappers

**Example:** cc-sessions aware brainstorming
```markdown
# Custom Brainstorming Wrapper

1. Check if in cc-sessions task context
2. If yes: Save to sessions/tasks/<task>/design.md
3. If no: Save to docs/plans/
4. Do NOT commit automatically
```

---

## Performance Characteristics

### Context Usage

| Component | Baseline | Per-Task | Notes |
|-----------|----------|----------|-------|
| cc-sessions | ~1K tokens | ~2K tokens | Context manifest |
| Superpowers | ~2K tokens | ~3-5K tokens | Active skills |
| Skills (each) | 0 tokens | ~1-2K tokens | Only when loaded |

**Total typical session:** ~8-10K tokens (vs ~15-20K ad-hoc clarifications)

**Net savings:** 30-40% context efficiency

### Time Overhead

| Phase | Overhead | Benefit |
|-------|----------|---------|
| Discussion | +5 min (brainstorm) | -15 min (fewer clarifications) |
| Alignment | +2 min (context gather) | -30 min (no duplicate work) |
| Implementation | +3 min (checkpoints) | -45 min (no refactors) |
| Check | +2 min (verification) | -20 min (proper commit) |

**Net:** ~40% time savings on medium-large features

---

## Security Model

### Token Protection

cc-sessions verifies `.gitignore` contains:
- `sessions/` (private logs may contain snippets)
- `.claude/context/` (local mirrors)
- `token_do_not_commit/` (credential storage)

### Commit Safety

Before `finito` commits:
1. Scan for common secret patterns
2. Check `.env` files not in changeset
3. Verify no `console.log` with sensitive data
4. Warn if committing to `token_do_not_commit/`

---

## Troubleshooting

### Common Issues

**"Tools are locked"**
- **Cause:** Still in Discussion mode
- **Fix:** Approve plan with `yert`

**"File not in approved plan"**
- **Cause:** Scope enforcement blocking edit
- **Fix:** Either return to Discussion to add file, OR create separate task

**"Context gathering slow"**
- **Cause:** First run analyzes entire codebase
- **Fix:** Add `.claudeignore` for large dirs (node_modules, dist)

**"Skills not activating"**
- **Cause:** Context not matching activation patterns
- **Fix:** Manually mention pattern (e.g., "let's use TDD")

---

## Next Steps

- Review [Benefits Analysis](benefits-analysis.md) for detailed rationale
- See [Examples](../guides/examples.md) for architecture in action
- Read [cc-sessions Guide](../guides/cc-sessions-guide.md) for workflow details
- Check [Superpowers Guide](../guides/superpowers-guide.md) for skills reference
