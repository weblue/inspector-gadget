# agent-jacket

Layered installer for LLM coding setups. Every layer optional — pick harnesses, bring your own models, stop at whatever depth you need. Token savings built in throughout.

```text
┌─ 5  remote access ──── server + clients over tailscale/ssh/tmux
├─ 4  workers & skills ─ subagent profiles, shared skills, sandboxed sub-agent runs (pi)
├─ 3  token savings ──── rtk wiring, prompt rules, output caps
├─ 2  models & auth ──── bring your own: subscriptions or API keys
└─ 1  harnesses ──────── any of: claude · codex · pi
```

## 1 — Harnesses

```bash
./install.sh                  # interactive
./install.sh claude pi        # any subset, or 'all'
./install.sh --force pi       # update existing install (re-seed, backups kept)
```

| | claude | codex | pi |
|---|---|---|---|
| Prompt (base + add-on) | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.pi/agent/AGENTS.md` |
| rtk wiring | hook + settings | rules file | extension |
| Shared skills | ✓ | ✓ | ✓ |
| Worker profiles | `~/.claude/agents/` | — | — |
| Extensions + pi-only skills | — | — | `~/.pi/agent/` |
| Secrets deny-list + output caps | `settings.json` | — | — |

## 2 — Models & auth

Nothing provider-pinned. Subscriptions (Claude Pro/Max, ChatGPT/Codex, `pi /login` OAuth) or API keys (installer offers a Pi key flow, warns before billing an API key a subscription would cover). Model choice surfaces everywhere: harness defaults, subagent `model:`/`effort:` frontmatter, Pi thinking levels, per-run `model` param.

## 3 — Token savings

[rtk](tools/rtk/index.md) installed everywhere (pinned + sha256-verified on linux), wired into each harness — CLI output compressed 60–90% before it hits context:

```text
$ rtk gain
  #  Command                Count  Saved   Avg%   Impact
 1.  rtk grep -n TODO           7    412  84.0%   ████████░░
```

Plus shared prompt rules (docs over code-reading, summaries over raw output, targeted edits) and caps: `MAX_MCP_OUTPUT_TOKENS`, effort routed by role.

## 4 — Workers & skills

Claude subagents (coder, reviewer, tester, architect, security) ~10 lines each, cost routing in frontmatter; main session orchestrates. Shared skills: `stop-slop`, `grill-me`.

Pi-only: the `sandcastle` skill gates `sandcastle_run` — headless Pi agent, same auth (`auth.json` mounted read-only), in a Docker container on an isolated git worktree; changes return as commits on a `sandcastle/*` branch. Sub-agent calls only; synchronous work runs directly on the host. Once per repo:

```bash
npx @ai-hero/sandcastle init && npx @ai-hero/sandcastle docker build-image
```

## 5 — Remote access

```text
laptop ──tailscale──▶ server ── tmux "agent-jacket" (pi, shell)
  └─ cmux workspaces            sshd (key-only, hardened)
```

```bash
./server.sh             # server: verify tailscale + ssh, start tmux session
./client-install.sh     # client: tailscale + cmux + ssh config + keys
./connect.sh            # client: open pi + shell workspaces in cmux
```

[cmux](https://github.com/manaflow-ai/cmux) = client-side macOS terminal, driven by `connect.sh`. Server needs only tmux — any SSH client works.

## Maintenance

```bash
./maintain.sh           # report: rtk savings, junk, prompt bloat, stale branches
./maintain.sh --prune   # also delete junk + stale backups
```

## Layout

```text
install.sh            layers 1–4 (--force to update)
server.sh             layer 5, server side
client-install.sh     layer 5, client side
connect.sh            layer 5, cmux workspaces
maintain.sh           hygiene (report / --prune)
system-prompt.md      shared base prompt
agents/               harness add-ons · pi-only skills · worker profiles
extensions/pi/        sandcastle, copy-all, usage
skills/               stop-slop, grill-me
tools/rtk/            rtk reference
docs/TODO.md          open + resolved items
```
