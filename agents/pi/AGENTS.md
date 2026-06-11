## Pi
- rtk is loaded as an extension; prefix shell commands with rtk.
- AFK or risky implementation work: load the sandcastle skill and use `sandcastle_run` (Docker sandbox + git worktree; changes return as branch commits).
- Parallel pi-subagents runs that edit files: set `worktree: true` so children can't clobber the checkout.
- `git commit/pull/push` stay in the main session; sandboxed sandcastle agents commit on their own branch.
