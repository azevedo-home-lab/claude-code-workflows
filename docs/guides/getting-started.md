# Getting Started

Welcome! This guide will get you up and running with the cc-sessions + Superpowers workflow in under 10 minutes.

## Prerequisites

- Claude Code v2.0.49 or later
- Git repository for your project
- Basic familiarity with command line

## Installation

### Step 1: Install Superpowers

```bash
plugin marketplace add obra/superpowers-marketplace
plugin install superpowers@superpowers-marketplace
```

### Step 2: Verify Installation

```bash
/help
```

You should see Superpowers commands listed:
- `/superpowers:brainstorm`
- `/superpowers:write-plan`
- `/superpowers:execute-plan`

### Step 3: Set Up Directory Structure

```bash
mkdir -p sessions/logs .claude/context
```

### Step 4: Configure .gitignore

Ensure these paths are in your `.gitignore`:

```
# Session data (private)
sessions/
.claude/context/
.claude/.chats/
.claude/settings.local.json

# Credentials
token_do_not_commit/
.env
.env.local
```

### Step 5: Copy CLAUDE.md Template

```bash
cp claude.md.template CLAUDE.md
```

Edit `CLAUDE.md` to customize for your project (fill in placeholders).

## Your First Workflow

Let's walk through adding a simple feature using the DAIC workflow.

### Scenario: Add a Date Formatter Utility

#### 1. Discussion Phase

Start a new task:

```bash
mek: Add a date formatter utility function
```

Refine requirements:

```
/superpowers:brainstorm
```

**Superpowers will ask:**
- What date formats do you need? (ISO, US, EU?)
- Timezone handling?
- Edge cases? (null, invalid dates?)
- Testing strategy?

**Your answers:**
```
- Support ISO, US (MM/DD/YYYY), EU (DD/MM/YYYY)
- UTC by default, optional timezone parameter
- Return null for invalid input
- Use Jest for unit tests
```

**Output:** Requirements saved to `docs/vision.md`

#### 2. Alignment Phase

Load context:

```bash
start^:
```

**cc-sessions analyzes your codebase:**
- Finds existing utilities in `src/utils/`
- Checks for existing date libraries (moment, date-fns, etc.)
- Loads relevant past session summaries

Generate plan:

```
/superpowers:write-plan
```

**Superpowers generates plan:**

```markdown
## Date Formatter Implementation Plan

1. Create `src/utils/dateFormatter.ts`
2. Implement `formatDate(date, format, timezone?)` function
3. Add input validation
4. Create unit tests in `src/utils/__tests__/dateFormatter.test.ts`
5. Test edge cases (null, invalid dates, timezones)
6. Export from `src/utils/index.ts`
7. Update documentation
```

Review the plan. If it looks good:

```bash
yert
```

**cc-sessions locks this plan as approved scope.**

#### 3. Implementation Phase

Execute the plan:

```
/superpowers:execute-plan
```

**Superpowers executes with checkpoints:**

**Checkpoint 1: Create file and function**
```typescript
// src/utils/dateFormatter.ts
export function formatDate(
  date: Date | string | null,
  format: 'iso' | 'us' | 'eu',
  timezone: string = 'UTC'
): string | null {
  if (!date) return null;

  // Implementation...
}
```

```
✅ Checkpoint 1 complete: Function created
Continue? (y/n)
```

Type `y` to continue.

**Checkpoint 2: Add tests (TDD skill auto-activates)**
```typescript
// src/utils/__tests__/dateFormatter.test.ts
describe('formatDate', () => {
  test('formats ISO date', () => {
    expect(formatDate('2025-11-23', 'iso')).toBe('2025-11-23T00:00:00.000Z');
  });

  test('formats US date', () => {
    expect(formatDate('2025-11-23', 'us')).toBe('11/23/2025');
  });

  test('returns null for invalid input', () => {
    expect(formatDate(null, 'iso')).toBe(null);
  });
});
```

```
✅ Checkpoint 2 complete: Tests added (6/6 passing)
Continue? (y/n)
```

Type `y`.

**Checkpoint 3: Export and document**
```typescript
// src/utils/index.ts
export { formatDate } from './dateFormatter';
```

```
✅ Checkpoint 3 complete: Exported and documented
All plan items complete. Ready for verification.
```

#### 4. Check Phase

Complete the session:

```bash
finito
```

**cc-sessions verification:**
```
🔍 Running verification checklist:

✅ All tests passing (6/6)
✅ No console.logs or debug code
✅ TypeScript compilation successful
✅ ESLint: 0 errors, 0 warnings

Ready to commit
```

**Auto-commit:**
```bash
git commit -m "feat: Add date formatter utility

- Supports ISO, US, EU formats
- UTC by default with optional timezone
- Handles null/invalid input gracefully
- 6 unit tests covering edge cases

🤖 Generated with Claude Code + cc-sessions
Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Session summary saved:**
```
✅ Summary saved to sessions/logs/date-formatter-summary.md
✅ Task marked complete
```

## What Just Happened?

You successfully:
- ✅ Used structured brainstorming to refine requirements
- ✅ Let cc-sessions gather context about your codebase
- ✅ Generated and approved a detailed plan
- ✅ Executed with quality gates (checkpoints, TDD)
- ✅ Got a proper commit with full context
- ✅ Created a session summary for future reference

## Next Steps

Now that you understand the basics:

1. **Read the guides:**
   - [Superpowers Guide](superpowers-guide.md) - Deep dive into all features
   - [cc-sessions Guide](cc-sessions-guide.md) - Understand DAIC workflow
   - [Examples](examples.md) - More real-world scenarios

2. **Try it on a real task:**
   - Pick a small feature or bug fix
   - Run through the full DAIC workflow
   - Review your session summary

3. **Customize your setup:**
   - Edit `CLAUDE.md` with project-specific rules
   - Add custom slash commands in `.claude/commands/`
   - Configure session retention (default: 30 summaries)

## Troubleshooting

**Superpowers commands not showing?**
- Run `/help` to verify installation
- Try `plugin list` to see installed plugins
- Reinstall: `plugin uninstall superpowers && plugin install superpowers@superpowers-marketplace`

**Context gathering slow?**
- First run analyzes entire codebase
- Subsequent runs are faster (cached context)
- Tip: Use `.claudeignore` to exclude large directories

**Plan too detailed?**
- Superpowers generates comprehensive plans by default
- You can simplify during review before `yert`
- Edit the plan in Discussion mode if needed

## Quick Reference

Keep the [Workflow Cheatsheet](../quick-reference/workflow-cheatsheet.md) handy for daily use.

## Questions?

- Review [Architecture](../reference/architecture.md) to understand how components work together
- Check [Benefits Analysis](../reference/benefits-analysis.md) for detailed rationale
- Browse [Examples](examples.md) for more usage scenarios
