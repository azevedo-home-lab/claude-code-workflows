# Plan: Workflow Enforcement Hooks for Superpowers

**Date**: 2026-03-15
**Status**: Plan
**Purpose**: Hard-gate code edits until a plan is discussed and approved, complementing superpowers' prompt-based discipline with deterministic PreToolUse hook enforcement.

## Problem

Superpowers enforces workflow phases (brainstorm → plan → execute → verify) via prompt instructions. Claude can rationalize skipping the planning phase with "this is simple" or "I'll plan as I go." The superpowers project itself documented 12 specific rationalization patterns. Prompt discipline alone is insufficient — Claude needs a hard gate that physically prevents code edits until a plan exists and the user approves it.

cc-sessions solved this with DAIC gating but is abandoned (last commit Oct 2025). No maintained replacement exists. Claude Code's native plan mode is not enforced — it's a prompt suggestion, not a technical gate (confirmed by Anthropic issue tracker).

## Design

### Two-Phase Model

```
DISCUSS ──(user: /approve)──> IMPLEMENT ──(task done or user: /discuss)──> DISCUSS
```

Only two phases. Superpowers handles sub-phases (brainstorm vs plan, TDD vs verify) through prompt discipline — that works well enough. The only boundary worth enforcing with hooks is **discuss-before-code**.

- **DISCUSS**: Covers brainstorming + planning. Write/Edit BLOCKED.
- **IMPLEMENT**: Covers executing + TDD + verification + review. Write/Edit ALLOWED.

### Hard-Gate Rules

| Tool | DISCUSS phase | IMPLEMENT phase |
|------|--------------|-----------------|
| Write, Edit, MultiEdit, NotebookEdit | **BLOCKED** | Allowed |
| Bash with write patterns | **BLOCKED** | Allowed |
| Read, Grep, Glob, Agent, WebSearch | Allowed | Allowed |
| Git commit/push | Allowed | Allowed |

