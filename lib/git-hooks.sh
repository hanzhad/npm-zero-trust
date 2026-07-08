#!/usr/bin/env bash
# lib/git-hooks.sh — Step 5: LavaMoat allow-scripts runs itself after every
# `git pull`, so trusted builds don't break with scripts disabled. Sourced by
# setup-zero-trust.sh; defines configure_git_hooks(). Linked directly from
# setup.en.md / setup.ru.md.

configure_git_hooks() {
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
}
