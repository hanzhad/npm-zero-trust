#!/usr/bin/env bash
set -euo pipefail

# This script is a thin orchestrator. The actual per-step logic lives in
# lib/*.sh in this repo — the single source of truth, linked directly from
# setup.en.md / setup.ru.md — and is fetched fresh from `main` on every run,
# then discarded. Override NZT_BASE_URL to point at a local checkout for
# development (e.g. NZT_BASE_URL="file://$PWD" ./setup-zero-trust.sh).
NZT_BASE_URL="${NZT_BASE_URL:-https://raw.githubusercontent.com/hanzhad/npm-zero-trust/main}"
LIB_FILES=(wrap-npm.sh close-side-doors.sh git-hooks.sh)

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

for f in "${LIB_FILES[@]}"; do
  curl -fsSL "$NZT_BASE_URL/lib/$f" -o "$TMP_DIR/$f"
  # shellcheck source=/dev/null
  source "$TMP_DIR/$f"
done

# Check if NVM is loaded
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  source "$NVM_DIR/nvm.sh"
else
  echo "❌ NVM not found. Please install NVM first."
  exit 1
fi

STARTING_VERSION=$(nvm current)

secure_node_version() {
  local v=$1
  echo "🛡️  Securing Node version $v..."
  nvm use "$v" > /dev/null

  # 1. Install Socket CLI with forced PATH update
  echo "   📦 Installing @socketsecurity/cli..."
  npm install -g @socketsecurity/cli@latest > /dev/null

  # Ensure the bin path is refreshed in the current shell
  hash -r
  export PATH="$(npm bin -g):$PATH"

  # Verify socket is available
  if ! command -v socket >/dev/null; then
     echo "   ⚠️ Warning: Socket not immediately found in PATH. Retrying..."
     sleep 2
     export PATH="$HOME/.nvm/versions/node/$v/bin:$PATH"
  fi

  # 2. Global script lockdown
  npm config set ignore-scripts true --location=global

  # 3. Install Smart Wrappers (lib/wrap-npm.sh)
  install_npm_wrapper "$v" "$HOME/.npm-real/$v/bin"
  echo "   ✅ Wrappers installed for $v"
}

# --- Execution ---
echo "🚀 Starting mass Zero-Trust deployment..."

INSTALLED_VERSIONS=$(nvm ls --no-colors | grep -E '^(->)?[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*\*?[[:space:]]*$' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -u)

for v in $INSTALLED_VERSIONS; do
  secure_node_version "$v"
done

# --- Step 4 & 5 (lib/close-side-doors.sh, lib/git-hooks.sh) ---
close_side_doors
configure_git_hooks

nvm use "$STARTING_VERSION" > /dev/null
echo "🎯 Done! All Node versions secured."