**Bash write patterns caught** (95% coverage, not 100% — Claude isn't adversarial):
- Redirections: `>`, `>>`
- In-place edits: `sed -i`, `sed -i''`
- Pipe to file: `tee`
- Heredocs: `cat > file << EOF`, `cat > file <<'EOF'`
- Python writes: `python -c` or `python3 -c` with `open`/`write`
- Echo redirects: `echo ... >`

**Not gated** (would cause friction without value):
- Read/Grep/Glob — Claude needs to research during discussion
- File scope tracking — cc-sessions' most complained-about feature
- TDD enforcement — superpowers handles this behaviorally
- Verification enforcement — superpowers handles this via `verification-before-completion`
- Git operations — no value in blocking commits

### Integration with Superpowers

The hooks and superpowers operate at different layers and don't conflict:

```
Layer 1: PreToolUse Hook (Deterministic)        Layer 2: Superpowers Skills (Behavioral)
┌──────────────────────────────────────┐        ┌──────────────────────────────────┐
│ .claude/hooks/workflow-gate.sh       │        │ /superpowers:brainstorm          │
│ .claude/hooks/bash-write-guard.sh    │        │ /superpowers:write-plan          │
│                                      │        │ /superpowers:execute-plan        │
│ Reads: .claude/state/phase.json      │        │ /superpowers:tdd                 │
│ Blocks: Write, Edit, MultiEdit       │        │ /superpowers:verify              │
│         + Bash write patterns        │        │ /superpowers:code-review         │
│ Until: phase = "implement"           │        │                                  │
└──────────────────────────────────────┘        └──────────────────────────────────┘
```

**Workflow example:**
1. User describes task → superpowers triggers `brainstorming` → hook blocks code edits
2. User says "write a plan" → superpowers triggers `writing-plans` → hook still blocks edits
3. User reviews plan, says `/approve` → hook flips state → edits unblocked
4. Superpowers triggers `executing-plans`, `TDD`, `verification` — hooks don't interfere
5. Task done → user says `/discuss` or state auto-resets → back to DISCUSS for next task

### State Management

**State file**: `.claude/state/phase.json`

```json
{
  "phase": "discuss",
  "updated": "2026-03-15T10:30:00Z"
}
```

**Design principle**: Hooks are stateless validators — they only read state. Phase transitions are driven by user commands (slash commands or CLAUDE.md trigger phrases), never by hooks. This separation prevents race conditions and makes the system predictable.

**Phase transitions**:
- `/approve` → sets phase to `"implement"`
- `/discuss` → sets phase to `"discuss"`
- New Claude Code session → defaults to `"discuss"` if no state file exists

### Known Limitations

1. **Bash bypass is ~95% covered, not 100%**. A sufficiently creative Bash command can slip through. Claude isn't adversarial — it uses Bash as a fallback when Edit is blocked. Catching common patterns is enough.
2. **Anthropic closed the Bash bypass issue as NOT_PLANNED** (GitHub #29709). This is a design limitation of Claude Code, not something we can fully solve.
3. **PreToolUse exit code 2 historically had bugs** with Write/Edit blocking (GitHub #13744). The hook should use JSON output with `permissionDecision: "deny"` instead of exit codes for reliability.

## Implementation

### Task 1: State management script

Create `.claude/hooks/workflow-state.sh` — a utility script that reads and writes `.claude/state/phase.json`. Used by hooks (read) and slash commands (write).

Functions:
- `get_phase` — reads current phase, defaults to "discuss"
- `set_phase <phase>` — writes phase with timestamp
- Creates `.claude/state/` directory if missing

### Task 2: Write/Edit gate hook

Create `.claude/hooks/workflow-gate.sh` — PreToolUse hook matching `Write|Edit|MultiEdit|NotebookEdit`.

Logic:
1. Source `workflow-state.sh` to get current phase
2. If phase is `"discuss"` → output JSON with `permissionDecision: "deny"` and a message telling Claude to discuss/plan first
3. If phase is `"implement"` → exit 0 (allow)
4. If no state file → exit 0 (no enforcement on first run)

### Task 3: Bash write guard hook

Create `.claude/hooks/bash-write-guard.sh` — PreToolUse hook matching `Bash`.

Logic:
1. Source `workflow-state.sh` to get current phase
2. If phase is `"implement"` → exit 0 (allow everything)
3. Read command from stdin JSON (`tool_input.command`)
4. Pattern-match for write operations (redirections, sed -i, tee, heredocs, python writes)
5. If write pattern found → output JSON with `permissionDecision: "deny"`
6. If no write pattern → exit 0 (allow read-only Bash)

### Task 4: Phase transition commands

Create two Claude Code slash commands:
- `.claude/commands/approve.md` — sets phase to "implement", prints confirmation
- `.claude/commands/discuss.md` — sets phase to "discuss", prints confirmation

These are simple markdown files that instruct Claude to run the state transition script.

### Task 5: Hook configuration

Update `.claude/settings.json` with PreToolUse hook entries for both hooks.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [{
          "type": "command",
          "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/workflow-gate.sh"
        }]
      },
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/bash-write-guard.sh"
        }]
      }
    ]
  }
}
```

### Task 6: Documentation

- Update `README.md` to document the enforcement hooks
- Update `docs/reference/architecture.md` with the two-layer enforcement diagram
- Update `docs/guides/getting-started.md` with setup instructions
- Add `docs/reference/hooks.md` with hook technical reference

### Task 7: Integration testing

Manual testing checklist:
- [ ] In DISCUSS phase: `Write` tool blocked with clear message
- [ ] In DISCUSS phase: `Edit` tool blocked with clear message
- [ ] In DISCUSS phase: `Bash(echo "test" > file.txt)` blocked
- [ ] In DISCUSS phase: `Bash(cat file.txt)` allowed
- [ ] In DISCUSS phase: `Read`, `Grep`, `Glob` allowed
- [ ] `/approve` transitions to IMPLEMENT phase
- [ ] In IMPLEMENT phase: all tools allowed
- [ ] `/discuss` transitions back to DISCUSS phase
- [ ] No state file → no enforcement (graceful first-run)
- [ ] Superpowers skills activate normally in both phases

## File Summary

```
claude-code-workflows/
├── .claude/
│   ├── hooks/
│   │   ├── workflow-state.sh       # State read/write utility
│   │   ├── workflow-gate.sh        # PreToolUse: blocks Write/Edit in DISCUSS
│   │   └── bash-write-guard.sh     # PreToolUse: blocks Bash writes in DISCUSS
│   ├── commands/
│   │   ├── approve.md              # /approve → flip to IMPLEMENT
│   │   └── discuss.md              # /discuss → flip to DISCUSS
│   └── state/
│       └── phase.json              # Current phase state (gitignored)
├── docs/
│   ├── reference/
│   │   └── hooks.md                # Hook technical reference
│   └── plans/
│       └── 2026-03-15-workflow-enforcement-hooks.md  # This plan
└── .gitignore                      # Add .claude/state/
```

## References

- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)
- [cc-sessions (GWUDCAP)](https://github.com/GWUDCAP/cc-sessions) — DAIC gating reference implementation
- [Sondera Cedar Hooks](https://github.com/sondera-ai/sondera-coding-agent-hooks) — Cedar policy approach
- [GitHub Issue #29709](https://github.com/anthropics/claude-code/issues/29709) — Bash bypass (closed NOT_PLANNED)
- [GitHub Issue #13744](https://github.com/anthropics/claude-code/issues/13744) — PreToolUse exit code 2 bug
- [Superpowers v4.3.0](https://blog.fsck.com/releases/2026/02/12/superpowers-v4-3-0/) — prompt-based enforcement limitations
- [Paddo.dev Hooks Guardrails](https://paddo.dev/blog/claude-code-hooks-guardrails/) — production hook patterns
