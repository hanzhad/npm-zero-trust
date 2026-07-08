#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Initializing Zero-Trust architecture for npm..."

# --- Step 1: Install Socket CLI ---
echo "📦 Installing @socketsecurity/cli..."
# If npm is already wrapped, use the direct path to ensure reliability
if command -v npm | grep -q "npm-real"; then
  npm install -g @socketsecurity/cli@latest
else
  # If this is a clean Node installation
  "$(command -v npm)" install -g @socketsecurity/cli@latest
fi

echo "🔑 Waiting for Socket CLI authorization..."
echo "⚠️ IMPORTANT: When prompted for 'system-wide policies', select 'No'."
echo "⚠️ IMPORTANT: When prompted for 'bash tab completion', select 'No'."
socket login

# --- Step 2: Global script lockdown ---
echo "🛑 Disabling global postinstall scripts..."
npm config set ignore-scripts true --location=global

# --- Step 3: Install Smart Wrappers ---
echo "🛡️ Configuring isolated routing for binaries..."
REAL_DIR="$HOME/.npm-real/bin"
mkdir -p "$REAL_DIR"

# Portable symlink resolver
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
  [ -n "$bin_path" ] || { echo "Skip: $b not found"; continue; }
  bin_dir="$(dirname "$bin_path")"

  # Stash the REAL binary (only if we haven't wrapped it already)
  if ! grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
    ln -sf "$(resolve "$bin_path")" "$REAL_DIR/$b"
    rm -f "$bin_path"
  fi

  # Install the wrapper at the canonical path
  cat > "$bin_dir/$b" <<EOF
#!/bin/sh
# socket-wrapper: fail-closed perimeter for $b
# Smart routing: only route package-modifying commands through 'socket'.
CMD="\$1"
case "\$CMD" in
  install|i|add|ci|update|up)
    exec env PATH="\$HOME/.npm-real/bin:\$PATH" socket $b "\$@"
    ;;
  *)
    exec env PATH="\$HOME/.npm-real/bin:\$PATH" "\$HOME/.npm-real/bin/$b" "\$@"
    ;;
esac
EOF
  chmod +x "$bin_dir/$b"
  echo "✅ Wrapper installed: $bin_dir/$b"
done

# --- Step 4: Close the side doors ---
echo "🚪 Blocking yarn, pnpm, and corepack side-doors..."
echo "enableScripts: false" >> ~/.yarnrc.yml
pnpm config set ignore-scripts true --global 2>/dev/null || true
corepack disable 2>/dev/null || true

# --- Step 5: Setup LavaMoat Git Hooks ---
echo "🪝 Configuring global Git hooks for LavaMoat..."
mkdir -p ~/.git-templates/hooks
cat > ~/.git-templates/hooks/post-merge <<'EOF'
#!/bin/sh
# Run allow-scripts only for projects that opted in
if [ -f package.json ] && grep -q '"lavamoat"' package.json; then
  npx --yes @lavamoat/allow-scripts
fi
EOF
chmod +x ~/.git-templates/hooks/post-merge
git config --global init.templatedir '~/.git-templates'

echo "🎯 Done! Zero-Trust architecture successfully applied to the current Node.js version."
