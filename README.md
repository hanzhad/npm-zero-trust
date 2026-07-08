# PRESENTATION: Zero-Trust npm Supply Chain Security

**Fail-Closed, "Set and Forget" Architecture for Local Machine Protection**

---

### Slide 1: The "Security Tax" Problem

* **The Reality:** Developers reject complex daily security workflows — and AI coding agents (Claude Code, Copilot, etc.) run package managers on your behalf without asking.
* **The Goal:** An invisible security layer that protects without hindering productivity.
* **The Concept:** *Fail-closed* — the safe path is the **only** path. If someone forgets, ignores the config, or an agent calls `npm` directly, it still cannot bypass customs.

---

### Slide 2: Where to Enforce (the key idea)

Security that lives in a **shell alias** or an **IDE setting** is trivially bypassed — a forgetful user or an agent just calls `npm` another way. So we enforce on two layers that no invocation can route around:

1. **npm's own config** — read on *every* invocation (by name, by absolute path, from an IDE, from an agent, from a subprocess).
2. **The `npm` binary location itself** — the file at the canonical path *is* the security wrapper.

> ❌ We do **not** use `chmod -x $(which npm)`. It doesn't route through customs — it just makes npm fail; it breaks its own wrapper; it resets on every npm/node update; and it's bypassed by `node npm-cli.js`. It was security theater.

---

### Slide 3: The Three-Layer Shield

1. **Lockdown (global `ignore-scripts`)** — disables all lifecycle scripts by default. *Un-bypassable execution customs.*
2. **Perimeter (Socket wrapper at the npm path)** — every install is scanned before packages hit the disk. *Fail-closed perimeter customs.*
3. **Autopilot (LavaMoat + Git hooks)** — trusted, allow-listed builds run automatically so nothing breaks.

---

### Slide 4: Layer 1 — Lockdown (do this first)

* **Action:** `npm config set ignore-scripts true --location=global`
* **Why global:** npm reads its config no matter *who* or *how* it is invoked — terminal, IDE, agent, subprocess, absolute path. So malicious `postinstall` scripts (the #1 supply-chain vector, e.g. the 2025 Shai-Hulud worm) never execute.
* **Only ~2% of packages** use lifecycle scripts, so almost nothing breaks — and Layer 3 re-enables the legitimate ones.

---

### Slide 5: Layer 2 — Perimeter (Socket)

* **Tool:** [Socket.dev](https://socket.dev) CLI (`socket npm` / `socket npx` drop-in scanner).
* **Function:** Scans the dependency tree via Socket before packages are fetched — malware, typosquatting, install-script exfiltration.
* **Fail-closed enforcement:** the `npm`/`npx` binaries at their canonical path are **replaced by a wrapper**; the real binaries are relocated to a private dir. Any caller — name, absolute path, IDE, or agent — hits the wrapper.
* **Honest scope (Free tier):** known-malicious packages are **blocked**; AI-flagged *potential* malware is **warned** on. Not a silver bullet — that's why Layer 1 exists underneath.

---

### Slide 6: Layer 3 — Autopilot (LavaMoat + Git Hooks)

* **Challenge:** with scripts off, how do Prisma / Next.js / esbuild build?
* **Solution:** `@lavamoat/allow-scripts` — deny all, then allow-list only what you approve (stored in `package.json`).
* **Automation:** a global `post-merge` Git hook runs `allow-scripts` after every `git pull`, so trusted binaries build themselves in the background.
* **User effort:** run `npx @lavamoat/allow-scripts setup` once per project, review the allow-list when dependencies change.

---

### Slide 7: The "Set and Forget" Implementation

1. **`npm config set ignore-scripts true --location=global`** — execution lockdown.
2. **Replace `npm`/`npx` with the Socket wrapper** — fail-closed perimeter (see setup guide).
3. **`git config --global init.templatedir '~/.git-templates'`** — auto-build hook for all future repos.

Full copy-paste scripts: **[English](setup.en.md)** · **[Russian](setup.ru.md)**.

---

### Slide 8: Honest Limits (read before trusting this)

* **`node npm-cli.js` bypasses the wrapper.** Fine for the threat model (careless human + AI agent), not against a determined attacker already running code on your box.
* **`brew upgrade node` restores the original npm** and removes the wrapper → the setup is idempotent; re-run it (or wire a brew post-upgrade hook).
* **Fail-closed = unavailable on failure.** No network / expired `socket login` / rate-limit ⇒ installs are **blocked**. That's the deal ("blocked beats infected"). A non-obvious break-glass (`~/.npm-real/bin/npm`) stays for the admin.
* **Side doors:** `yarn` / `pnpm` / `bun` / `corepack` must be closed too, or an agent just uses those (covered in the setup guide).

---

### Slide 9: Summary

* Security is an **architectural property**, not a daily checklist.
* "Lazy security" is reliable because it makes the safe path the **default and only** path — it doesn't depend on anyone remembering anything.
* Enforcement lives at the **npm config + the binary**, not in aliases or IDE settings — so IDEs, agents, and forgetful humans all pass through customs.

---

## Setup Instructions

* [Technical Setup Guide (English)](setup.en.md)
* [Technical Setup Guide (Russian)](setup.ru.md)


Auto setup
```
curl -sSL https://raw.githubusercontent.com/hanzhad/npm-zero-trust/main/setup-zero-trust.sh > ~/setup-zero-trust.sh && chmod +x ~/setup-zero-trust.sh && ~/setup-zero-trust.sh && rm ~/setup-zero-trust.sh
```

---
