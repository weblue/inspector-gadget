---
name: sandcastle
description: Run AFK implementation tasks in a Docker sandbox + git worktree via the sandcastle_run tool. Use for hand-off, parallel, or risky implementation work that must not touch the host checkout; not for quick edits or read-only tasks.
---

# Sandcastle: sandboxed AFK runs

`sandcastle_run` launches a headless Pi agent (same auth and models as this session — auth.json is mounted read-only) inside a Docker container, working in an isolated git worktree. Changes come back as commits on a branch, never directly in the working tree.

## When
- Implementation tasks you'd hand off whole: multi-file features, refactors, test-fixing loops.
- Parallel work: multiple runs on different branches can't clobber each other or this checkout.
- Anything risky enough that host isolation matters.

Not for: quick single-file edits (do them directly), read-only questions, tasks needing interactive input.

## Prereqs (once per repo)
- Docker running.
- Scaffold + image build, inside the repo: `npx @ai-hero/sandcastle init && npx @ai-hero/sandcastle docker build-image` (images are per-repo: `sandcastle:<repo-dir>`).

## Call
- `task`: self-contained prompt — exact file paths, acceptance criteria, and an explicit "commit your work" instruction.
- `model`: defaults to this session's default model.
- `merge: false` (default) → commits land on a `sandcastle/*` branch for review: `rtk git log <branch>`, `rtk diff main...<branch>`, merge when satisfied. `merge: true` auto-merges to HEAD — only for low-risk tasks.
- `maxIterations` > 1 lets the agent iterate; it stops early via the completion signal.

## After a run
Report branch, commit count, and log path. Review the diff before merging. Prune stale `sandcastle/*` branches periodically.
