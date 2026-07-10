#!/usr/bin/env bash
set -euo pipefail

REPO="${AGENT_OS_REPO:-VIONWILLIAMS/agent-os-install}"
GITHUB_API_URL="${AGENT_OS_GITHUB_API_URL:-https://api.github.com}"
RELEASE_BASE_URL="${AGENT_OS_RELEASE_BASE_URL:-https://github.com/${REPO}/releases/download}"
INSTALL_ROOT="${AGENT_OS_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/agent-os}"
BIN_DIR="${AGENT_OS_BIN_DIR:-$HOME/.local/bin}"
CHANNEL="stable"
VERSION=""
MODIFY_PATH=1
AUTO_UPDATE=1

usage() {
  cat <<EOF
Install Agent-OS as a self-contained native application.

Usage:
  bash scripts/install.sh [options]

Options:
  --channel <stable|beta>  Release channel (default: stable)
  --version <X.Y.Z>        Install an exact version
  --install-root <path>    Versioned install root (default: ${INSTALL_ROOT})
  --bin-dir <path>         Command directory (default: ${BIN_DIR})
  --no-modify-path         Do not update the shell profile
  --no-auto-update         Disable the once-per-day background update check
  -h, --help               Show this help

No Node.js, Bun, npm, or sudo is required.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --install-root) INSTALL_ROOT="${2:-}"; shift 2 ;;
    --bin-dir|--install-dir) BIN_DIR="${2:-}"; shift 2 ;;
    --no-modify-path) MODIFY_PATH=0; shift ;;
    --no-auto-update) AUTO_UPDATE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

case "$CHANNEL" in
  stable|beta) ;;
  *) echo "Unsupported channel: $CHANNEL (use stable or beta)" >&2; exit 1 ;;
esac

for command in curl tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
case "${os}:${arch}" in
  darwin:arm64|darwin:aarch64) platform="darwin-arm64" ;;
  darwin:x86_64|darwin:amd64) platform="darwin-x64" ;;
  linux:arm64|linux:aarch64) platform="linux-arm64" ;;
  linux:x86_64|linux:amd64) platform="linux-x64" ;;
  *)
    echo "Unsupported platform: ${os}:${arch}" >&2
    echo "See https://github.com/${REPO}/releases for available downloads." >&2
    exit 1
    ;;
esac

