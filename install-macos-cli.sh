#!/usr/bin/env bash
set -euo pipefail

PACKAGE_SPEC="${AGENT_OS_PACKAGE_SPEC:-@vionwilliams/agent-os@latest}"
MIN_NODE_MAJOR="${AGENT_OS_MIN_NODE_MAJOR:-20}"
MIN_BUN_VERSION="${AGENT_OS_MIN_BUN_VERSION:-1.3.0}"
NPM_CACHE_DIR="${AGENT_OS_NPM_CACHE:-${HOME}/.agent-os/npm-cache}"
SHORTCUT_BIN_DIR="${AGENT_OS_SHORTCUT_BIN:-${HOME}/.agent-os/bin}"

log() {
  printf '\033[1;34m[agent-os]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[agent-os]\033[0m %s\n' "$*" >&2
}

fail() {
  printf '\033[1;31m[agent-os]\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Install Agent-OS CLI on macOS.

Usage:
  bash install-macos-cli.sh

Environment variables:
  AGENT_OS_PACKAGE_SPEC   npm package spec to install.
                          Default: ${PACKAGE_SPEC}
  AGENT_OS_MIN_NODE_MAJOR Minimum Node.js major version.
                          Default: ${MIN_NODE_MAJOR}
  AGENT_OS_MIN_BUN_VERSION Minimum Bun version.
                          Default: ${MIN_BUN_VERSION}
  AGENT_OS_NPM_CACHE      npm cache directory used by this installer.
                          Default: ${NPM_CACHE_DIR}
  AGENT_OS_SHORTCUT_BIN   Directory for Agent-OS convenience commands.
                          Default: ${SHORTCUT_BIN_DIR}
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "This installer is for macOS only. Detected: $(uname -s)"
fi

PROFILE_FILE="${HOME}/.zshrc"
case "${SHELL:-}" in
  */bash) PROFILE_FILE="${HOME}/.bash_profile" ;;
  */zsh|"") PROFILE_FILE="${HOME}/.zshrc" ;;
esac

append_profile_line() {
  local line="$1"
  touch "${PROFILE_FILE}"
  if ! grep -Fqx "${line}" "${PROFILE_FILE}"; then
    printf '\n%s\n' "${line}" >> "${PROFILE_FILE}"
  fi
}

add_to_path_for_now() {
  local dir="$1"
  case ":${PATH}:" in
    *":${dir}:"*) ;;
    *) export PATH="${dir}:${PATH}" ;;
  esac
}

version_ge() {
  local current="$1"
  local required="$2"
  local current_major current_minor current_patch
  local required_major required_minor required_patch

  IFS=. read -r current_major current_minor current_patch <<<"${current}"
  IFS=. read -r required_major required_minor required_patch <<<"${required}"

  current_major="${current_major:-0}"
  current_minor="${current_minor:-0}"
  current_patch="${current_patch:-0}"
  required_major="${required_major:-0}"
  required_minor="${required_minor:-0}"
  required_patch="${required_patch:-0}"

  if (( current_major > required_major )); then return 0; fi
  if (( current_major < required_major )); then return 1; fi
  if (( current_minor > required_minor )); then return 0; fi
  if (( current_minor < required_minor )); then return 1; fi
  (( current_patch >= required_patch ))
}

install_or_load_nvm() {
  export NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"

  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    log "Installing nvm for user-local Node.js..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  fi

  # shellcheck source=/dev/null
  . "${NVM_DIR}/nvm.sh"

  append_profile_line 'export NVM_DIR="$HOME/.nvm"'
  append_profile_line '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
}

ensure_node() {
  local node_major=""

  if command -v node >/dev/null 2>&1; then
    node_major="$(node -p "Number(process.versions.node.split('.')[0])" 2>/dev/null || true)"
  fi

  if [[ -n "${node_major}" && "${node_major}" -ge "${MIN_NODE_MAJOR}" ]] && command -v npm >/dev/null 2>&1; then
    log "Node.js is ready: $(node -v), npm $(npm -v)"
    return
  fi

  if [[ -n "${node_major}" ]]; then
    warn "Current Node.js major version is ${node_major}; Agent-OS expects >= ${MIN_NODE_MAJOR}."
  else
    warn "Node.js/npm not found."
  fi

  install_or_load_nvm
  log "Installing Node.js LTS with nvm..."
  nvm install --lts
  nvm use --lts

  command -v node >/dev/null 2>&1 || fail "Node.js install finished, but node is still not in PATH."
  command -v npm >/dev/null 2>&1 || fail "Node.js install finished, but npm is still not in PATH."
  log "Node.js is ready: $(node -v), npm $(npm -v)"
}

