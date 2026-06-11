#!/usr/bin/env bash
# install.sh — bootstrap agent-jacket for one, several, or all harnesses
#
# Usage:
#   ./install.sh                  # interactive multi-select
#   ./install.sh claude           # one harness
#   ./install.sh claude codex     # several harnesses
#   ./install.sh all              # all three (claude, codex, pi)
#   ./install.sh --force claude   # update existing install: re-seed prompts/settings, backups kept, no prompts
#
# What this does:
#   1. Detect OS (mac / linux)
#   2. Select harnesses: any combination of claude | codex | pi, or 'all'
#   3. Install each selected agent CLI if not already present
#   4. For Pi: ask for auth method (default: subscription login)
#   5. Seed each selected agent's global config (shared system-prompt.md +
#      agent-specific file, concatenated at install time):
#        claude → ~/.claude/CLAUDE.md + ~/.claude/settings.json
#        codex  → ~/.codex/AGENTS.md
#        pi     → ~/.pi/agent/AGENTS.md
#   6. Install RTK and wire it into each selected agent via `rtk init`:
#        claude → rtk init --global             (hook + ~/.claude/settings.json)
#        codex  → rtk init --global --codex      (rules file ~/.codex/AGENTS.md)
#        pi     → rtk init --agent pi --global   (extension ~/.pi/agent/extensions/rtk.ts)
#   7. Copy skills and register them with each selected agent:
#        claude → ~/.claude/skills/ (auto-discovered)
#        codex  → ~/.codex/skills/ + [[skills.config]] in ~/.codex/config.toml
#        pi     → ~/.pi/agent/skills/ + "skills" array in ~/.pi/agent/settings.json
#   8. If Pi selected: copy extensions to ~/.pi/agent/extensions/ and wire settings.json
#   9. Install cmux (mac only — native terminal multiplexer for agent workflows)
#  10. Install server prereqs (tmux, Tailscale, SSH hardening) for remote access
#
# Context hygiene: Claude uses permissions.deny in ~/.claude/settings.json;
# all agents respect the project .gitignore. No global "ignore" file is written.
#
# Worker profiles (agents/profiles/*.md) install as Claude Code subagents in
# ~/.claude/agents/, each with the shared _base.md constraints appended.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
else
  BOLD="" DIM="" GREEN="" YELLOW="" CYAN="" RED="" RESET=""
fi

info()    { echo -e "${CYAN}${BOLD}=>${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}✓${RESET}  $*"; }
warn()    { echo -e "${YELLOW}${BOLD}!${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}✗${RESET}  $*" >&2; exit 1; }
ask()     { echo -e "${BOLD}?${RESET}  $*"; }
lc()      { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ─── os detection ─────────────────────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)  echo "linux" ;;
    *)      error "Unsupported OS: $(uname -s)" ;;
  esac
}

OS=$(detect_os)
FORCE=0
info "Detected OS: ${OS}"

# ─── dependency helpers ────────────────────────────────────────────────────────
require_cmd() {
  command -v "$1" &>/dev/null || error "'$1' is required but not installed. $2"
}

require_node() {
  require_cmd node "Install Node.js from https://nodejs.org or via your package manager."
  require_cmd npm  "npm should ship with Node.js."
}

# ─── agent selection ───────────────────────────────────────────────────────────
# Selection supports any combination of harnesses, plus 'all'.
# Result is collected into SELECTED_AGENTS (always non-empty after validation).
declare -a SELECTED_AGENTS=()

# True if the named agent is in the selection (safe for an empty array).
agent_selected() {
  local target="$1" a
  for a in ${SELECTED_AGENTS[@]+"${SELECTED_AGENTS[@]}"}; do
    [[ "$a" == "$target" ]] && return 0
  done
  return 1
}

# Adds an agent to the selection, de-duplicating.
add_agent() {
  agent_selected "$1" || SELECTED_AGENTS+=("$1")
}

# Parses selection tokens. 'all' is terminal (overrides everything else).
parse_tokens() {
  local token
  for token in "$@"; do
    token="$(lc "$token")"
    case "$token" in
      "")       : ;;
      a|all)    SELECTED_AGENTS=(claude codex pi); return 0 ;;
      1|claude) add_agent claude ;;
      2|codex)  add_agent codex  ;;
      3|pi)     add_agent pi     ;;
      *) error "Unknown selection: '$token'. Use claude, codex, pi, or all." ;;
    esac
  done
}

