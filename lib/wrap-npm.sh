#!/usr/bin/env bash
# lib/wrap-npm.sh — Layer 2: replace npm/npx at their canonical path with a
# fail-closed Socket wrapper. Sourced by setup-zero-trust.sh; defines
# install_npm_wrapper(). This file is linked directly from setup.en.md /
# setup.ru.md (Step 3) — it is the only copy of this logic in the repo.

install_npm_wrapper() {
  local v="$1" REAL_DIR="$2"
  mkdir -p "$REAL_DIR"

  # portable symlink resolver (macOS readlink lacks -f)
  _nzt_resolve() {
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

    # stash the REAL binary (only if we haven't wrapped it already)
    if ! grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
      ln -sf "$(_nzt_resolve "$bin_path")" "$REAL_DIR/$b"
      rm -f "$bin_path"
    fi

    # This file is a sh/node polyglot. It must run correctly two ways:
    #   1. Executed directly (shell PATH lookup honors the #!/bin/sh shebang).
    #   2. Loaded as `node <this-file>` — @socketsecurity/cli's own npm-shadow
    #      logic finds "the real npm" by checking the file sitting next to the
    #      running node binary (path.dirname(process.execPath) + "/npm"), and
    #      spawns it via `node <that-path>`, bypassing the shebang entirely.
    # A plain shell script fails mode 2 with a SyntaxError (node tries to parse
    # `# socket-wrapper: ...` as JS). Line 2 below is valid in both languages:
    # sh sees `:` (no-op) then `; exec node "$0" "$@"`; node sees a string
    # literal followed by a `//` comment. The env-var guard breaks the
    # otherwise-infinite recursion when socket calls back into this same file.
    cat > "$bin_dir/$b" <<EOF
#!/bin/sh
":" //# ; exec node "\$0" "\$@"

'use strict';
// socket-wrapper: fail-closed perimeter for $b (Node $v)
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REAL_DIR = '$REAL_DIR';
const REAL_BIN = path.join(REAL_DIR, '$b');
const args = process.argv.slice(2);
const cmd = args[0];
const MUTATING = new Set(['install', 'i', 'add', 'ci', 'update', 'up']);

process.env.PATH = REAL_DIR + path.delimiter + process.env.PATH;

let result;
if (!process.env.__SOCKET_WRAPPER_ACTIVE__ && MUTATING.has(cmd)) {
  process.env.__SOCKET_WRAPPER_ACTIVE__ = '1';
  result = spawnSync('socket', ['$b', ...args], { stdio: 'inherit', env: process.env });
} else {
  result = spawnSync(REAL_BIN, args, { stdio: 'inherit', env: process.env });
}

if (result.error) {
  console.error('socket-wrapper: ' + result.error.message);
  process.exit(1);
}
if (result.signal) {
  process.kill(process.pid, result.signal);
} else {
  process.exit(result.status == null ? 1 : result.status);
}
EOF
    chmod +x "$bin_dir/$b"
  done
}
