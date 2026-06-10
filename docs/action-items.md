# Agent Jacket action items

Project-specific follow-ups from `docs/token-efficiency.md`.

## Completed in this repo

- Renamed project references from `local-briefcase` to `agent-jacket`.
- Expanded `.gitignore` to keep common high-noise files out of agent search context.
- Removed Finder junk files and an unnecessary `.gitkeep`.
- Standardized remote session names and SSH alias defaults on `agent-jacket`.

## Next actions

### High priority

- [ ] Keep shared prompt files lean (`system-prompt.md`, `agents/*`) and replace `TODO` stubs with concise, durable instructions only.
- [ ] Audit active MCP/tool registrations per harness and disable anything unused.
- [ ] Set `MAX_MCP_OUTPUT_TOKENS` in agent environments to cap chatty tools.
- [ ] Set lower `MAX_THINKING_TOKENS` defaults for mechanical flows; keep larger budgets for planning/review.

### Repo structure

- [ ] Keep top-level folders purpose-specific: `agents/`, `extensions/`, `skills/`, `tools/`, `docs/`.
- [ ] Put experiments, scratch files, and generated artifacts under ignored directories like `tmp/` or `.tmp/`.
- [ ] Avoid storing machine-specific config in tracked files unless it is part of the product surface.

### Operational hygiene

- [ ] Prefer RTK-wrapped commands plus bounded output (`tail -n`) for noisy logs and test runs.
- [ ] Periodically remove Finder junk, backup files, and stale local scaffolding before they spread.
- [ ] Revisit `.gitignore` whenever new tooling adds caches, logs, or generated output.