ensure_bun() {
  export BUN_INSTALL="${BUN_INSTALL:-${HOME}/.bun}"
  add_to_path_for_now "${BUN_INSTALL}/bin"

  if command -v bun >/dev/null 2>&1; then
    local current
    current="$(bun -v)"
    if version_ge "${current}" "${MIN_BUN_VERSION}"; then
      log "Bun is ready: ${current}"
      append_profile_line 'export BUN_INSTALL="$HOME/.bun"'
      append_profile_line 'export PATH="$BUN_INSTALL/bin:$PATH"'
      return
    fi
    warn "Current Bun version is ${current}; Agent-OS expects >= ${MIN_BUN_VERSION}."
  else
    warn "Bun not found."
  fi

  log "Installing Bun..."
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="${HOME}/.bun"
  add_to_path_for_now "${BUN_INSTALL}/bin"

  append_profile_line 'export BUN_INSTALL="$HOME/.bun"'
  append_profile_line 'export PATH="$BUN_INSTALL/bin:$PATH"'

  command -v bun >/dev/null 2>&1 || fail "Bun install finished, but bun is still not in PATH."
  log "Bun is ready: $(bun -v)"
}

ensure_npm_global_bin() {
  local prefix bin
  prefix="$(npm config get prefix)"
  bin="${prefix}/bin"

  if [[ ! -d "${bin}" ]]; then
    mkdir -p "${bin}" 2>/dev/null || true
  fi

  add_to_path_for_now "${bin}"
  append_profile_line "export PATH=\"${bin}:\$PATH\""
}

ensure_npm_cache() {
  mkdir -p "${NPM_CACHE_DIR}" || fail "Unable to create npm cache directory: ${NPM_CACHE_DIR}"
  export NPM_CONFIG_CACHE="${NPM_CACHE_DIR}"
  export npm_config_cache="${NPM_CACHE_DIR}"
  log "Using npm cache: ${NPM_CACHE_DIR}"
}

install_agent_os() {
  ensure_npm_cache
  ensure_npm_global_bin

  log "Installing Agent-OS CLI from npm: ${PACKAGE_SPEC}"
  if npm install -g "${PACKAGE_SPEC}"; then
    return
  fi

  warn "Global npm install failed. Retrying with a user-local npm prefix..."
  mkdir -p "${HOME}/.npm-global"
  npm config set prefix "${HOME}/.npm-global"
  add_to_path_for_now "${HOME}/.npm-global/bin"
  append_profile_line 'export PATH="$HOME/.npm-global/bin:$PATH"'

  npm install -g "${PACKAGE_SPEC}"
}

ensure_agent_os_shortcuts() {
  local agent_path
  agent_path="$(command -v agent-os || true)"
  if [[ -z "${agent_path}" ]]; then
    return
  fi

  mkdir -p "${SHORTCUT_BIN_DIR}" || fail "Unable to create shortcut directory: ${SHORTCUT_BIN_DIR}"
  add_to_path_for_now "${SHORTCUT_BIN_DIR}"
  append_profile_line 'export PATH="$HOME/.agent-os/bin:$PATH"'

  if [[ "${agent_path}" != "${SHORTCUT_BIN_DIR}/agent-os" ]]; then
    ln -sf "${agent_path}" "${SHORTCUT_BIN_DIR}/agent-os"
  fi
  ln -sf "${agent_path}" "${SHORTCUT_BIN_DIR}/aos"
  log "Convenience commands are ready: agent-os, aos"
}

verify_agent_os() {
  hash -r 2>/dev/null || true
  command -v agent-os >/dev/null 2>&1 || fail "agent-os is not in PATH after install. Restart Terminal and run: agent-os --version"
  ensure_agent_os_shortcuts
  hash -r 2>/dev/null || true

  log "Agent-OS installed at: $(command -v agent-os)"
  agent-os --version

  if command -v aos >/dev/null 2>&1; then
    log "Agent-OS shortcut installed at: $(command -v aos)"
    aos --version
  fi
}

log "Starting macOS Agent-OS CLI installer."
ensure_node
ensure_bun
install_agent_os
verify_agent_os

cat <<EOF

Agent-OS CLI is installed.

Next commands:
  agent-os --help
  aos --help
  agent-os -p "回复 pong"

If a new Terminal cannot find agent-os, restart Terminal or run:
  source ${PROFILE_FILE}
EOF
