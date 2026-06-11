# agent-jacket

A layered installer for LLM coding setups. Every layer is optional — pick your harnesses, bring your own models, and stop at whatever depth you need. Token savings are built into every layer.

```text
┌─ 6  remote access ──── server + clients over tailscale/ssh/tmux (optional)
├─ 5  sandboxed AFK ──── docker + git-worktree agent runs (optional, pi)
├─ 4  workers & skills ─ subagent profiles, shared skills
├─ 3  token savings ──── rtk wiring, prompt rules, output caps
├─ 2  models & auth ──── bring your own: subscriptions or API keys
└─ 1  harnesses ──────── any of: claude · codex · pi
```

## Layer 1 — Harnesses: install any combination

```bash
./install.sh                  # interactive multi-select
./install.sh all              # claude + codex + pi
./install.sh claude pi        # any subset
./install.sh --force pi       # update an existing install (re-seed, backups kept, no prompts)
```

```text
=> Detected OS: mac
=> Selected agent(s): claude pi
✓  claude is already installed (2.5.1)
✓  pi is already installed
=> Seeding agent config...
✓  Seeded: ~/.claude/CLAUDE.md
✓  Seeded: ~/.claude/settings.json
```
*(abridged)*

Each selected harness gets its CLI installed and a prompt seeded from one source of truth (`system-prompt.md` + a small harness add-on, concatenated at install time). Re-running with `--force` is the update path: retired files are purged, overwrites leave timestamped `.backup.*` files.

| | claude | codex | pi |
|---|---|---|---|
| Prompt | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.pi/agent/AGENTS.md` |
| rtk wiring | hook + settings | rules in AGENTS.md | extension |
| Shared skills | ✓ | ✓ | ✓ |
| Worker profiles | `~/.claude/agents/` | — | — |
| Extensions + pi-only skills | — | — | `~/.pi/agent/` |
| Secrets deny-list + output caps | `settings.json` | — | — |

## Layer 2 — Models & auth: bring your own

Nothing is pinned to a provider. Each harness logs in with whatever you have:

- **Subscriptions** — Claude Pro/Max (`claude`), ChatGPT/Codex (`codex`), or either via `pi /login` OAuth.
- **API keys** — the installer offers a key flow for Pi (anthropic, openai, google, deepseek, mistral, groq, xai) and steers you away from billing an Anthropic API key when a subscription would cover it.

Model choice stays yours per layer above: harness defaults, per-subagent `model:`/`effort:` frontmatter, Pi subagent thinking levels, and an explicit `model` param on sandboxed runs.

## Layer 3 — Token savings: on by default, every layer

- **[rtk](tools/rtk/index.md)** is installed on all platforms (pinned + sha256-verified on Linux) and wired into every selected harness — CLI output is compressed 60–90% before it reaches the context window:

  ```text
  $ rtk gain
    #  Command                   Count  Saved    Avg%    Impact
   1.  rtk git status --short        3      1   11.1%   ██████████
   2.  rtk grep -n TODO              7    412   84.0%   ████████░░
  ```

- **Prompt rules** (shared across harnesses): docs over code-reading, conciseness over grammar, summaries over raw output, targeted edits over rewrites.
- **Caps & routing**: `MAX_MCP_OUTPUT_TOKENS` in Claude settings; reasoning effort routed by role — mechanical workers low/medium, review/architecture high.

## Layer 4 — Workers & skills

- **Worker profiles** → Claude Code subagents (coder, reviewer, tester, architect, security), each ~10 lines + shared constraints, with cost-routing baked into frontmatter (`model: sonnet`, `effort:`). The main session orchestrates.
- **Shared skills** → all harnesses: `stop-slop` (strip AI prose patterns), `grill-me` (interrogate a plan).
- **Pi-only skills** → `sandcastle` (gates layer 5 so it isn't considered on every request).

## Layer 5 — Sandboxed AFK runs (optional; Pi + Docker)

The `sandcastle` extension adds a `sandcastle_run` tool: a headless Pi agent — **same auth as your session**, `auth.json` mounted read-only — runs inside a Docker container on an isolated git worktree. Changes come back as commits on a `sandcastle/*` branch for review; your checkout is never touched. Skip this layer entirely by not installing Docker.

```bash
# once per repo
npx @ai-hero/sandcastle init && npx @ai-hero/sandcastle docker build-image
```

## Layer 6 — Remote access (optional; server + clients)

Run the agents on one machine, drive them from anywhere on your tailnet. Skip this layer by never running `server.sh` — everything above works standalone.

```text
laptop ──tailscale──▶ server (mac/linux)
  │                      ├─ tmux session "agent-jacket"
  └─ cmux workspaces ────┤    ├─ window: pi
     (pi / shell)        │    └─ window: shell
                         └─ sshd (key-only, hardened by install.sh)
```

[cmux](https://github.com/manaflow-ai/cmux) is the client-side terminal: a native macOS multiplexer built for agent workflows, driven by `connect.sh` to open one SSH'd workspace per concern. The server needs no GUI — sessions live in plain tmux, so any SSH client works.

```bash
# on the server
./server.sh                   # verify tailscale + ssh, start the shared tmux session

# on a client mac
./client-install.sh           # tailscale + cmux + ssh config + key exchange
./connect.sh                  # open pi + shell workspaces in cmux
```

```text
$ ./server.sh
✓  Tailscale connected — myserver.tail1234.ts.net (100.x.y.z)
✓  SSH (Remote Login) is enabled.
✓  Session 'agent-jacket' started (windows: pi, shell).
```

## Maintenance

```bash
./maintain.sh           # report: rtk savings, junk files, prompt bloat, stale branches
./maintain.sh --prune   # also delete junk + stale install backups
```

## Layout

```text
install.sh            layers 1–5: bootstrap / update (--force)
server.sh             layer 6: start remote-access services on this machine
client-install.sh     layer 6: prep a client to reach the server
connect.sh            layer 6: open server sessions as cmux workspaces
maintain.sh           recurring hygiene (report / --prune)
system-prompt.md      shared base prompt (concatenated into every harness)
agents/
  claude|codex|pi/    harness-specific prompt add-ons + settings
  pi/skills/          pi-only skills (sandcastle)
  profiles/           Claude worker subagents (coder, reviewer, tester, …)
extensions/pi/        Pi extensions (sandcastle, copy-all, usage)
skills/               shared skills (stop-slop, grill-me)
tools/rtk/            rtk wiring reference
docs/TODO.md          open items + resolved log
```
