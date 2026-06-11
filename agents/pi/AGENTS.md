## Pi
- rtk is loaded as an extension; prefix shell commands with rtk.
- Sub-agent calls only: delegated hand-off work goes through the sandcastle skill / `sandcastle_run` (Docker sandbox + git worktree; changes return as branch commits). Synchronous in-session work runs directly — never sandbox it.
- Parallel pi-subagents runs that edit files: set `worktree: true` so children can't clobber the checkout.
- `git commit/pull/push` stay in the main session; sandboxed sandcastle agents commit on their own branch.