resolve_release_tag() {
  if [[ -n "$VERSION" ]]; then
    case "$VERSION" in v*) printf '%s\n' "$VERSION" ;; *) printf 'v%s\n' "$VERSION" ;; esac
    return
  fi
  if [[ "$CHANNEL" == stable ]]; then
    curl -fsSL "${GITHUB_API_URL}/repos/${REPO}/releases/latest" |
      sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' |
      head -n 1
    return
  fi
  curl -fsSL "${GITHUB_API_URL}/repos/${REPO}/releases?per_page=30" |
    awk -F'"' '
      /"tag_name":[[:space:]]*/ { tag=$4; draft=0 }
      /"draft":[[:space:]]*false/ { draft=1 }
      /"prerelease":[[:space:]]*true/ {
        if (draft && tag ~ /-beta([.\-"]|$)/) { print tag; exit }
      }
    '
}

TAG="$(resolve_release_tag)"
if [[ -z "$TAG" ]]; then
  echo "Could not resolve an Agent-OS ${CHANNEL} release." >&2
  exit 1
fi
VERSION="${TAG#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Release tag is not valid SemVer: $TAG" >&2
  exit 1
fi

ASSET_NAME="agent-os-v${VERSION}-${platform}.tar.gz"
ASSET_URL="${RELEASE_BASE_URL%/}/${TAG}/${ASSET_NAME}"
CHECKSUM_URL="${ASSET_URL}.sha256"
VERSIONS_DIR="${INSTALL_ROOT}/versions"
STAGING_DIR="${INSTALL_ROOT}/staging/${VERSION}.$$.$(date +%s)"
EXTRACT_DIR="${STAGING_DIR}/extract"
STATE_FILE="${INSTALL_ROOT}/install.json"
CURRENT_LINK="${INSTALL_ROOT}/current"
LOCK_FILE="${INSTALL_ROOT}/update.lock"
PREVIOUS_VERSION=""
LOCK_HELD=0

cleanup() {
  rm -rf "$STAGING_DIR"
  if [[ "$LOCK_HELD" == 1 ]]; then rm -f "$LOCK_FILE"; fi
}
trap cleanup EXIT

mkdir -p "$INSTALL_ROOT" "$VERSIONS_DIR" "$BIN_DIR" "$EXTRACT_DIR"
if [[ -f "$LOCK_FILE" ]]; then
  lock_pid="$(sed -n '1p' "$LOCK_FILE" 2>/dev/null || true)"
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "Another Agent-OS install or update is already running (PID ${lock_pid})." >&2
    exit 1
  fi
  rm -f "$LOCK_FILE"
fi
if ( set -o noclobber; printf '%s\n' "$$" > "$LOCK_FILE" ) 2>/dev/null; then
  LOCK_HELD=1
else
  echo "Another Agent-OS install or update is already running." >&2
  exit 1
fi

if [[ -f "$STATE_FILE" ]]; then
  PREVIOUS_VERSION="$(sed -n 's/.*"currentVersion":[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | head -n 1)"
elif [[ -L "$CURRENT_LINK" ]]; then
  PREVIOUS_VERSION="$(basename "$(readlink "$CURRENT_LINK")")"
fi

ARCHIVE_PATH="${STAGING_DIR}/${ASSET_NAME}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
echo "Installing Agent-OS ${VERSION} (${platform}, ${CHANNEL})"
echo "Downloading ${ASSET_URL}"
curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 "$ASSET_URL" --output "$ARCHIVE_PATH"
curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 "$CHECKSUM_URL" --output "$CHECKSUM_PATH"

expected_checksum="$(sed -n 's/^\([a-fA-F0-9]\{64\}\).*/\1/p' "$CHECKSUM_PATH" | head -n 1 | tr '[:upper:]' '[:lower:]')"
if [[ -z "$expected_checksum" ]]; then
  echo "Invalid checksum file: ${CHECKSUM_URL}" >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  actual_checksum="$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')"
else
  actual_checksum="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
fi
if [[ "$actual_checksum" != "$expected_checksum" ]]; then
  echo "SHA-256 verification failed for ${ASSET_NAME}." >&2
  exit 1
fi
echo "Checksum verified."

tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR"
for command in agent-os agent-os-scriptcut agent-os-db; do
  if [[ ! -s "${EXTRACT_DIR}/bin/${command}" ]]; then
    echo "Native bundle is missing bin/${command}." >&2
    exit 1
  fi
  chmod +x "${EXTRACT_DIR}/bin/${command}"
done
for ui in workbench-ui bdi-ui; do
  if [[ ! -s "${EXTRACT_DIR}/share/agent-os/${ui}/index.html" ]]; then
    echo "Native bundle is missing ${ui}/index.html." >&2
    exit 1
  fi
done
if [[ ! -s "${EXTRACT_DIR}/manifest.json" ]]; then
  echo "Native bundle is missing manifest.json." >&2
  exit 1
fi
manifest_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${EXTRACT_DIR}/manifest.json" | head -n 1)"
manifest_platform="$(sed -n 's/.*"platform"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${EXTRACT_DIR}/manifest.json" | head -n 1)"
if [[ "$manifest_version" != "$VERSION" || "$manifest_platform" != "$platform" ]]; then
  echo "Native bundle manifest does not match ${VERSION}/${platform}." >&2
  exit 1
fi

version_output="$(AGENT_OS_ASSET_ROOT="${EXTRACT_DIR}/share/agent-os" "${EXTRACT_DIR}/bin/agent-os" --version)"
case "$version_output" in
  *"$VERSION"*) ;;
  *) echo "Staged binary failed version verification: $version_output" >&2; exit 1 ;;
esac

CONFIG_DIR="${AGENT_OS_CONFIG_DIR:-$HOME/.agent-os}"
DATABASE="${CONFIG_DIR}/coordination.db"
if [[ -f "$DATABASE" && "$PREVIOUS_VERSION" != "$VERSION" ]]; then
  BACKUP_DIR="${CONFIG_DIR}/backups"
  mkdir -p "$BACKUP_DIR"
  BACKUP_PATH="${BACKUP_DIR}/coordination.pre-update-${VERSION}.$(date -u +%Y%m%dT%H%M%SZ).db"
  echo "Backing up coordination database to ${BACKUP_PATH}"
  "${EXTRACT_DIR}/bin/agent-os-db" backup \
    --db "$DATABASE" \
    --output "$BACKUP_PATH" >/dev/null
fi

