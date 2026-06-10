#!/usr/bin/env bash
# client-install.sh — prep a remote machine to access this server
#
# What this does:
#   1. Detects OS (mac / linux)
#   2. Installs Tailscale and prompts to join the tailnet
#   3. Writes an SSH config entry for the server
#   4. Verifies SSH key is present (or generates one to send to the server)
#   5. Prints connection instructions
#
# No agents are installed on the client. All agentic flows run on the server.
# Clients connect via: ssh <server> → tmux attach -t agent-jacket

set -euo pipefail

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

info()    { echo "${CYAN}${BOLD}=>${RESET} $*"; }
success() { echo "${GREEN}${BOLD}✓${RESET}  $*"; }
warn()    { echo "${YELLOW}${BOLD}!${RESET}  $*"; }
error()   { echo "${RED}${BOLD}✗${RESET}  $*" >&2; exit 1; }
ask()     { echo "${BOLD}?${RESET}  $*"; }
lc()      { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ─── os detection ─────────────────────────────────────────────────────────────
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  *)      error "Unsupported OS: $(uname -s)" ;;
esac
info "Detected OS: ${OS}"

# ─── tailscale ────────────────────────────────────────────────────────────────
echo ""
info "Installing Tailscale..."

if command -v tailscale &>/dev/null; then
  success "Tailscale is already installed."
else
  if [[ "$OS" == "mac" ]] && command -v brew &>/dev/null; then
    brew install --cask tailscale
    success "Tailscale installed."
  elif [[ "$OS" == "linux" ]]; then
    curl -fsSL https://tailscale.com/install.sh | sh
    success "Tailscale installed."
  else
    warn "Could not auto-install Tailscale. Download from: https://tailscale.com/download"
  fi
fi

# ─── cmux (mac only) ──────────────────────────────────────────────────────────
if [[ "$OS" == "mac" ]]; then
  echo ""
  info "Installing cmux..."
  if [[ -d "/Applications/cmux.app" ]]; then
    success "cmux is already installed."
  elif command -v brew &>/dev/null; then
    brew tap manaflow-ai/cmux 2>/dev/null || true
    brew install --cask cmux
    success "cmux installed. Open cmux from Applications to launch it."
  else
    warn "Homebrew not found. Download cmux manually:"
    warn "  https://github.com/manaflow-ai/cmux/releases/latest/download/cmux-macos.dmg"
  fi
fi

TS_STATUS="$(tailscale status --json 2>/dev/null | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('BackendState',''))" 2>/dev/null || echo "unknown")"

if [[ "$TS_STATUS" == "Running" ]]; then
  success "Tailscale is connected."
else
  warn "Tailscale is not connected."
  echo ""
  if [[ "$OS" == "mac" ]]; then
    echo "  Open the Tailscale menu bar app and sign in to join your tailnet."
  else
    echo "  Run: sudo tailscale up"
    echo "  Then follow the link to authenticate."
  fi
  echo ""
  read -rp "  Press Enter once you've joined the tailnet to continue... "
fi

# ─── server details ───────────────────────────────────────────────────────────
echo ""
ask "What is the server's Tailscale hostname or IP?"
echo "  ${DIM}(Find it on the server by running: tailscale ip -4  or  tailscale status)${RESET}"
echo ""
read -rp "  Server hostname or IP: " SERVER_HOST

ask "What is the SSH username on the server?"
read -rp "  Username [default: $(whoami)]: " SERVER_USER
SERVER_USER="${SERVER_USER:-$(whoami)}"

SSH_ALIAS="agent-jacket-server"
ask "What alias should this server have in ~/.ssh/config?"
read -rp "  Alias [default: ${SSH_ALIAS}]: " SSH_ALIAS_INPUT
SSH_ALIAS="${SSH_ALIAS_INPUT:-$SSH_ALIAS}"

# ─── ssh key ──────────────────────────────────────────────────────────────────
echo ""
info "Checking SSH key..."

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Prefer an existing id_ed25519, then id_rsa; otherwise generate an ed25519 key.
if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
  KEY_PATH="$HOME/.ssh/id_ed25519"
  success "SSH key found: ~/.ssh/id_ed25519"
elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
  KEY_PATH="$HOME/.ssh/id_rsa"
  success "SSH key found: ~/.ssh/id_rsa"
else
  warn "No SSH key found. Generating ed25519 key..."
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "${USER}@$(hostname)-client"
  KEY_PATH="$HOME/.ssh/id_ed25519"
  success "Key generated: ~/.ssh/id_ed25519"
fi

# Derive the public key if it's missing (e.g. only a private id_rsa is present).
PUBKEY_PATH="${KEY_PATH}.pub"
if [[ ! -f "$PUBKEY_PATH" ]]; then
  info "Deriving public key from ${KEY_PATH}..."
  ssh-keygen -y -f "$KEY_PATH" > "$PUBKEY_PATH" 2>/dev/null && \
    success "Public key written: ${PUBKEY_PATH}" || \
    warn "Could not derive public key from ${KEY_PATH}."
fi

# ~-relative form for the SSH config IdentityFile line.
IDENTITY_REL="~/.ssh/$(basename "$KEY_PATH")"

# ─── ssh config ───────────────────────────────────────────────────────────────
echo ""
info "Writing SSH config entry..."

SSH_CONFIG="$HOME/.ssh/config"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if grep -q "^Host ${SSH_ALIAS}$" "$SSH_CONFIG" 2>/dev/null; then
  warn "Entry '${SSH_ALIAS}' already exists in ~/.ssh/config — skipping."
else
  cat >> "$SSH_CONFIG" <<EOF

# agent-jacket server — added by client-install.sh
Host ${SSH_ALIAS}
  HostName ${SERVER_HOST}
  User ${SERVER_USER}
  IdentityFile ${IDENTITY_REL}
  ServerAliveInterval 60
  ServerAliveCountMax 3
EOF
  success "SSH config entry written: Host ${SSH_ALIAS}"
fi

# ─── authorize client key on server ───────────────────────────────────────────
echo ""
if [[ -f "$PUBKEY_PATH" ]]; then
  PUBKEY_CONTENT="$(cat "$PUBKEY_PATH")"
  info "Your public key (add this to the server's ~/.ssh/authorized_keys if not already there):"
  echo ""
  echo "  ${DIM}${PUBKEY_CONTENT}${RESET}"
  echo ""
  read -rp "  Try to copy it to the server now via ssh-copy-id? [y/N]: " DO_COPY
  if [[ "$(lc "$DO_COPY")" == "y" ]]; then
    ssh-copy-id -i "$PUBKEY_PATH" "${SERVER_USER}@${SERVER_HOST}" && \
      success "Public key copied to server." || \
      warn "ssh-copy-id failed — copy the key manually."
  else
    warn "Add the key manually by running on the server:"
    echo "  echo '${PUBKEY_CONTENT}' >> ~/.ssh/authorized_keys"
  fi
fi

# ─── done ─────────────────────────────────────────────────────────────────────
echo ""
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${BOLD}  Client setup complete${RESET}"
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo "  ${BOLD}Open server sessions in cmux (mac):${RESET}"
echo "  ${CYAN}./connect.sh${RESET}"
echo "  ${DIM}Opens Pi, shell, and logs workspaces in cmux, each SSH'd to the server.${RESET}"
echo ""
echo "  ${BOLD}Or connect manually:${RESET}"
echo "  ${CYAN}ssh ${SSH_ALIAS} -t 'tmux attach -t agent-jacket'${RESET}"
echo ""
echo "  ${DIM}Ensure Tailscale is connected on this machine before connecting.${RESET}"
echo ""
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
