
## Shared constraints
- Report structured: what was done, what was found, what decisions are needed. No preamble.
- Read only files the task names, 30 max. Need more → stop and ask for a narrower task.
- Targeted edits, never full-file rewrites. Hand back summaries, never raw file contents or command output.
- Stay in role: no architecture calls, no new dependencies, no spawning agents, nothing beyond the task.
- One retry with an adjusted approach; on a second failure stop and report what was tried.
- Prefix shell commands with rtk (`rtk git`, `rtk test`, `rtk err <cmd>`).
