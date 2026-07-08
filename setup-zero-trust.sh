#!/usr/bin/env bash
set -euo pipefail

# Check if NVM is loaded
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  source "$NVM_DIR/nvm.sh"
else
  echo "❌ NVM not found. Please install NVM first."
  exit 1
fi

# Remember starting version to return to it later
STARTING_VERSION=$(nvm current)

# Function to secure a single Node version
secure_node_version() {
  local v=$1
  echo "🛡️  Securing Node version $v..."
  nvm use "$v" > /dev/null

  # 1. Install Socket CLI
  echo "   📦 Installing @socketsecurity/cli..."
  npm install -g @socketsecurity/cli@latest > /dev/null

  # 2. Global script lockdown
  npm config set ignore-scripts true --location=global

  # 3. Install Smart Wrappers
  REAL_DIR="$HOME/.npm-real/$v/bin"
  mkdir -p "$REAL_DIR"

  resolve() {
    f="$1"
    while [ -L "$f" ]; do
      l="$(readlink "$f")"
      case "$l" in /*) f="$l" ;; *) f="$(cd "$(dirname "$f")" && pwd)/$l" ;; esac
    done
    printf '%s\n' "$f"
  }

  for b in npm npx; do
    bin_path="$(command -v "$b" || true)"
    [ -n "$bin_path" ] || continue
    bin_dir="$(dirname "$bin_path")"

    if ! grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
      ln -sf "$(resolve "$bin_path")" "$REAL_DIR/$b"
      rm -f "$bin_path"
    fi

    cat > "$bin_dir/$b" <<EOF
#!/bin/sh
# socket-wrapper: fail-closed perimeter for $b (Node $v)
CMD="\$1"
case "\$CMD" in
  install|i|add|ci|update|up)
    exec env PATH="$REAL_DIR:\$PATH" socket $b "\$@"
    ;;
  *)
    exec env PATH="$REAL_DIR:\$PATH" "$REAL_DIR/$b" "\$@"
    ;;
esac
EOF
    chmod +x "$bin_dir/$b"
  done
  echo "   ✅ Wrappers installed for $v"
}

# --- Execution ---
echo "🚀 Starting mass Zero-Trust deployment..."

# Get all installed versions
INSTALLED_VERSIONS=$(nvm ls --no-colors | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')

for v in $INSTALLED_VERSIONS; do
  secure_node_version "$v"
done

# --- Global Side-Door Closing ---
echo "🚪 Closing yarn/pnpm side-doors..."
echo "enableScripts: false" >> ~/.yarnrc.yml 2>/dev/null || true
pnpm config set ignore-scripts true --global 2>/dev/null || true
corepack disable 2>/dev/null || true

# --- Global Git Hooks ---
echo "🪝 Configuring global Git hooks..."
mkdir -p ~/.git-templates/hooks
cat > ~/.git-templates/hooks/post-merge <<'EOF'
#!/bin/sh
if [ -f package.json ] && grep -q '"lavamoat"' package.json; then
  npx --yes @lavamoat/allow-scripts
fi
EOF
chmod +x ~/.git-templates/hooks/post-merge
git config --global init.templatedir '~/.git-templates'

# Return to initial version
nvm use "$STARTING_VERSION" > /dev/null

echo "🎯 Done! All Node versions secured. Remember to 'nvm use' your project version to refresh paths."
