# Zero-Trust npm — Technical Setup (Fail-Closed)

**Philosophy:** the safe path must be the *only* path. We do **not** rely on shell aliases or IDE settings — a forgetful user or an AI agent would just call `npm` another way. Enforcement lives on two layers nothing can route around:

1. **npm's own config** (`ignore-scripts`) — read on every invocation.
2. **The `npm` binary location** — the file at the canonical path *is* the wrapper.

> Why not `chmod -x $(which npm)`? It doesn't send anything through customs — it just makes npm fail, breaks its own wrapper, resets on every npm/node update, and is bypassed by `node npm-cli.js`. Skip it.

Tested on macOS (Homebrew Node) + zsh. Adjust paths for Linux.

---

## Step 1 — Install the Socket scanner

```bash
npm install -g @socketsecurity/cli
socket login
```

`socket npm` / `socket npx` are drop-in wrappers that scan the dependency tree before packages are fetched.

> **Free-tier scope:** known-malicious packages are **blocked**; AI-flagged *potential* malware is **warned** on. That's why Layer 1 (below) sits underneath as the hard stop.

---

## Step 2 — Layer 1: global lockdown (un-bypassable execution customs)

```bash
npm config set ignore-scripts true --location=global
```

npm reads this config **no matter who runs it** — terminal, IDE, agent, subprocess, or absolute path. Malicious `postinstall` scripts (the #1 supply-chain vector) will not execute. Only ~2% of packages use lifecycle scripts; Layer 3 re-enables the legitimate ones.

Verify:

```bash
npm config get ignore-scripts --location=global   # -> true
```

---

## Step 3 — Layer 2: replace the npm binary with the Socket wrapper (fail-closed perimeter)

This relocates the **real** `npm`/`npx` into a private, per-Node-version dir and puts a wrapper at the canonical path. Any caller — by name, by absolute path, from an IDE, or from an agent — hits the wrapper. Non-mutating commands (`run`, `ls`, `--version`, …) go straight to the real binary; only `install`/`i`/`add`/`ci`/`update`/`up` route through `socket npm`. The logic is **idempotent** (safe to re-run).

The wrapper file is an **sh/Node polyglot**: `@socketsecurity/cli` resolves "the real npm" by checking the file sitting next to the running `node` binary and re-invokes it via `node <that-path>`, bypassing shebangs entirely — so the wrapper has to parse as valid JavaScript too, or that self-invocation crashes with a `SyntaxError`. An env-var guard (`__SOCKET_WRAPPER_ACTIVE__`) stops Socket's own callback into this file from recursing forever.

This is the only copy of this logic in the repo — **[`lib/wrap-npm.sh`](lib/wrap-npm.sh)**. `setup-zero-trust.sh` downloads and sources it automatically on every run; to apply it by hand for the currently active Node version:

```bash
curl -fsSL https://raw.githubusercontent.com/hanzhad/npm-zero-trust/main/lib/wrap-npm.sh -o /tmp/wrap-npm.sh
source /tmp/wrap-npm.sh
install_npm_wrapper "$(node -v)" "$HOME/.npm-real/$(node -v)/bin"
```

**Optional maximum hardening** — make the wrapper un-removable by the user/agent:

```bash
sudo chown root:wheel "$(command -v npm)" "$(command -v npx)"
sudo chmod 755        "$(command -v npm)" "$(command -v npx)"
```

Verify the wrapper is in place:

```bash
head -5 "$(command -v npm)"        # -> #!/bin/sh  ... socket-wrapper ...
npm install --dry-run left-pad     # should route through Socket
```

---

## Step 4 — Close the side doors

Fail-closed collapses if an agent just picks another package manager.

Logic lives in **[`lib/close-side-doors.sh`](lib/close-side-doors.sh)**:

```bash
curl -fsSL https://raw.githubusercontent.com/hanzhad/npm-zero-trust/main/lib/close-side-doors.sh -o /tmp/close-side-doors.sh
source /tmp/close-side-doors.sh
close_side_doors
```

If `yarn` / `pnpm` / `bun` are installed, wrap them the same way as Step 3 (or remove them).

---

## Step 5 — Layer 3: automatic trusted builds (LavaMoat + Git hook)

With scripts off, legitimate builds (Prisma, Next.js, esbuild…) need an allow-list.

**Per project (once):**

```bash
npm i -D @lavamoat/allow-scripts
npx @lavamoat/allow-scripts setup   # writes ignore-scripts=true to the project .npmrc
npx @lavamoat/allow-scripts auto    # builds the allow-list in package.json (review it!)
```

**Global hook so it runs itself after every `git pull`** — logic lives in **[`lib/git-hooks.sh`](lib/git-hooks.sh)**:

```bash
curl -fsSL https://raw.githubusercontent.com/hanzhad/npm-zero-trust/main/lib/git-hooks.sh -o /tmp/git-hooks.sh
source /tmp/git-hooks.sh
configure_git_hooks
```

> The template applies to repos you `git init` / `git clone` **after** this. For existing repos, copy the hook into `.git/hooks/post-merge`.

---

## Step 6 — IDE (belt-and-suspenders, no longer load-bearing)

Because enforcement is at the binary + npm config, the IDE is already covered even if you skip this. Setting it just keeps the IDE's UI honest.

* IntelliJ / WebStorm: **Settings → Languages & Frameworks → Node.js and npm → Package manager** → point to the wrapped `npm` (its normal path is fine — it *is* the wrapper now).

---

## What "Set and Forget" looks like now

* **`npm install`** → wrapper → Socket scan → real npm, with lifecycle scripts off. Clean packages install; malicious ones are blocked.
* **An agent or forgetful user calls `npm` (any way)** → still hits the wrapper; `postinstall` still can't run (global `ignore-scripts`). No customs bypass.
* **Clone a project that needs builds** → run `allow-scripts setup` once; the Git hook handles it from then on.

---

## Honest limits & operations

* **Residual bypass:** calling the real launcher directly by its stashed path (`~/.npm-real/<node-version>/bin/npm`) skips the wrapper — the canonical `npm`/`npx` paths and `node <that-path>` are both covered, since the wrapper is a polyglot Socket itself can't route around. Acceptable for the threat model (careless human + AI agent), not against a determined attacker already executing code locally.
* **`brew upgrade node` restores the original npm** and removes the wrapper. Re-run Step 3 (it's idempotent), or add a brew post-upgrade hook.
* **Fail-closed = unavailable on failure.** No network / expired `socket login` / rate-limit ⇒ installs are blocked by design. Break-glass for the admin: the real binary still lives at `~/.npm-real/<node-version>/bin/npm`.
* **Always commit your lockfile and use `npm ci`** in CI — it installs exactly from the lockfile and fails on drift.

### Rollback

```bash
for v_dir in "$HOME"/.npm-real/*/; do
  v="$(basename "$v_dir")"
  for b in npm npx; do
    bin_path="$HOME/.nvm/versions/node/$v/bin/$b"
    if [ -f "$bin_path" ] && grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
      rm -f "$bin_path"
      cp -P "$v_dir/$b" "$bin_path"   # restore real launcher
    fi
  done
done
npm config delete ignore-scripts --location=global
git config --global --unset init.templatedir || true
```

---
