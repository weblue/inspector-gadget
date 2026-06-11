---
name: sandcastle
description: Run delegated sub-agent implementation tasks in a Docker sandbox + git worktree via the sandcastle_run tool. Only for hand-off/parallel work collected later; never for synchronous in-session work, quick edits, or read-only tasks.
---

# Sandcastle: sandboxed AFK runs

`sandcastle_run` launches a headless Pi agent (same auth and models as this session — auth.json is mounted read-only) inside a Docker container, working in an isolated git worktree. Changes come back as commits on a branch, never directly in the working tree.

## When
Sub-agent calls only — work delegated whole and collected later:
- Hand-off implementation: multi-file features, refactors, test-fix loops.
- Parallel runs on separate branches.

Never for synchronous workflows: anything being waited on in-session, quick edits, read-only questions, tasks needing interaction — do those directly on the host.

## Prereqs (once per repo)
- Docker running.
- Scaffold + image build, inside the repo: `npx @ai-hero/sandcastle init --agent pi && npx @ai-hero/sandcastle docker build-image` (images are per-repo: `sandcastle:<repo-dir>`; install.sh offers this for one repo).

## Call
- `task`: self-contained prompt — exact file paths, acceptance criteria, and an explicit "commit your work" instruction.
- `model`: defaults to this session's default model.
- `merge: false` (default) → commits land on a `sandcastle/*` branch for review: `rtk git log <branch>`, `rtk diff main...<branch>`, merge when satisfied. `merge: true` auto-merges to HEAD — only for low-risk tasks.
- `maxIterations` > 1 lets the agent iterate; it stops early via the completion signal.

## After a run
Report branch, commit count, and log path. Review the diff before merging. Prune stale `sandcastle/*` branches periodically.
