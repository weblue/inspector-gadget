#!/usr/bin/env bash
# install.sh — bootstrap local-briefcase for a target agent
#
# Usage:
#   ./install.sh              # interactive
#   ./install.sh claude       # non-interactive agent selection
#   ./install.sh codex
#   ./install.sh pi
#
# What this does:
#   1. Detect OS (mac / linux)
#   2. Prompt for agent selection (claude | codex | pi)
#   3. Install the agent CLI if not already present
#   4. For Pi: ask for auth method (default: subscription login)
#   5. Seed the agent's global config file (~/CLAUDE.md, ~/AGENTS.md, ~/.pi/agent/AGENTS.md)
#   6. Seed the agent's global ignore file (~/.claudeignore, ~/.agentsignore)
#   7. Install RTK (token-reduction proxy, no prompt modifications applied here)
#   8. Copy skills to the agent's global skill directory
#   9. If Pi: copy extensions to ~/.pi/agent/extensions/
#  10. Install cmux (mac only — native terminal multiplexer for agent workflows)
#
# TODO:
#   - RTK: run `rtk init -g [--agent <agent>]` to wire RTK into the agent context
#     (rtk init injects instructions into the agent's system context — review
#     agents/<agent>/CLAUDE.md or AGENTS.md after running to confirm behaviour)
#   - Copy agent profiles once agents/<agent>/profiles/ is defined

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD="\033[1m"
  DIM="\033[2m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  CYAN="\033[36m"
  RED="\033[31m"
  RESET="\033[0m"
else
  BOLD="" DIM="" GREEN="" YELLOW="" CYAN="" RED="" RESET=""
fi

info()    { echo -e "${CYAN}${BOLD}=>${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}✓${RESET}  $*"; }
warn()    { echo -e "${YELLOW}${BOLD}!${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}✗${RESET}  $*" >&2; exit 1; }
ask()     { echo -e "${BOLD}?${RESET}  $*"; }

# ─── os detection ─────────────────────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)  echo "linux" ;;
    *)      error "Unsupported OS: $(uname -s)" ;;
  esac
}

OS=$(detect_os)
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
AGENT="${1:-}"

if [[ -z "$AGENT" ]]; then
  echo ""
  ask "Which agent would you like to install?"
  echo "   ${BOLD}1)${RESET} claude  — Anthropic Claude Code"
  echo "   ${BOLD}2)${RESET} codex   — OpenAI Codex CLI"
  echo "   ${BOLD}3)${RESET} pi      — Pi (pi.dev)"
  echo ""
  read -rp "   Enter choice [1-3] or name: " AGENT_INPUT

  case "$AGENT_INPUT" in
    1|claude) AGENT="claude" ;;
    2|codex)  AGENT="codex"  ;;
    3|pi)     AGENT="pi"     ;;
    *) error "Unknown selection: '$AGENT_INPUT'. Choose 1, 2, or 3." ;;
  esac
fi

AGENT="${AGENT,,}"  # lowercase
[[ "$AGENT" =~ ^(claude|codex|pi)$ ]] || error "Unknown agent '$AGENT'. Must be claude, codex, or pi."
info "Selected agent: ${BOLD}${AGENT}${RESET}"

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

case "$AGENT" in
  claude) install_claude ;;
  codex)  install_codex  ;;
  pi)     install_pi     ;;
esac

# ─── pi auth setup ─────────────────────────────────────────────────────────────
if [[ "$AGENT" == "pi" ]]; then
  echo ""
  ask "Do you want to authenticate Pi with a direct API key?"
  echo "   ${BOLD}1)${RESET} No  ${DIM}(default — use 'pi /login' after install for subscription, OAuth, or browser auth)${RESET}"
  echo "   ${BOLD}2)${RESET} Yes ${DIM}(paste a provider API key now, e.g. Anthropic, OpenAI, Google)${RESET}"
  echo ""
  read -rp "   Enter choice [1-2, default 1]: " PI_AUTH_CHOICE
  PI_AUTH_CHOICE="${PI_AUTH_CHOICE:-1}"

  case "$PI_AUTH_CHOICE" in
    1|no|"")
      warn "Run 'pi /login' after install to authenticate."
      ;;
    2|yes|apikey|api)
      read -rp "   Provider (e.g. anthropic, openai, google): " PI_PROVIDER
      read -rsp "   API key (input hidden): " PI_API_KEY
      echo ""
      warn "API key auth wiring is not yet implemented in this script."
      warn "Set your key manually in ~/.pi/config or via 'pi auth'."
      # TODO: write key to ~/.pi/config or invoke `pi auth --provider "$PI_PROVIDER" --key "$PI_API_KEY"`
      ;;
    *)
      warn "Unknown choice — defaulting to login. Run 'pi /login' after install."
      ;;
  esac
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
    warn "File already exists: $dest"
    read -rp "   Overwrite? [y/N]: " OVERWRITE
    [[ "${OVERWRITE,,}" == "y" ]] || { info "Skipped $dest"; return; }
    cp "$dest" "${dest}.backup.$(date +%Y%m%d%H%M%S)"
    info "Backup saved: ${dest}.backup.*"
  fi

  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  success "Seeded: $dest"
}

