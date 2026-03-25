# Phase Transition Security Model

**Version:** 2.0 (post-BUG-3 redesign)
**Date:** 2026-03-25
**ADR:** [2026-03-25-phase-token-security-model.md](2026-03-25-phase-token-security-model.md)

## Overview

The Workflow Manager enforces phase transitions (OFF → DEFINE → DISCUSS → IMPLEMENT → REVIEW → COMPLETE → OFF) to ensure Claude follows the workflow discipline. The security model prevents Claude from self-authorizing phase transitions — only the user can change phases (via slash commands) or close the workflow.

## Trust Boundary

**The sole security boundary is the `UserPromptSubmit` hook.** This hook fires exclusively on actual user input — Claude cannot trigger it. This is a Claude Code platform guarantee, not an application-level control.

All other security measures are defense-in-depth: they raise the cost of exploitation but are not individually sufficient.

## Architecture

```
User types /implement
        │
        ▼
┌──────────────────────┐
│  UserPromptSubmit     │  ← Platform guarantee: user-only
│  (user-phase-token.sh)│
│                       │
│  Detects /implement   │
│  Generates nonce      │
│  Writes token file    │
│  {target, nonce}      │
└──────┬───────────────┘
       │ writes to
       ▼
┌──────────────────────┐
│  $CLAUDE_PLUGIN_DATA/ │
│  .phase-tokens/       │
│  <nonce> file         │
└──────┬───────────────┘
       │ consumed by
       ▼
┌──────────────────────┐
│  set_phase()          │  ← Application-level enforcement
│  (workflow-state.sh)  │
│                       │
│  Finds matching token │
│  Atomic mv-then-check │
│  Validates target     │
│  Transitions phase    │
└──────────────────────┘
```

## Security Layers

### Layer 1: UserPromptSubmit (Primary — Platform Guarantee)

- Only fires on user input. Claude cannot invoke it.
- Generates one-time token files with random nonces.
- Only matches explicit slash commands (`/define`, `/discuss`, `/implement`, `/review`, `/complete`, `/off`, `/autonomy <level>`).
- Does NOT match bare `set_phase` calls in natural conversation.

### Layer 2: Application-Level Token Verification (Primary — `set_phase()`)

- `set_phase()` and `set_autonomy_level()` require a valid token before writing state.
- Token is consumed atomically (mv-then-validate) to prevent TOCTOU races.
- No TTL — tokens are consumed immediately when the slash command executes.
- Forward-only auto-transition (autonomy=auto, higher ordinal, not OFF) is allowed without tokens.

### Layer 3: PreToolUse Write Guards (Defense-in-Depth — Unreliable)

- `bash-write-guard.sh` blocks writes to `.phase-tokens/` in **all active phases** (DEFINE, DISCUSS, IMPLEMENT, REVIEW, COMPLETE). The guard fires before the IMPLEMENT/REVIEW early-exit in the write guard, catching token forgery attempts even in permissive phases.
- **Known limitation:** PreToolUse blocking (both exit code 2 and `permissionDecision: "deny"`) is unreliable per documented Claude Code bugs. Even though the guard fires in all phases, it may not prevent the write. This layer raises the bar but is not a security boundary.

### Layer 4: Behavioral Anchoring (Soft — Not a Security Boundary)

- Phase command templates instruct Claude about phase rules.
- PostToolUse coaching reinforces workflow discipline.
- CLAUDE.md can state "only slash commands change phases."
- **This is NOT security.** Claude can and does ignore behavioral instructions under adversarial prompting.

## Threat Model

| Threat | Mitigation | Residual Risk |
|--------|-----------|---------------|
| Claude calls `set_phase()` directly | Layer 2: Token required, no token exists | None — `set_phase` rejects without token |
| Claude triggers UserPromptSubmit | Layer 1: Platform guarantee — impossible | None (unless Anthropic introduces a platform bug) |
| Claude forges token during IMPLEMENT | Layer 3: `.phase-tokens` guard fires (before IMPLEMENT early-exit), but PreToolUse blocking is unreliable | **Accepted risk** — requires adversarial intent, guard raises bar but may not block |
| Claude forges token during DEFINE/DISCUSS | Layer 3: Write guard blocks all non-whitelisted writes | Low — guard works in these phases |
| Claude reads token format from source | Open source — format is public knowledge | Accepted — security by obscurity is not security |
| Prompt injection instructs Claude to forge | Layers 3 + 4 raise the bar | **Accepted risk** — bounded blast radius (phase change only) |
| Claude modifies `workflow-state.sh` to remove checks | Layer 3: Write guard blocks script modification in restricted phases. In IMPLEMENT, source changes are committed and auditable. | Low — detectable via git diff |

## What This Model Does NOT Protect Against

1. **A motivated, adversarially-instructed Claude during IMPLEMENT/REVIEW.** If Claude is told to forge a token and call `set_phase()`, it can do so. The blast radius is limited to unauthorized phase transitions — not data loss, code execution, or credential theft.

2. **Claude Code platform bugs.** If `UserPromptSubmit` fires on non-user input, or if hooks are bypassed entirely, the model collapses. This would also break every other Claude Code plugin that relies on hooks.

3. **Direct file modification of `workflow.json`.** Claude can edit the state file via Bash during IMPLEMENT/REVIEW. The token system protects `set_phase()` calls, not raw file writes. The write guard blocks raw file writes in other phases.

## Comparison with cc-sessions

[GWUDCAP/cc-sessions](https://github.com/GWUDCAP/cc-sessions) uses the same security model:

| Aspect | ClaudeWorkflows | cc-sessions |
|--------|----------------|-------------|
| Trust boundary | UserPromptSubmit | UserPromptSubmit |
| Mode enforcement | Token files + `set_phase()` | JSON state file + PreToolUse |
| Anti-forgery | Application-level token check | PreToolUse blocks state file writes |
| Crypto tokens | None | None |
| Behavioral anchoring | PostToolUse coaching | Context injection + "shame ritual" |

Both projects accept the same residual risk: token/state forgery during implementation phases by an adversarially-instructed Claude. Both rely on the UserPromptSubmit platform guarantee as the primary security boundary.

## Future Improvements

- **HMAC signing:** If PreToolUse blocking becomes reliable (Anthropic fixes [#23284](https://github.com/anthropics/claude-code/issues/23284), [#26923](https://github.com/anthropics/claude-code/issues/26923)), HMAC-signed tokens could be added. The secret would live in `$CLAUDE_PLUGIN_DATA`, and PreToolUse would block Claude from reading it.
- **Read deny rules:** Claude Code's `permissions.deny` rules could block reads of the secret file, but this depends on deny rules being reliably enforced (which has its own bugs: [#6631](https://github.com/anthropics/claude-code/issues/6631)).
- **CLAUDE_ENV_FILE for all hooks:** If Anthropic extends CLAUDE_ENV_FILE to non-SessionStart hooks, the original HMAC design (secret in env, not file) becomes viable.
