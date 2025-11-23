# DAIC Workflow Quick Reference

Display this quick reference guide for the cc-sessions + Superpowers integrated workflow.

---

## 🔄 DAIC Workflow Commands

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

## 🎁 Key Benefits

- **Accountability:** Every task tracked from inception
- **No Lost Work:** Full session logs with decision rationale
- **Smart Context:** Only loads relevant code/history
- **Scope Control:** Prevents wandering implementation
- **Quality Gates:** TDD, verification, proper commits
- **Context Savings:** 30-40% less back-and-forth
- **Future You:** Warm starts from session summaries

---

## 📋 Full Sequence

1. **mek:** `Add email notifications` → Track task
2. **/superpowers:brainstorm** → Clarify (SendGrid? Retries? Testing?)
3. **start^:** → Analyze codebase for this task
4. **/superpowers:write-plan** → 8-step plan with testing
5. **yert** → Lock plan & start coding
6. **/superpowers:execute-plan** → Implement with checkpoints
7. **finito** → Verify, commit, archive summary

---

## 💡 Pro Tips

- **Discussion:** Use brainstorm even if you think requirements are clear
- **Alignment:** Review the plan carefully - easier to change now than during coding
- **Implementation:** Checkpoints are your friend - review before continuing
- **Check:** Read the summary - it's your future context

---

## 📚 More Details

For detailed examples and benefits breakdown, see: `workflow_proposal.md`