if [[ $# -gt 0 ]]; then
  RAW_SELECTION=""
  for _arg in "$@"; do
    if [[ "$_arg" == "--force" ]]; then
      FORCE=1
    else
      RAW_SELECTION="${RAW_SELECTION:+$RAW_SELECTION }$_arg"
    fi
  done
else
  echo ""
  ask "Which agent harness(es) would you like to install? (pick any number)"
  echo "   ${BOLD}1)${RESET} claude  — Anthropic Claude Code"
  echo "   ${BOLD}2)${RESET} codex   — OpenAI Codex CLI"
  echo "   ${BOLD}3)${RESET} pi      — Pi (pi.dev)"
  echo "   ${BOLD}a)${RESET} all     — install all three"
  echo ""
  read -rp "   Enter choice(s) [e.g. '1 3', 'claude pi', 'all']: " RAW_SELECTION
fi

# Normalise commas to spaces, then word-split into tokens.
RAW_SELECTION="${RAW_SELECTION//,/ }"
read -ra SELECTION_TOKENS <<< "$RAW_SELECTION"
parse_tokens ${SELECTION_TOKENS[@]+"${SELECTION_TOKENS[@]}"}

if [[ ${#SELECTED_AGENTS[@]} -eq 0 ]]; then
  error "No agents selected. Pass an agent name or 'all'."
fi

info "Selected agent(s): ${BOLD}${SELECTED_AGENTS[*]}${RESET}"

# ─── install agent cli ─────────────────────────────────────────────────────────
install_claude() {
  if command -v claude &>/dev/null; then
    success "claude is already installed ($(claude --version 2>/dev/null || echo 'version unknown'))"
    return
  fi
  info "Installing Claude Code..."
  require_node
  npm install -g @anthropic-ai/claude-code
  success "Claude Code installed."
  warn "Run 'claude' to log in via your Anthropic subscription."
}

install_codex() {
  if command -v codex &>/dev/null; then
    success "codex is already installed ($(codex --version 2>/dev/null || echo 'version unknown'))"
    return
  fi
  info "Installing Codex CLI..."
  require_node
  npm install -g @openai/codex
  success "Codex CLI installed."
  warn "Run 'codex' to log in via your OpenAI subscription."
}

install_pi() {
  if command -v pi &>/dev/null; then
    success "pi is already installed"
    return
  fi
  info "Installing Pi..."
  require_node
  npm install -g --ignore-scripts @earendil-works/pi-coding-agent
  success "Pi installed."
}

install_agent_cli() {
  case "$1" in
    claude) install_claude ;;
    codex)  install_codex  ;;
    pi)     install_pi     ;;
  esac
}

for AGENT in "${SELECTED_AGENTS[@]}"; do
  install_agent_cli "$AGENT"
done

# ─── pi auth setup ─────────────────────────────────────────────────────────────
# Pi resolves credentials in this order (highest priority first):
#   1. --api-key flag   2. ~/.pi/agent/auth.json   3. env vars   4. models.json
# We write to auth.json — the same store `pi /login`'s API-key path uses. It is
# 0600, outranks environment variables, and persists across shells (unlike a
# loose .env, which Pi does not auto-source).
#
# Auth policy:
#   - Recommended: subscription OAuth via `pi /login` (token auto-refresh, no key
#     on disk). For Anthropic this draws on your Claude Pro/Max subscription.
#   - A direct API key is offered, but for Anthropic we steer away from it: a
#     third-party API key bills against your Anthropic *API* limits, whereas Claude
#     Code — or Pi's subscription login — uses your Claude subscription instead.

# Writes an API-key entry into ~/.pi/agent/auth.json (0600), preserving existing
# entries. Schema matches what `pi /login`'s API-key path produces:
#   { "<provider>": { "type": "api_key", "key": "<key>" } }
write_pi_auth() {
  local provider="$1" key="$2"
  local auth="$HOME/.pi/agent/auth.json"
  mkdir -p "$HOME/.pi/agent"
  python3 - "$auth" "$provider" "$key" <<'PY'
import json, os, sys
path, provider, key = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f) or {}
    except Exception:
        data = {}
data[provider] = {"type": "api_key", "key": key}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
PY
  chmod 600 "$auth" 2>/dev/null || true
  success "Wrote Pi API key for '$provider' to ~/.pi/agent/auth.json (0600)."
}

if agent_selected pi; then
  echo ""
  info "Pi authentication"
  echo "  ${DIM}Recommended: subscription login via 'pi /login' (auto-refresh, no key on disk).${RESET}"
  read -rp "$(echo -e "${BOLD}?${RESET}  Set a direct API key instead? [y/N]: ")" PI_USE_APIKEY
  PI_USE_APIKEY="${PI_USE_APIKEY:-n}"

  if [[ "$(lc "$PI_USE_APIKEY")" == "y" ]]; then
    read -rp "   Provider (anthropic | openai | google | deepseek | mistral | groq | xai): " PI_PROVIDER
    PI_PROVIDER="$(echo "$PI_PROVIDER" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

    # Steer Anthropic users toward a subscription rather than a billable API key.
    if [[ "$PI_PROVIDER" == "anthropic" || "$PI_PROVIDER" == "claude" ]]; then
      warn "An Anthropic API key bills against your Anthropic *API* usage limits."
      warn "To use your Claude Pro/Max subscription instead, use Claude Code, or run"
      warn "'pi /login' and choose the Claude subscription (OAuth) option."
      read -rp "   Use a billable Anthropic API key anyway? [y/N]: " PI_ANTHROPIC_CONFIRM
      if [[ "$(lc "$PI_ANTHROPIC_CONFIRM")" != "y" ]]; then
        warn "Skipping API key. Run 'pi /login' after install for subscription auth."
        PI_PROVIDER=""
      fi
    fi

    if [[ -n "$PI_PROVIDER" ]]; then
      read -rsp "   API key (input hidden): " PI_API_KEY
      echo ""
      if [[ -z "$PI_API_KEY" ]]; then
        warn "No key entered — skipping. Run 'pi /login' to authenticate later."
      else
        write_pi_auth "$PI_PROVIDER" "$PI_API_KEY"
      fi
    fi
  else
    info "Run 'pi /login' after install to authenticate (subscription OAuth or API key)."
  fi
fi

# ─── seed config file ─────────────────────────────────────────────────────────
# Seeds the agent's global config from this repo's agents/<agent>/ directory.
# If the target file already exists, prompts before overwriting.

seed_file() {
  local src="$1"
  local dest="$2"

  if [[ ! -f "$src" ]]; then
    warn "Source not found, skipping: $src"
    return
  fi

  if [[ -f "$dest" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      cp "$dest" "${dest}.backup.$(date +%Y%m%d%H%M%S)"
      info "Backup saved: ${dest}.backup.*"
    else
      warn "File already exists: $dest"
      read -rp "   Overwrite? [y/N]: " OVERWRITE
      [[ "$(lc "$OVERWRITE")" == "y" ]] || { info "Skipped $dest"; return; }
      cp "$dest" "${dest}.backup.$(date +%Y%m%d%H%M%S)"
      info "Backup saved: ${dest}.backup.*"
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  success "Seeded: $dest"
}

# Builds the installed prompt by concatenating the shared base prompt
# (system-prompt.md) with the agent-specific file, then seeds the result.
# Keeps one source of truth in the repo while installed files stay self-contained.
seed_prompt() {
  local agent_src="$1" dest="$2" tmp
  tmp="$(mktemp)"
  if [[ -f "$agent_src" ]]; then
    { cat "$REPO_DIR/system-prompt.md"; echo ""; cat "$agent_src"; } > "$tmp"
  else
    warn "Agent prompt not found ($agent_src) — seeding base prompt only."
    cat "$REPO_DIR/system-prompt.md" > "$tmp"
  fi
  seed_file "$tmp" "$dest"
  rm -f "$tmp"
}

seed_agent_config() {
  case "$1" in
    claude)
      # Claude Code loads global memory from ~/.claude/CLAUDE.md (not ~/CLAUDE.md)
      # and global settings from ~/.claude/settings.json.
      mkdir -p "$HOME/.claude"
      seed_prompt "$REPO_DIR/agents/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
      seed_file "$REPO_DIR/agents/claude/settings.json" "$HOME/.claude/settings.json"
      ;;
    codex)
      # Codex reads AGENTS.md from CODEX_HOME (~/.codex), not ~/AGENTS.md.
      mkdir -p "$HOME/.codex"
      seed_prompt "$REPO_DIR/agents/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
      ;;
    pi)
      # Pi loads AGENTS.md from ~/.pi/agent (plus parents and cwd).
      mkdir -p "$HOME/.pi/agent"
      seed_prompt "$REPO_DIR/agents/pi/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
      ;;
  esac
}

