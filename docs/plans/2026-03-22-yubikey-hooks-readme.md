# Design: YubiKey Tiered Touch, Hook Fixes, Review Gap, README Rewrite

**Date:** 2026-03-22
**Status:** Draft

## Problem

Four issues affecting usability and quality:

1. YubiKey requires physical touch for every git commit/push. This is bothersome for routine operations. Only destructive commands need touch. Unplugged YubiKey should block all git.
2. PostToolUse coaching hook throws errors on every tool call (TaskCreate, Read, Glob, etc.) because it fires on all tools and crashes on irrelevant ones.
3. Bash write guard blocks read-only commands that contain `2>/dev/null` because the redirect pattern `>[^&]` matches stderr-to-devnull.
4. README is too verbose (~296 lines), reads AI-generated, buries the signal.
5. Review pipeline doesn't check for negative/edge-case test coverage, which is how bugs 2 and 3 shipped.

## Task A: YubiKey Tiered Touch

### Requirements

| YubiKey state | Allowed operations | Touch? |
|---|---|---|
| Plugged in | All safe git commands (commit, push, pull, fetch, clone, tag, rebase, reset) | No |
| Plugged in | Destructive commands (push --force, push --delete, branch -D/-M, tag -d on remote) | Yes (software gate — confirmation prompt) |
| Unplugged | None | All git blocked |

### Threat model

Accidental destruction by the user or Claude Code. Not adversarial shell compromise. Software gate is sufficient.

Note: `reset --hard` and `rebase` are locally destructive but recoverable via reflog. The dangerous list covers only remote-irreversible operations (force push, remote deletion). Local-only destructive commands are intentionally in the safe tier.

### Implementation

#### New SSH key

Generate: `ssh-keygen -t ed25519-sk -O no-touch-required -O resident -C "yubikey-no-touch"`

This key signs automatically when the YubiKey is plugged in. No tap needed.

Manual steps (documented in README, not automated):
- Generate the key
- Register on GitHub as signing key + authentication key
- Update `~/.ssh/allowed_signers`
- Deregister old touch-required key from GitHub (keep on YubiKey as backup)

#### Rewrite `git-yubikey`

Current: shows a touch banner for commit/push/tag, then calls `/usr/bin/git`.

New behavior:

```
1. Probe YubiKey presence: ykman list --serials (fast, ~100ms)
   - Absent → print "YubiKey not detected — git operations require YubiKey" → exit 1

2. Classify command:
   - DANGEROUS: push --force, push -f, push --force-with-lease,
                push --delete, branch -D, branch -M, tag -d (remote)
   - SAFE: everything else

3. If DANGEROUS:
   - Print touch banner: "DESTRUCTIVE: <command>. Touch YubiKey to confirm."
   - Wait for touch (use the touch-required key for a signing challenge,
     or simpler: prompt user confirmation since gate is software-enforced)
   - Proceed or abort

4. exec /usr/bin/git "$@"
```

Design choice for dangerous-command confirmation: Since the gate is software-enforced (the no-touch key is configured globally), the simplest approach is a `read -p "Press Enter to confirm..."` prompt. This blocks automated/accidental execution while staying simple. The touch-required key is not needed in the flow — it remains as a backup on the YubiKey.

#### Update `git-ssh-auth.sh`

Change default key path from `id_ed25519_sk` to the new no-touch key. Keep `YUBIKEY_SSH_KEY` env var override.

#### Update `git config`

`user.signingkey` → new key's `.pub` path.

#### Update `CLAUDE.md.snippet`

Reflect new behavior: no touch for normal ops, confirmation prompt for destructive ops, blocked when unplugged.

### Trade-offs

- ~100ms latency per git command for presence check
- Dangerous-command gate is software, not hardware — sufficient for the threat model
- New key requires GitHub re-registration (one-time manual step)

## Task B: Hook Bug Fixes

### Bug 1: PostToolUse errors on irrelevant tools

**Root cause:** PostToolUse hook has no `matcher` in settings.json — fires on every tool. For tools the coaching system doesn't care about (Read, Glob, Grep, TaskCreate, TaskUpdate, Skill, etc.), it still runs `increment_coaching_counter` which writes to workflow.json on every call. With `set -euo pipefail`, any failure in the read-write cycle (race condition, malformed state, python3 error) kills the hook with a non-zero exit.