VERSION_DIR="${VERSIONS_DIR}/${VERSION}"
TEMP_VERSION_DIR="${VERSIONS_DIR}/.${VERSION}.tmp.$$"
rm -rf "$TEMP_VERSION_DIR"
mv "$EXTRACT_DIR" "$TEMP_VERSION_DIR"
rm -rf "$VERSION_DIR"
mv "$TEMP_VERSION_DIR" "$VERSION_DIR"

activate_version() {
  local requested="$1"
  local requested_dir="${VERSIONS_DIR}/${requested}"
  if [[ ! -x "${requested_dir}/bin/agent-os" ]]; then return 1; fi
  local temp_link="${CURRENT_LINK}.tmp.$$"
  rm -f "$temp_link"
  ln -s "$requested_dir" "$temp_link"
  mv -f "$temp_link" "$CURRENT_LINK"
  for command in agent-os agent-os-scriptcut agent-os-db; do
    local command_link="${BIN_DIR}/${command}"
    local command_temp="${command_link}.tmp.$$"
    rm -f "$command_temp"
    ln -s "${CURRENT_LINK}/bin/${command}" "$command_temp"
    mv -f "$command_temp" "$command_link"
  done
}

if ! activate_version "$VERSION"; then
  if [[ -n "$PREVIOUS_VERSION" ]]; then activate_version "$PREVIOUS_VERSION" || true; fi
  echo "Failed to activate Agent-OS ${VERSION}; the previous version was restored." >&2
  exit 1
fi

if ! "${BIN_DIR}/agent-os" --version | grep -F "$VERSION" >/dev/null; then
  if [[ -n "$PREVIOUS_VERSION" ]]; then activate_version "$PREVIOUS_VERSION" || true; fi
  echo "Post-install verification failed; the previous version was restored." >&2
  exit 1
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
previous_json=""
if [[ -n "$PREVIOUS_VERSION" && "$PREVIOUS_VERSION" != "$VERSION" ]]; then
  previous_json="  \"previousVersion\": \"${PREVIOUS_VERSION}\",\n"
fi
auto_update_json=false
if [[ "$AUTO_UPDATE" == 1 ]]; then auto_update_json=true; fi
STATE_TEMP="${STATE_FILE}.tmp.$$"
printf '{\n  "schemaVersion": 1,\n  "installMethod": "native",\n  "channel": "%s",\n  "autoUpdate": %s,\n  "currentVersion": "%s",\n%b  "installedAt": "%s",\n  "updatedAt": "%s",\n  "lastCheckedAt": "%s"\n}\n' \
  "$CHANNEL" "$auto_update_json" "$VERSION" "$previous_json" "$now" "$now" "$now" > "$STATE_TEMP"
mv -f "$STATE_TEMP" "$STATE_FILE"

path_is_configured=0
case ":${PATH:-}:" in *":${BIN_DIR}:"*) path_is_configured=1 ;; esac
profile=""
if [[ "$MODIFY_PATH" == 1 && "$path_is_configured" == 0 ]]; then
  shell_name="$(basename "${SHELL:-sh}")"
  case "$shell_name" in
    zsh) profile="$HOME/.zshrc" ;;
    bash)
      if [[ "$os" == darwin ]]; then profile="$HOME/.bash_profile"; else profile="$HOME/.bashrc"; fi
      ;;
  esac
  if [[ -n "$profile" ]]; then
    path_line='export PATH="$HOME/.local/bin:$PATH"'
    if [[ "$BIN_DIR" != "$HOME/.local/bin" ]]; then
      path_line="export PATH=\"${BIN_DIR}:\$PATH\""
    fi
    touch "$profile"
    if ! grep -F "$path_line" "$profile" >/dev/null 2>&1; then
      printf '\n# Agent-OS native CLI\n%s\n' "$path_line" >> "$profile"
    fi
  fi
fi

echo
echo "Agent-OS ${VERSION} installed successfully."
echo "Commands: ${BIN_DIR}/agent-os, agent-os-scriptcut, agent-os-db"
echo "Update channel: ${CHANNEL}; automatic updates: ${auto_update_json}"
if [[ "$path_is_configured" == 0 ]]; then
  echo "${BIN_DIR} is not in this shell's PATH yet."
  if [[ -n "$profile" ]]; then
    echo "Run: source ${profile}"
  else
    echo "Add this to your shell profile: export PATH=\"${BIN_DIR}:\$PATH\""
  fi
fi
echo "Verify: agent-os --version"