echo ""
info "Seeding agent config..."
for AGENT in "${SELECTED_AGENTS[@]}"; do
  seed_agent_config "$AGENT"
done

# ─── context hygiene ──────────────────────────────────────────────────────────
# None of these agents use a dedicated global "ignore" file:
#   - Claude Code has no .claudeignore. Sensitive-path blocking is done via
#     permissions.deny in ~/.claude/settings.json (seeded above from
#     agents/claude/settings.json).
#   - Codex and Pi have no global ignore file.
#   - All three respect the project's .gitignore for file discovery.

echo ""
info "Context hygiene: Claude uses permissions.deny in ~/.claude/settings.json; all agents respect project .gitignore."

# ─── install rtk ──────────────────────────────────────────────────────────────
# RTK is a CLI proxy that reduces LLM token consumption by 60–90% on common
# dev commands (git, docker, npm, cargo, etc.) by compressing output before
# it reaches the agent's context window.
#
# After installing the binary we wire RTK into each selected agent with the
# canonical per-agent `rtk init` command (verified against the RTK docs):
#   claude → rtk init --global            installs a hook + patches ~/.claude/settings.json
#   codex  → rtk init --global --codex     adds a rules file to ~/.codex/AGENTS.md
#   pi     → rtk init --agent pi --global  writes the extension ~/.pi/agent/extensions/rtk.ts
#                                          (Pi requires the long --global flag, not -g)
# Each `rtk init` mutates that agent's config; review before committing.

