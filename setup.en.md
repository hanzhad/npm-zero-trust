### Step 1: Preparing the Tools

Install the main scanner and log in:

```bash
npm install -g @socketsecurity/cli
socket login

```

### Step 2: Creating the "Impenetrable Proxy"

Create a folder for protection and a proxy file that will act as the single entry point for `npm`.

1. **Create the folder:**

```bash
mkdir -p ~/.socket-wrapper

```

2. **Create the proxy script:**

```bash
nano ~/.socket-wrapper/npm

```

Paste the following code (replace `/usr/local/bin/socket` with the output of `which socket`):

```bash
#!/bin/bash
# Full path to your socket binary
SOCKET_PATH=$(which socket)

# Execute the check and installation
exec "$SOCKET_PATH" npm "$@"

```

3. **Make it executable:**

```bash
chmod +x ~/.socket-wrapper/npm

```

### Step 3: Global Isolation (Access Blocking)

Now, the "masterstroke": prevent the system from using the original `npm` directly.

1. **Disable auto-scripts:**

```bash
npm config set ignore-scripts true

```

2. **Block the system npm (physically):**

```bash
chmod -x $(which npm)

```

*(If you use `npx`, `yarn`, or `pnpm`, run `chmod -x` on them as well).*

### Step 4: Configuring the IDE (IntelliJ / WebStorm)

Your IDE needs to know that `npm` is now your proxy script.

1. Open **Settings -> Languages & Frameworks -> Node.js and npm**.
2. In the **Package manager** field, enter the path: `~/.socket-wrapper/npm`.
3. Now, the IDE will "knock" on your proxy, which will call Socket, and then invoke everything else.

### Step 5: Automation (Git Hooks)

To have LavaMoat automatically build necessary packages (Prisma, Next.js, etc.) without manual intervention:

1. **Create a template for all future projects:**

```bash
mkdir -p ~/.git-templates/hooks

```

2. **Create `post-merge`:**

```bash
nano ~/.git-templates/hooks/post-merge

```

Paste the following:

```bash
#!/bin/bash
if [ -f "package.json" ] && grep -q '"lavamoat"' package.json; then
  npx --yes allow-scripts
fi

```

3. **Set permissions and activate:**

```bash
chmod +x ~/.git-templates/hooks/post-merge
git config --global init.templatedir '~/.git-templates'

```

---

### What "Set It and Forget It" looks like now:

* **When you run `npm install`:** The command goes through your script, then to Socket, then to `npm`. Everything is secure.
* **If a virus or malicious script tries to run `npm` directly:** It will receive a "Permission denied" error (due to `chmod -x`), as it is unaware of your secret proxy script.
* **When you clone a new project:** You enter the directory, run `npm install` (via the proxy), and if a build is required, run `npx allow-scripts setup` once. From then on, everything works automatically via Git hooks.

**Your Status:** You are protected at the system kernel level. Every attempt to install packages must pass through the Socket.dev customs.

*If you need to update Node.js/npm, simply restore permissions with `chmod +x $(which npm)`, perform the update, and then block them again.*

---
