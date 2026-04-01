---
description: Run review pipeline on changed files
disable-model-invocation: true
---
!`"${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugin}"/scripts/user-set-phase.sh "review"`