# Runs the correct global `rtk init` for one agent. Returns rtk's exit status.
rtk_init_agent() {
  case "$1" in
    claude) rtk init --global ;;
    codex)  rtk init --global --codex ;;
    pi)     rtk init --agent pi --global ;;
  esac
}

echo ""
info "Installing RTK..."

if command -v rtk &>/dev/null; then
  success "rtk is already installed ($(rtk --version 2>/dev/null || echo 'version unknown'))"
else
  if [[ "$OS" == "mac" ]] && command -v brew &>/dev/null; then
    # Use the official tap to avoid the Homebrew name collision with the
    # unrelated 'rtk' (Rust Type Kit) formula.
    brew install rtk-ai/tap/rtk
  else
    # ── Pinned RTK Linux install ───────────────────────────────────────────────
    # Bump instructions: update RTK_VERSION and the two SHA256 values below.
    # Fetch new hashes from the release's checksums.txt at:
    #   https://github.com/rtk-ai/rtk/releases/download/v<NEW_VERSION>/checksums.txt
    RTK_VERSION="0.42.3"
    RTK_X86_SHA256="5df764a633709cb85d248258d085d24ec95faa8bca0e6835a93cd57cadc4eb9e"
    RTK_ARM64_SHA256="2b7fa09d06f8dbf334c55482fad2e7ce4a1f8564bc9ed1f65d9f5992db8e5527"

    RTK_ARCH="$(uname -m)"
    case "$RTK_ARCH" in
      x86_64)          RTK_ASSET="rtk-x86_64-unknown-linux-musl.tar.gz";   RTK_SHA256="$RTK_X86_SHA256" ;;
      aarch64|arm64)   RTK_ASSET="rtk-aarch64-unknown-linux-gnu.tar.gz";   RTK_SHA256="$RTK_ARM64_SHA256" ;;
      *) error "RTK: unsupported architecture '$RTK_ARCH'. Only x86_64 and aarch64/arm64 are supported." ;;
    esac

    RTK_URL="https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/${RTK_ASSET}"
    RTK_TMPDIR="$(mktemp -d)"
    info "Downloading RTK ${RTK_VERSION} (${RTK_ARCH})..."
    curl -fsSL "$RTK_URL" -o "${RTK_TMPDIR}/${RTK_ASSET}"

    # Verify checksum — hard error on mismatch, never fall back to curl|sh.
    if command -v sha256sum &>/dev/null; then
      echo "${RTK_SHA256}  ${RTK_TMPDIR}/${RTK_ASSET}" | sha256sum -c --status \
        || error "RTK checksum mismatch — aborting. Do NOT install from an unverified archive."
    elif command -v shasum &>/dev/null; then
      echo "${RTK_SHA256}  ${RTK_TMPDIR}/${RTK_ASSET}" | shasum -a 256 -c --status \
        || error "RTK checksum mismatch — aborting. Do NOT install from an unverified archive."
    else
      error "No sha256sum or shasum found — cannot verify RTK archive. Install one and retry."
    fi
    success "RTK archive checksum verified."

    tar -xzf "${RTK_TMPDIR}/${RTK_ASSET}" -C "$RTK_TMPDIR"
    RTK_BIN="$(find "$RTK_TMPDIR" -type f -name rtk | head -1)"
    [[ -n "$RTK_BIN" ]] || error "RTK binary not found in extracted archive."

    if sudo install -m 755 "$RTK_BIN" /usr/local/bin/rtk 2>/dev/null; then
      success "RTK installed to /usr/local/bin/rtk."
    else
      mkdir -p "$HOME/.local/bin"
      install -m 755 "$RTK_BIN" "$HOME/.local/bin/rtk"
      success "RTK installed to ~/.local/bin/rtk."
      warn "~/.local/bin is not on PATH — add it: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
    rm -rf "$RTK_TMPDIR"
  fi
  success "RTK installed."
