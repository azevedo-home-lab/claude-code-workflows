# Workflow Cheatsheet

Ultra-concise reference for daily use. Print this out or bookmark it.

## DAIC Workflow Commands

### 📝 Discussion Phase
```bash
mek: <task description>          # Start new task
/superpowers:brainstorm          # Refine requirements with Q&A
```
**Why:** Captures requirements upfront, prevents rework (saves 30-40% back-and-forth)

---

### 🎯 Alignment Phase
```bash
start^:                          # Gather context & load plan
/superpowers:write-plan          # Generate structured plan
```
**Why:** Context-aware planning based on actual codebase, not assumptions

---

### 🔨 Implementation Phase
```bash
yert                             # Approve plan & begin implementation
/superpowers:execute-plan        # Batch execution with checkpoints
```
**Why:** Scope control prevents feature creep, checkpoints catch issues early

---

### ✅ Check Phase
```bash
finito                           # Verify, commit, archive
```
**Why:** Quality gates, proper commits, knowledge capture for future sessions

---

## Visual Flow

```
┌─────────────────────────────────────────────────────────────┐
│ DISCUSSION (D)                                              │
│ mek: Add auth → /superpowers:brainstorm                     │
│ Output: Refined requirements in docs/vision.md              │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ ALIGNMENT (A)                                               │
│ start^: → /superpowers:write-plan                          │
│ Output: 8-step implementation plan, ready for approval      │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ IMPLEMENTATION (I)                                          │
│ yert → /superpowers:execute-plan                           │
│ Output: Code changes with checkpoints, TDD enforced         │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ CHECK (C)                                                   │
│ finito                                                      │
│ Output: Commit, summary in sessions/logs/                   │
└─────────────────────────────────────────────────────────────┘
```

## Full Example Sequence

```bash
# 1. Start
mek: Add email notifications

# 2. Clarify
/superpowers:brainstorm
# Answer: SendGrid? Retries? Testing?

# 3. Context
start^:
# Analyzes codebase for this task

# 4. Plan
/superpowers:write-plan
# Generates 8-step plan with testing

# 5. Approve
yert
# Locks plan, allows implementation

# 6. Execute
/superpowers:execute-plan
# Implements with checkpoints

# 7. Complete
finito
# Verify, commit, archive summary
```

## Key Benefits Reminder

- **Accountability:** Every task tracked from inception
- **No Lost Work:** Full session logs with decision rationale
- **Smart Context:** Only loads relevant code/history
- **Scope Control:** Prevents wandering implementation
- **Quality Gates:** TDD, verification, proper commits
- **Context Savings:** 30-40% less back-and-forth
- **Future You:** Warm starts from session summaries

## Pro Tips

- **Discussion:** Use brainstorm even if requirements seem clear
- **Alignment:** Review plan carefully - easier to change now than during coding
- **Implementation:** Checkpoints are your friend - review before continuing
- **Check:** Read the summary - it's your future context
