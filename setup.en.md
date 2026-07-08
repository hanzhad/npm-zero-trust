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

This relocates the **real** `npm`/`npx` into a private dir and puts a wrapper at the canonical path. Any caller — by name, by absolute path, from an IDE, or from an agent — hits the wrapper. The script is **idempotent** (safe to re-run).

```bash
#!/usr/bin/env bash
set -euo pipefail

REAL_DIR="$HOME/.npm-real/bin"
mkdir -p "$REAL_DIR"

# portable symlink resolver (macOS readlink lacks -f)
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
  [ -n "$bin_path" ] || { echo "skip: $b not found"; continue; }
  bin_dir="$(dirname "$bin_path")"

  # 1) stash the REAL binary (only if we haven't wrapped it already)
  if ! grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
    ln -sf "$(resolve "$bin_path")" "$REAL_DIR/$b"   # absolute link to real launcher
    rm -f "$bin_path"
  fi

  # 2) install the wrapper at the canonical path
  cat > "$bin_dir/$b" <<EOF
#!/bin/sh
# socket-wrapper: fail-closed perimeter for $b
# Put the real npm first so 'socket' finds it (and we don't recurse into ourselves).
exec env PATH="\$HOME/.npm-real/bin:\$PATH" socket $b "\$@"
EOF
  chmod +x "$bin_dir/$b"
  echo "wrapped: $bin_dir/$b  (real -> $REAL_DIR/$b)"
done
```

**Optional maximum hardening** — make the wrapper un-removable by the user/agent:

```bash
sudo chown root:wheel "$(command -v npm)" "$(command -v npx)"
sudo chmod 755        "$(command -v npm)" "$(command -v npx)"
```

Verify the wrapper is in place:

```bash
head -3 "$(command -v npm)"        # -> #!/bin/sh  ... socket-wrapper ...
npm install --dry-run left-pad     # should route through Socket
```

---

## Step 4 — Close the side doors

Fail-closed collapses if an agent just picks another package manager.

```bash
# yarn (global):
echo "enableScripts: false" >> ~/.yarnrc.yml
# pnpm:
pnpm config set ignore-scripts true --global 2>/dev/null || true
# stop corepack from provisioning a "clean" yarn/pnpm:
corepack disable 2>/dev/null || true
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

**Global hook so it runs itself after every `git pull`:**

```bash
mkdir -p ~/.git-templates/hooks
cat > ~/.git-templates/hooks/post-merge <<'EOF'
#!/bin/sh
# run allow-scripts only for projects that opted in
if [ -f package.json ] && grep -q '"lavamoat"' package.json; then
  npx --yes @lavamoat/allow-scripts
fi
EOF
chmod +x ~/.git-templates/hooks/post-merge
git config --global init.templatedir '~/.git-templates'
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

* **Residual bypass:** `node /path/to/npm-cli.js` skips the wrapper. Acceptable for the threat model (careless human + AI agent), not against a determined attacker already executing code locally.
* **`brew upgrade node` restores the original npm** and removes the wrapper. Re-run Step 3 (it's idempotent), or add a brew post-upgrade hook.
* **Fail-closed = unavailable on failure.** No network / expired `socket login` / rate-limit ⇒ installs are blocked by design. Break-glass for the admin: the real binary still lives at `~/.npm-real/bin/npm`.
* **Always commit your lockfile and use `npm ci`** in CI — it installs exactly from the lockfile and fails on drift.

### Rollback

```bash
for b in npm npx; do
  bin_path="$(command -v "$b")"; bin_dir="$(dirname "$bin_path")"
  if grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
    rm -f "$bin_path"
    cp -P "$HOME/.npm-real/bin/$b" "$bin_dir/$b"   # restore real launcher
  fi
done
npm config delete ignore-scripts --location=global
git config --global --unset init.templatedir || true
```

---