fi

if ! command -v rtk &>/dev/null; then
  warn "rtk not on PATH after install — skipping agent wiring. Wire it later with 'rtk init'."
else
  info "Wiring RTK into selected agent(s)..."
  for AGENT in "${SELECTED_AGENTS[@]}"; do
    if rtk_init_agent "$AGENT"; then
      success "RTK wired into ${AGENT}."
    else
      warn "rtk init for ${AGENT} returned non-zero — re-run it manually and check the output."
    fi
  done
  warn "RTK init modified agent config (settings.json / AGENTS.md / extensions). Review before committing."
fi

# ─── copy skills ──────────────────────────────────────────────────────────────
# Copies all skills (full directories, including references/) into the agent's
# skill directory, then registers them where the agent needs explicit config.
#
# Destinations & registration:
#   claude: ~/.claude/skills/<skill>/   — auto-discovered by Claude Code.
#   codex:  ~/.codex/skills/<skill>/    — registered via [[skills.config]] in
#                                         ~/.codex/config.toml (no auto-discovery).
#   pi:     ~/.pi/agent/skills/<skill>/ — loaded via the "skills" array in
#                                         ~/.pi/agent/settings.json (wired below).
#
# Pi additionally gets harness-exclusive skills from agents/pi/skills/.

copy_skills() {
  local skills_dest="$1"
  local skills_src="${2:-$REPO_DIR/skills}"

  if [[ ! -d "$skills_src" ]]; then
    warn "Skills source not found, skipping: $skills_src"
    return
  fi

  local copied=0
  for skill_dir in "$skills_src"/*/; do
    [[ -f "${skill_dir}SKILL.md" ]] || continue
    local skill_name dest
    skill_name="$(basename "$skill_dir")"
    dest="$skills_dest/$skill_name"
    mkdir -p "$dest"
    cp -r "$skill_dir"* "$dest/"
    success "Skill → $dest"
    (( copied++ )) || true
  done

  [[ $copied -gt 0 ]] || warn "No skills found in skills/ — nothing copied."
}

# Codex does not auto-discover ~/.codex/skills/ — each skill folder needs a
# [[skills.config]] entry in ~/.codex/config.toml. Entries are added only once.
register_codex_skills() {
  local skills_dir="$1"
  local config="$HOME/.codex/config.toml"
  mkdir -p "$HOME/.codex"
  touch "$config"

  for skill_dir in "$skills_dir"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local path="${skill_dir%/}"
    if grep -qF "path = \"$path\"" "$config" 2>/dev/null; then
      info "Codex skill already registered: $(basename "$path")"
      continue
    fi
    {
      echo ""
      echo "[[skills.config]]"
      echo "path = \"$path\""
      echo "enabled = true"
    } >> "$config"
    success "Registered Codex skill: $(basename "$path")"
  done
}

install_agent_skills() {
  case "$1" in
    claude)
      mkdir -p "$HOME/.claude/skills"
      copy_skills "$HOME/.claude/skills"
      ;;
    codex)
      mkdir -p "$HOME/.codex/skills"
      copy_skills "$HOME/.codex/skills"
      register_codex_skills "$HOME/.codex/skills"
      ;;
    pi)
      mkdir -p "$HOME/.pi/agent/skills"
      copy_skills "$HOME/.pi/agent/skills"
      copy_skills "$HOME/.pi/agent/skills" "$REPO_DIR/agents/pi/skills"
      # Pi settings.json (skills + extensions arrays) is wired in the Pi section below.
      ;;
  esac
}

echo ""
info "Copying skills..."
for AGENT in "${SELECTED_AGENTS[@]}"; do
  install_agent_skills "$AGENT"
done

# ─── pi extensions & settings ─────────────────────────────────────────────────
# Copies Pi extensions to ~/.pi/agent/extensions/ and wires ~/.pi/agent/settings.json
# so Pi loads both the skills and extensions directories. Pi does NOT auto-load
# loose files placed in ~/.pi/agent — paths must be declared in settings.json.

# Ensures the "skills" and "extensions" directories are listed in Pi's settings.json.
# Merges into any existing settings without clobbering other keys (paths resolve
# relative to ~/.pi/agent).
configure_pi_settings() {
  local settings="$HOME/.pi/agent/settings.json"
  local pi_result
  pi_result="$(python3 - "$settings" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f) or {}
    except Exception:
        data = {}
for key in ("skills", "extensions"):
    arr = data.get(key)
    if not isinstance(arr, list):
        arr = []
    if key not in arr:
        arr.append(key)
    data[key] = arr
# Wire subagent thinking-effort defaults only when not already configured.
# These route pi-subagents builtin agents' reasoning effort (cost control);
# full override docs are in the pi-subagents README.
added_subagents = False
if "subagents" not in data:
    data["subagents"] = {
        "agentOverrides": {
            "scout":           {"thinking": "low"},
            "context-builder": {"thinking": "low"},
            "worker":          {"thinking": "medium"},
            "planner":         {"thinking": "high"},
            "reviewer":        {"thinking": "high"},
            "oracle":          {"thinking": "high"},
        }
    }
    added_subagents = True
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("added" if added_subagents else "skipped")
PY
)"
  if [[ "$pi_result" == "added" ]]; then
    success "Pi settings.json wired (skills, extensions, subagents thinking defaults added)."
  else
    success "Pi settings.json wired (skills, extensions; existing subagents config preserved)."
  fi
}

if agent_selected pi; then
  echo ""
  info "Installing Pi extensions..."

  ext_src="$REPO_DIR/extensions/pi"
  ext_dest="$HOME/.pi/agent/extensions"

  if [[ ! -d "$ext_src" ]]; then
    warn "extensions/pi/ not found, skipping."
  else
    mkdir -p "$ext_dest"
    # Retired extensions — drop stale copies on update:
    #   bash-guard       → replaced by sandcastle sandboxing
    #   firecrawl-search → removed; web access comes from the pi-web-access package
    rm -f "$ext_dest/bash-guard.ts" "$ext_dest/firecrawl-search.ts"
    for ext_file in "$ext_src"/*.ts; do
      [[ -f "$ext_file" ]] || continue
      cp "$ext_file" "$ext_dest/"
      success "Extension → $ext_dest/$(basename "$ext_file")"
    done
    if [[ -f "$ext_src/package.json" ]]; then
      cp "$ext_src/package.json" "$ext_dest/package.json"
      [[ -f "$ext_src/package-lock.json" ]] && cp "$ext_src/package-lock.json" "$ext_dest/package-lock.json"
      info "Installing Pi extension dependencies..."
      npm install --prefix "$ext_dest" --silent
      success "Extension dependencies installed."
    fi
  fi

  configure_pi_settings

  # The sandcastle extension runs AFK agents in Docker sandboxes. It needs a
  # running Docker daemon and a one-time image build.
  if command -v docker &>/dev/null; then
    success "Docker found — sandcastle sandboxed runs available."
    info "Per-repo setup before first sandcastle_run: npx @ai-hero/sandcastle init && npx @ai-hero/sandcastle docker build-image"
  else
    warn "Docker not found — the sandcastle skill (sandboxed AFK runs) won't work until Docker is installed."
  fi
fi

# ─── install cmux ─────────────────────────────────────────────────────────────
# cmux is a native macOS terminal multiplexer built for AI agent workflows.
# GPU-accelerated (libghostty), vertical tabs, split panes, embedded browser.
# macOS only — skipped on Linux.

echo ""
if [[ "$OS" == "mac" ]]; then
  info "Installing cmux..."
  if [[ -d "/Applications/cmux.app" ]]; then
    success "cmux is already installed."
  elif command -v brew &>/dev/null; then
    brew tap manaflow-ai/cmux 2>/dev/null || true
    brew install --cask cmux
    success "cmux installed."
  else
    warn "Homebrew not found. Download cmux manually:"
    warn "  https://github.com/manaflow-ai/cmux/releases/latest/download/cmux-macos.dmg"
  fi
else
  info "cmux is macOS only — skipping on Linux."
fi

# ─── worker profiles ──────────────────────────────────────────────────────────
# Worker profiles (agents/profiles/*.md) install as Claude Code subagents in
# ~/.claude/agents/. Each installed profile = role file + _base.md appended, so
# subagents are self-contained. Codex and Pi have no subagent file equivalent;
# their main prompts cover the same ground.

install_claude_profiles() {
  local src="$REPO_DIR/agents/profiles"
  local dest="$HOME/.claude/agents"
  [[ -d "$src" ]] || { warn "agents/profiles/ not found, skipping."; return; }
  mkdir -p "$dest"
  # Retired profiles — orchestrator removed (subagents can't spawn subagents;
  # the main session orchestrates, guided by CLAUDE.md).
  rm -f "$dest/orchestrator.md"
  local f name
  for f in "$src"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    [[ "$name" == _* ]] && continue
    cat "$f" "$src/_base.md" > "$dest/$name"
    success "Profile → $dest/$name"
  done
}

if agent_selected claude; then
  echo ""
  info "Installing worker profiles..."
  install_claude_profiles
fi

# ─── server environment prereqs ───────────────────────────────────────────────
# Installs tools required to serve remote terminal access to this machine.
# Remote access flow: Tailscale (network) → SSH (transport) → tmux (session).
#
# Note on auth layers:
#   - Tailscale: uses your Tailscale account (Google/GitHub/email) to join the
#     tailnet. Run 'tailscale up' after install to authenticate.
#   - SSH over Tailscale: uses ~/.ssh/id_ed25519 or ~/.ssh/id_rsa (key auth;
#     password auth disabled).
#
# boss-man is not started here. Run ~/projects/boss-man-dashboard/start.sh
# separately, then configure your homelab nginx to proxy to this machine's port.
# Run ./server.sh to start Tailscale + the shared tmux session for remote access.

echo ""
info "Installing server environment prereqs..."

# tmux — shared terminal sessions for remote clients
if command -v tmux &>/dev/null; then
  success "tmux is already installed ($(tmux -V))"
elif [[ "$OS" == "mac" ]] && command -v brew &>/dev/null; then
  brew install tmux
  success "tmux installed."
elif [[ "$OS" == "linux" ]]; then
  if sudo apt-get install -y tmux 2>/dev/null || sudo yum install -y tmux 2>/dev/null; then
    success "tmux installed."
  else
    warn "Could not auto-install tmux. Install it via your package manager."
  fi
else
  warn "Could not install tmux — install it manually."
fi

# Tailscale — zero-config mesh VPN for secure external access
if command -v tailscale &>/dev/null; then
  success "Tailscale is already installed."
elif [[ "$OS" == "mac" ]] && command -v brew &>/dev/null; then
  brew install --cask tailscale
  success "Tailscale installed. Open the Tailscale app and sign in to join your tailnet."
elif [[ "$OS" == "linux" ]]; then
  # ── Pinned Tailscale Linux install ────────────────────────────────────────
  # Bump instructions: update TS_VERSION and the two SHA256 values below.
  # Fetch a new hash by appending .sha256 to the tgz URL, e.g.:
  #   curl -fsSL https://pkgs.tailscale.com/stable/tailscale_<VER>_amd64.tgz.sha256
  TS_VERSION="1.98.4"
  TS_AMD64_SHA256="e6c08a8ee7e63e69aaf1b62ecd12672b3883fbcd2a176bf6cfa42a15fdce0b6b"
  TS_ARM64_SHA256="3cb068eb1368b6bb218d0ef0aa0a7a679a7156b7c979e2279cc2c2321b5f05c7"

  if command -v systemctl &>/dev/null; then
    TS_ARCH="$(uname -m)"
    case "$TS_ARCH" in
      x86_64)         TS_PKG_ARCH="amd64"; TS_SHA256="$TS_AMD64_SHA256" ;;
      aarch64|arm64)  TS_PKG_ARCH="arm64"; TS_SHA256="$TS_ARM64_SHA256" ;;
      *) error "Tailscale: unsupported architecture '$TS_ARCH'. Only x86_64 and aarch64/arm64 are supported." ;;
    esac

    TS_ASSET="tailscale_${TS_VERSION}_${TS_PKG_ARCH}.tgz"
    TS_URL="https://pkgs.tailscale.com/stable/${TS_ASSET}"
    TS_TMPDIR="$(mktemp -d)"
    info "Downloading Tailscale ${TS_VERSION} (${TS_PKG_ARCH})..."
    curl -fsSL "$TS_URL" -o "${TS_TMPDIR}/${TS_ASSET}"

    # Verify checksum — hard error on mismatch.
    if command -v sha256sum &>/dev/null; then
      echo "${TS_SHA256}  ${TS_TMPDIR}/${TS_ASSET}" | sha256sum -c --status \
        || error "Tailscale checksum mismatch — aborting. Do NOT install from an unverified archive."
    elif command -v shasum &>/dev/null; then
      echo "${TS_SHA256}  ${TS_TMPDIR}/${TS_ASSET}" | shasum -a 256 -c --status \
        || error "Tailscale checksum mismatch — aborting. Do NOT install from an unverified archive."
    else
      error "No sha256sum or shasum found — cannot verify Tailscale archive. Install one and retry."
    fi
    success "Tailscale archive checksum verified."

    tar -xzf "${TS_TMPDIR}/${TS_ASSET}" -C "$TS_TMPDIR"
    TS_EXTRACTED="${TS_TMPDIR}/tailscale_${TS_VERSION}_${TS_PKG_ARCH}"

    sudo install -m 755 "${TS_EXTRACTED}/tailscaled" /usr/sbin/tailscaled
    sudo install -m 755 "${TS_EXTRACTED}/tailscale"  /usr/bin/tailscale
    sudo install -m 644 "${TS_EXTRACTED}/systemd/tailscaled.service" /etc/systemd/system/tailscaled.service
    # Don't clobber an existing defaults file — it may contain user customisations.
    if [[ ! -f /etc/default/tailscaled ]]; then
      sudo install -m 644 "${TS_EXTRACTED}/systemd/tailscaled.defaults" /etc/default/tailscaled
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable --now tailscaled
    rm -rf "$TS_TMPDIR"
    success "Tailscale installed. Run 'sudo tailscale up' to join your tailnet."
  else
    # No systemd — fall back to the official script (unpinned).
    warn "systemctl not found — falling back to the official Tailscale install script (unpinned, unverified)."
    curl -fsSL https://tailscale.com/install.sh | sh
    success "Tailscale installed. Run 'sudo tailscale up' to join your tailnet."
  fi
else
  warn "Could not install Tailscale — download from https://tailscale.com/download"
fi

# SSH — enable macOS Remote Login and harden config
if [[ "$OS" == "mac" ]]; then
  info "Configuring SSH (Remote Login)..."

  # Enable Remote Login if not already on
  if ! sudo systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
    sudo systemsetup -setremotelogin on
    success "Remote Login (SSH) enabled."
  else
    success "Remote Login (SSH) already enabled."
  fi

  # Ensure ~/.ssh exists with correct permissions
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  # Add the local public key to authorized_keys (prefer id_ed25519, then id_rsa).
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    KEY_PATH="$HOME/.ssh/id_ed25519"
  elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
    KEY_PATH="$HOME/.ssh/id_rsa"
  else
    KEY_PATH=""
    warn "No key at ~/.ssh/id_ed25519 or ~/.ssh/id_rsa — skipping authorized_keys."
  fi

  if [[ -n "$KEY_PATH" ]]; then
    PUBKEY="${KEY_PATH}.pub"
    if [[ ! -f "$PUBKEY" ]]; then
      info "Deriving public key from ${KEY_PATH}..."
      ssh-keygen -y -f "$KEY_PATH" > "$PUBKEY" 2>/dev/null && \
        success "Public key written to $PUBKEY." || \
        warn "Could not derive public key — add it to ~/.ssh/authorized_keys manually."
    fi
    if [[ -f "$PUBKEY" ]]; then
      touch "$HOME/.ssh/authorized_keys"
      chmod 600 "$HOME/.ssh/authorized_keys"
      if ! grep -qF "$(cat "$PUBKEY")" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
        cat "$PUBKEY" >> "$HOME/.ssh/authorized_keys"
        success "Public key added to authorized_keys."
      else
        success "Public key already in authorized_keys."
      fi
    fi
  fi

  # Harden sshd_config: key-only auth, no passwords
  SSHD_CONF="/etc/ssh/sshd_config"
  set_sshd_option() {
    local key="$1" val="$2"
    if grep -qE "^#?\\s*${key}" "$SSHD_CONF"; then
      sudo sed -i '' -E "s|^#?[[:space:]]*${key}.*|${key} ${val}|" "$SSHD_CONF"
    else
      echo "${key} ${val}" | sudo tee -a "$SSHD_CONF" > /dev/null
    fi
  }
  set_sshd_option "PasswordAuthentication"            "no"
  set_sshd_option "ChallengeResponseAuthentication"   "no"
  set_sshd_option "PubkeyAuthentication"              "yes"
  set_sshd_option "AuthorizedKeysFile"                ".ssh/authorized_keys"
  sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
  sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
  success "SSH hardened: key-only auth, passwords disabled."

elif [[ "$OS" == "linux" ]]; then
  warn "Linux SSH hardening: ensure sshd_config has PasswordAuthentication no and PubkeyAuthentication yes."
  warn "Then restart sshd: sudo systemctl restart sshd"
fi

# ─── done ─────────────────────────────────────────────────────────────────────
echo ""
success "${BOLD}Done.${RESET} agent-jacket bootstrapped for ${BOLD}${SELECTED_AGENTS[*]}${RESET}."
echo ""
if agent_selected claude; then echo "   ${DIM}Next: run 'claude' to log in.${RESET}"; fi
if agent_selected codex;  then echo "   ${DIM}Next: run 'codex' to log in.${RESET}"; fi
if agent_selected pi;     then echo "   ${DIM}Next: run 'pi /login' to authenticate.${RESET}"; fi
echo    "   ${DIM}Next: run 'tailscale up' to join your tailnet, then ./server.sh to start remote access.${RESET}"
echo ""