**Fix:** After Layer 1 check (phase entry message), add an early exit for tools that don't participate in Layer 2 or Layer 3. The relevant tool set is:

- Layer 2: `Agent`, `Write`, `Edit`, `MultiEdit`, `Bash`
- Layer 3: `Agent`, `Bash`, `Write`, `Edit`, `MultiEdit`, `AskUserQuestion`, `mcp.*save_observation`

All other tools → exit 0 immediately after Layer 1. No counter increment, no disk write.

Move the counter increment/reset to only fire for tools in the relevant set.

### Bug 2: Bash guard false positive on `2>/dev/null`

**Root cause:** Write pattern `>[^&]` matches `2>/dev/null` because `>` is followed by `/` (not `&`). Stderr redirects to /dev/null are read-safe.

**Fix:** Before applying the write pattern, strip safe redirect patterns from the command:

```bash
CLEAN_CMD=$(echo "$COMMAND" | sed -E 's/[0-9]*>&[0-9]+//g; s/[0-9]+>\/dev\/null//g')
```

This removes `2>/dev/null`, `2>&1`, `1>&2`, etc. Then apply `WRITE_PATTERN` against `CLEAN_CMD` instead of `COMMAND`. The original `COMMAND` is still used for write-target extraction.

### Tests

Add test cases:
- PostToolUse hook returns 0 for Read, Glob, TaskCreate, TaskUpdate tool types
- Bash guard allows: `ssh-keygen -l -f key.pub 2>/dev/null`, `git config --list 2>&1`, `some_cmd 2>/dev/null | grep pattern`
- Bash guard still blocks: `echo "test" > file.txt`, `cat data > output`, `2>/dev/null` alone doesn't whitelist a real write like `echo x > file 2>/dev/null`

## Task C: Review Pipeline — Negative Test Coverage Check

### Problem

The review pipeline's three agents (Code Quality, Security, Architecture) review code but don't evaluate whether the test suite covers unhappy paths, edge cases, and real-world usage patterns. This is how bugs B1 and B2 shipped — the tests verified positive cases but not negative ones.

### Fix

Two changes:

#### 1. Add directive to Code Quality review agent prompt

In `.claude/commands/review.md`, add to the Code Quality agent's instructions:

> "Check test coverage for negative cases. For every conditional branch, error path, or input validation in the changed code, verify that a test exercises the failure case. If tests only cover happy paths, flag it as a Warning. Specific patterns to check: shell scripts with pattern matching (are non-matching inputs tested?), regex-based detection (are edge cases and false positives tested?), hooks/middleware (are irrelevant/unexpected inputs tested?)."

#### 2. Add professional standard

In `docs/reference/professional-standards.md`, add to REVIEW Phase Standards:

> **Review test coverage for unhappy paths.** Happy-path tests prove the feature works when everything goes right. Unhappy-path tests prove it doesn't break when things go wrong. If the test suite only verifies positive cases, flag it. Every conditional branch implies at least one negative case that needs a test. "It works on my inputs" is not coverage.

### Trade-offs

- Review agents may produce more findings, increasing review cycle time
- The directive is heuristic — agents can't compute actual branch coverage, they check by reading test files
- False positives possible ("this edge case isn't tested" when it's actually unreachable)

## Task D: README Rewrite

### Target

Cut from ~296 lines to ~80-100 lines. Make it read like a human wrote it.

### Structure

1. **Title + badge + one-liner** (~3 lines)
2. **What's in the box** — 4 tools, one line each (~6 lines)
3. **Quick start** — install command + link (~8 lines)
4. **Workflow overview** — one short paragraph + compact phase table + commands list (~25 lines)
5. **Tools** — compact table with links (~15 lines)
6. **Documentation links** (~10 lines)
7. **Contributing + License** (~5 lines)

### What moves out

| Content | Current location | New location |
|---|---|---|
| Mermaid diagram (108 lines) | README | `docs/reference/architecture.md` (already exists) |
| `/review` pipeline details | README | Already in `review.md` command + hooks reference |
| `/complete` pipeline details | README | Already in `complete.md` command + hooks reference |
| CLAUDE.md integration instructions | README | Getting started guide |
| Security section | README | Already in CLAUDE.md template |
| Detailed install/uninstall | README | Getting started guide |

### Trade-offs

- Less self-contained — README points to docs instead of being docs
- Someone skimming GitHub sees less detail upfront — but the current wall of text isn't being read anyway