echo ""
info "Seeding agent config..."

case "$AGENT" in
  claude)
    seed_file "$REPO_DIR/agents/claude/CLAUDE.md" "$HOME/CLAUDE.md"
    ;;
  codex)
    seed_file "$REPO_DIR/agents/codex/AGENTS.md" "$HOME/AGENTS.md"
    ;;
  pi)
    mkdir -p "$HOME/.pi/agent"
    seed_file "$REPO_DIR/agents/pi/system-prompt.md" "$HOME/.pi/agent/AGENTS.md"
    ;;
esac

# ─── seed ignore file ─────────────────────────────────────────────────────────
# Writes best-practice ignore rules to the agent's global ignore file.
# Claude: ~/.claudeignore
# Codex:  ~/.agentsignore
# Pi:     no standard ignore file — skipped

IGNORE_CONTENT='# ── build & dependencies ────────────────────────────────────────────────────
node_modules/
vendor/
.pnp/
.pnp.js

# ── build outputs ─────────────────────────────────────────────────────────────
dist/
build/
out/
.next/
.nuxt/
.svelte-kit/
target/
__pycache__/
*.pyc
*.pyo
*.class
*.o
*.a

# ── environment & secrets ─────────────────────────────────────────────────────
.env
.env.*
*.env
*.key
*.pem
*.p12
*.pfx
secrets/
credentials/
.netrc

# ── lock files (large, low signal) ───────────────────────────────────────────
package-lock.json
yarn.lock
pnpm-lock.yaml
Cargo.lock
poetry.lock
Gemfile.lock

# ── logs & caches ─────────────────────────────────────────────────────────────
*.log
logs/
.cache/
.parcel-cache/
.turbo/
coverage/
.nyc_output/

# ── os & editor noise ─────────────────────────────────────────────────────────
.DS_Store
Thumbs.db
.idea/
.vscode/
*.swp
*.swo

# ── version control ───────────────────────────────────────────────────────────
.git/

# ── large / binary assets ─────────────────────────────────────────────────────
*.png
*.jpg
*.jpeg
*.gif
*.webp
*.mp4
*.mov
*.zip
*.tar.gz
*.tgz
'

seed_ignore() {
  local dest="$1"
  if [[ -f "$dest" ]]; then
    warn "Ignore file already exists: $dest"
    read -rp "   Overwrite? [y/N]: " OVERWRITE
    [[ "${OVERWRITE,,}" == "y" ]] || { info "Skipped $dest"; return; }
    cp "$dest" "${dest}.backup.$(date +%Y%m%d%H%M%S)"
  fi
  printf '%s' "$IGNORE_CONTENT" > "$dest"
  success "Seeded: $dest"
}

echo ""
info "Seeding ignore file..."

case "$AGENT" in
  claude) seed_ignore "$HOME/.claudeignore" ;;
  codex)  seed_ignore "$HOME/.agentsignore" ;;
  pi)     info "Pi has no standard global ignore file — skipping." ;;
esac

# ─── install rtk ──────────────────────────────────────────────────────────────
# RTK is a CLI proxy that reduces LLM token consumption by 60–90% on common
# dev commands (git, docker, npm, cargo, etc.) by compressing output before
# it reaches the agent's context window.
#
# RTK is installed here without modifying any prompts or agent config.
#
# TODO: run `rtk init -g` (claude/codex) or the appropriate --agent flag to
#       wire RTK into the agent's system context. Review the resulting changes
#       to ~/CLAUDE.md or ~/AGENTS.md before committing — rtk init injects
#       its own instructions into the agent context.
#         claude:  rtk init -g
#         codex:   rtk init -g  (verify --agent flag for codex in rtk docs)
#         pi:      rtk init -g  (verify --agent flag for pi in rtk docs)

