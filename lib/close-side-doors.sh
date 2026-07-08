#!/usr/bin/env bash
# lib/close-side-doors.sh — Step 4: stop yarn/pnpm/corepack from being an
# escape hatch around the npm lockdown. Sourced by setup-zero-trust.sh;
# defines close_side_doors(). Linked directly from setup.en.md / setup.ru.md.

close_side_doors() {
  echo "🚪 Closing yarn/pnpm side-doors..."
  echo "enableScripts: false" >> ~/.yarnrc.yml 2>/dev/null || true
  pnpm config set ignore-scripts true --global 2>/dev/null || true
  corepack disable 2>/dev/null || true
}
