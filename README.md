# PRESENTATION: Zero-Trust npm Supply Chain Security

**"Set and Forget" Architecture for Local Machine Protection** 

---

### Slide 1: The "Security Tax" Problem

* **The Reality:** Developers reject complex daily security workflows.
* **The Goal:** Build an invisible security layer that ensures protection without hindering productivity.
* **The Concept:** "Set and Forget" — maximum isolation with zero friction.

---

### Slide 2: The Three-Layer "Fort Knox" Shield

A multi-layered defense architecture that operates automatically:

1. **The Perimeter (Socket Firewall):** Blocks malware before it touches the disk.
2. **The Lockdown (Global `ignore-scripts`):** Disables all hidden "post-install" scripts by default.
3. **The Autopilot (LavaMoat + Git Hooks):** Automated, verified build execution only for trusted dependencies.

---

### Slide 3: Layer 1 — The Perimeter (Socket SFW)

* **Tool:** [Socket.dev](https://socket.dev) CLI (Wrapper Mode).
* **Function:** Intercepts every `npm install` command. Scans dependency trees in real-time for malware, typosquatting, and unauthorized network calls.
* **Outcome:** Malicious code is blocked in the cloud; nothing reaches the hard drive.
* **Configuration:** `socket sfw install` (one-time setup).

---

### Slide 4: Layer 2 — The Lockdown (Global Enforcement)

* **Action:** `npm config set ignore-scripts true`
* **Purpose:** Even if a "clean" package is compromised, it cannot execute arbitrary code (miners, info-stealers) on your machine.
* **Security:** Physical revocation of execution rights via `sudo chmod -x $(which npm)`.
* **Result:** Only your designated proxy script can trigger the package manager.

---

### Slide 5: Layer 3 — The Autopilot (LavaMoat + Git Hooks)

* **Challenge:** How to build projects (e.g., Prisma, Next.js) if scripts are blocked?
* **Solution:** `@lavamoat/allow-scripts`.
* **Automation:**
* **Git Hooks:** `post-merge` hook automatically triggers security checks after `git pull`.
* **User Effort:** Run `npx allow-scripts setup` exactly once per project.


* **Efficiency:** The system builds your trusted binaries automatically in the background.

---

### Slide 6: The "Set and Forget" Implementation

Three steps to system-wide immunity:

1. **`npm config set ignore-scripts true`** (Global Lockdown).
2. **`socket sfw install`** (Cloud-based perimeter).
3. **`git config --global init.templatedir '~/.git-templates'`** (Automated security for all future repositories).

---

### Slide 7: Developer Workflow

1. **Work as usual:** Run `npm install` or `git pull`.
2. **Threat Detected:** Socket immediately terminates the installation; code never hits the disk.
3. **Trusted Project:** The system automatically builds dependencies using your pre-approved whitelist.
4. **Security ROI:** Zero chance of credential theft, minimal configuration overhead, absolute process transparency.

---

### Slide 8: Summary

* Security is not a set of restrictions, but an architectural process.
* "Lazy Security" is more reliable than manual control because it removes the human factor.
* Your machine is fully secured: protection integrated at the Git, NPM, and OS-shell levels.

---

## Setup Instructions

* [Follow the Technical Setup Guide (English)](setup.en.md)
* [Follow the Technical Setup Guide (Russian)](setup.ru.md)

---