echo ""
info "Installing RTK..."

if command -v rtk &>/dev/null; then
  success "rtk is already installed ($(rtk --version 2>/dev/null || echo 'version unknown'))"
else
  if [[ "$OS" == "mac" ]] && command -v brew &>/dev/null; then
    brew install rtk
  else
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  fi
  success "RTK installed."
fi

warn "RTK system-context wiring is not yet automated — see TODO in this script."

# ─── copy skills ──────────────────────────────────────────────────────────────
# Copies all skills from skills/ into the agent's global skill directory.
#
# Destinations:
#   claude: ~/.claude/skills/<skill>/      (referenced from CLAUDE.md via @~/.claude/skills/...)
#   codex:  ~/.codex/skills/<skill>/       (TBD — verify codex skill loading path)
#   pi:     ~/.pi/agent/<skill>.md         (Pi loads all .md files in ~/.pi/agent/ at startup;
#                                           only the top-level SKILL.md is copied, not references/)

copy_skills() {
  local skills_src="$REPO_DIR/skills"
  local skills_dest="$1"
  local pi_mode="${2:-false}"

  if [[ ! -d "$skills_src" ]]; then
    warn "skills/ directory not found, skipping."
    return
  fi

  local copied=0
  for skill_dir in "$skills_src"/*/; do
    local skill_name
    skill_name="$(basename "$skill_dir")"

    if [[ "$pi_mode" == "true" ]]; then
      # Pi: copy only SKILL.md, flattened, as <skill-name>.md
      local src="$skill_dir/SKILL.md"
      local dest="$skills_dest/${skill_name}.md"
      if [[ -f "$src" ]]; then
        mkdir -p "$skills_dest"
        cp "$src" "$dest"
        success "Skill → $dest"
        (( copied++ )) || true
      fi
    else
      # Claude / Codex: copy full skill directory
      local dest="$skills_dest/$skill_name"
      mkdir -p "$dest"
      cp -r "$skill_dir"* "$dest/"
      success "Skill → $dest"
      (( copied++ )) || true
    fi
  done

  [[ $copied -gt 0 ]] || warn "No skills found in skills/ — nothing copied."
}

echo ""
info "Copying skills..."

case "$AGENT" in
  claude)
    mkdir -p "$HOME/.claude/skills"
    copy_skills "$HOME/.claude/skills"
    ;;
  codex)
    mkdir -p "$HOME/.codex/skills"
    copy_skills "$HOME/.codex/skills"
    ;;
  pi)
    mkdir -p "$HOME/.pi/agent"
    copy_skills "$HOME/.pi/agent" "true"
    ;;
esac

# ─── pi extensions ────────────────────────────────────────────────────────────
# Copies all Pi extensions from extensions/pi/ to ~/.pi/agent/extensions/.
# Extensions are TypeScript files loaded by Pi at startup.

if [[ "$AGENT" == "pi" ]]; then
  echo ""
  info "Installing Pi extensions..."

  local ext_src="$REPO_DIR/extensions/pi"
  local ext_dest="$HOME/.pi/agent/extensions"

  if [[ ! -d "$ext_src" ]]; then
    warn "extensions/pi/ not found, skipping."
  else
    mkdir -p "$ext_dest"
    for ext_file in "$ext_src"/*.ts; do
      [[ -f "$ext_file" ]] || continue
      cp "$ext_file" "$ext_dest/"
      success "Extension → $ext_dest/$(basename "$ext_file")"
    done
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

# ─── TODO: agent profiles ─────────────────────────────────────────────────────
# TODO: once agents/<agent>/profiles/ is defined, copy profiles on install.

# ─── done ─────────────────────────────────────────────────────────────────────
echo ""
success "${BOLD}Done.${RESET} local-briefcase bootstrapped for ${BOLD}${AGENT}${RESET}."
echo ""
case "$AGENT" in
  claude) echo -e "   ${DIM}Next: run 'claude' to log in.${RESET}" ;;
  codex)  echo -e "   ${DIM}Next: run 'codex' to log in.${RESET}" ;;
  pi)     echo -e "   ${DIM}Next: run 'pi' to log in or complete auth.${RESET}" ;;
esac
echo ""
