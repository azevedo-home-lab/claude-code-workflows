# Step 5: Commit & Push

Stage all changed files relevant to the task and commit:

1. Run `git status` and `git diff --stat`
2. Stage the relevant files (prefer specific files over `git add -A`)
3. **Version verification:** Verify the version bump was done during IMPLEMENT.

Run `scripts/check-version-sync.sh` to validate both version files match.
Then verify the version is greater than the last release tag:
```bash
CURRENT=$(jq -r '.plugins[0].version // .version' .claude-plugin/marketplace.json)
LAST_TAG=$(git tag -l 'v*' --sort=-v:refname | head -1 | sed 's/^v//')
echo "Current: $CURRENT, Last tag: ${LAST_TAG:-none}"
```

If version bump was not done (version matches or is less than last tag), flag as validation failure:
> "Version bump missing — run the versioning step before committing."

Include version files in the commit staging if they were modified.

4. Draft a concise conventional commit message explaining why
5. Commit using conventional commit format. Use your current model name in the Co-Authored-By line:

       Co-Authored-By: <your model name> <noreply@anthropic.com>

If clean working tree: skip and note "Nothing to commit."

## Push to Remote

After committing, push to the remote:

1. Check if there are commits to push:
```bash
AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || git rev-list --count origin/$(git symbolic-ref --short HEAD)..HEAD 2>/dev/null || echo "unknown")
echo "Commits ahead of remote: $AHEAD"
```

2. If ahead > 0, ask: "Push to remote? (yes / no)"
   - At **all autonomy levels**: always ask before pushing. Push is never automatic.
   - If **yes**: warn about YubiKey, then push:
     ```
     ========== YUBIKEY: TOUCH NOW FOR GIT PUSH ==========
     ```
     ```bash
     git push origin HEAD
     ```
   - If **no**: note "Push deferred — run `git push` manually when ready."

3. If no upstream or unknown: skip push, note "No remote tracking branch — push skipped."

4. After push (or skip), mark informational milestone:
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "pushed" "true"
```
This is NOT an exit gate — just tracks whether push happened.

#### Step 5 Review Gate

After committing (or skipping), dispatch a **review agent** — read `plugin/agents/commit-reviewer.md`, then dispatch as `general-purpose`:

Context: "Review the most recent commit."

If REDO: fix (amend commit or create new commit) and re-dispatch. Max 3 iterations, then surface to user.
Present summary: "Step 5 review: [findings found / no issues]. Fixed: [what changed]. Verdict: PASS."
If step was skipped (nothing to commit): skip this gate.

Mark milestone (also mark if skipped — clean tree means committed is N/A):
```bash
.claude/hooks/workflow-cmd.sh set_completion_field "committed" "true"
```
