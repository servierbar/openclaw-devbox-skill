---
name: devbox
description: Manage development environment containers (devboxes) with web-accessible VSCode, VNC, and app routing via Traefik. Use when the user asks to create, start, stop, list, or manage devboxes/dev environments, spin up a development container, set up a coding sandbox, or configure the devbox infrastructure for the first time (onboarding).
---

# Devbox Skill

Devboxes are OpenClaw sandbox containers running a custom image with VSCode Web, noVNC, Chromium (CDP), and up to 5 app ports routed via Traefik.

OpenClaw manages the container lifecycle. Containers **self-register** — the entrypoint auto-assigns an ID, writes Traefik routes, and builds `APP_URL_*` env vars. The main agent just spawns and reports URLs.

## File Locations

All scripts and config live in the skill's `scripts/` directory. Resolve paths relative to this SKILL.md's parent directory.

Key files:
- `scripts/Dockerfile` + `scripts/entrypoint.sh` — devbox image
- `scripts/stop-devbox.sh` — clean up Traefik config when stopping a devbox
- `scripts/.devbox-counter` — sequential ID counter (bind-mounted into containers, created by onboarding)

## Architecture

- **Agent id:** `devbox` (configured in openclaw.json)
- **Sandbox mode:** `all` / `scope: session` — one container per session
- **Image:** `openclaw-devbox:latest` (Debian bookworm + Node 24 + VSCode + Chromium + VNC)
- **Network:** `traefik` (for routing and git access)
- **Browser:** `sandbox.browser.enabled: true`, CDP on port 9222 (built into the image)
- **GitHub token:** available as `$GITHUB_TOKEN` env var

### Self-Registration (entrypoint)

The container's entrypoint automatically:
1. Reads and increments `/shared/.devbox-counter` → assigns `DEVBOX_ID`
2. Builds `APP_URL_1..5`, `VSCODE_URL`, `NOVNC_URL` from tags + domain + ID
3. Writes `/etc/devbox.env` and `/etc/profile.d/devbox.sh` (available in all shells)
4. Writes Traefik config to `/traefik/devbox-{id}.yml` (Traefik auto-picks it up)

### Bind Mounts

Two host paths are bind-mounted into each devbox container:

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `/root/openclaw/workspace/skills/devbox/scripts/.devbox-counter` | `/shared/.devbox-counter:rw` | ID counter |
| `/root/traefik/dynamic` | `/traefik:rw` | Traefik dynamic config |

**Important:** Both paths must be world-writable (`chmod 666` / `chmod 777`) because sandbox containers run with `CapDrop: ALL` (no Linux capabilities).

## Prerequisites Check

Before any devbox operation, verify:

1. Docker available: `docker info`
2. Image exists: `docker images openclaw-devbox:latest`
3. Traefik network exists: `docker network ls | grep traefik`
4. Counter file exists and is writable: `ls -la scripts/.devbox-counter`
5. Traefik dynamic dir is writable

If any fails, run the **onboarding flow**.

## Onboarding Flow

1. **Docker access** — Verify Docker CLI and socket
2. **Build the image** — `docker build -t openclaw-devbox:latest -f scripts/Dockerfile scripts/`
3. **Traefik network** — `docker network create traefik` (if not exists)
4. **Traefik** — Confirm Traefik with file provider watching `/root/traefik/dynamic/`
5. **Domain** — User provides domain with wildcard DNS `*.domain` pointing to server
6. **Counter file** — `echo "0" > scripts/.devbox-counter && chmod 666 scripts/.devbox-counter`
7. **Traefik dir perms** — Ensure world-writable: `chmod 777 /root/traefik/dynamic` (run via Docker if needed)
8. **Update openclaw.json** — Set sandbox config with env vars, binds, and browser
9. **Test** — Spawn a devbox, verify self-registration and URLs

## Workflow: Spawn a Devbox

### Step 1: Spawn subagent (main agent)

```python
sessions_spawn(
    agentId="devbox",
    label="devbox-{task_name}",
    task="Your task description. GitHub token is in $GITHUB_TOKEN. Env vars (DEVBOX_ID, APP_URL_*, etc.) are in your shell."
)
```

That's it! The container self-registers. No manual ID assignment or Traefik setup needed.

### Step 2: Report URLs to user (main agent)

Read the counter to know the assigned ID, then report:

```bash
DEVBOX_ID=$(cat scripts/.devbox-counter)
```

- VSCode: `https://vscode-{id}.{domain}`
- noVNC: `https://novnc-{id}.{domain}/vnc.html`
- App URLs: `https://{tag}-{id}.{domain}` (api, kiosk, console, app4, app5)

### Step 3: Cleanup (when done)

```bash
# Remove Traefik config (container cleanup is automatic when session ends)
bash scripts/stop-devbox.sh "$DEVBOX_ID"
```

Or manually remove the Traefik config from the host's dynamic dir.

## Environment Variables

### Static (set in openclaw.json sandbox.docker.env)

| Variable | Example | Description |
|----------|---------|-------------|
| `GITHUB_TOKEN` | `ghp_...` | GitHub PAT for cloning |
| `DEVBOX_DOMAIN` | `oc.servier.bar` | Base domain |
| `APP_TAG_1..5` | `api`, `kiosk`, ... | Route tags |
| `ENABLE_VNC` | `true` | Enable noVNC |
| `ENABLE_VSCODE` | `true` | Enable VSCode Web |

### Dynamic (built by entrypoint, available in all shells)

| Variable | Example | Description |
|----------|---------|-------------|
| `DEVBOX_ID` | `1` | Auto-assigned sequential ID |
| `APP_URL_1..5` | `https://api-1.oc.servier.bar` | Full URLs per app slot |
| `APP_PORT_1..5` | `8003..8007` | Internal ports |
| `VSCODE_URL` | `https://vscode-1.oc.servier.bar` | VSCode Web URL |
| `NOVNC_URL` | `https://novnc-1.oc.servier.bar/vnc.html` | noVNC URL |

### Ports

| Port | Service |
|------|---------|
| 8000 | VSCode Web |
| 8002 | noVNC |
| 9222 | Chrome DevTools Protocol (CDP) |
| 8003 | App slot 1 (api) |
| 8004 | App slot 2 (kiosk) |
| 8005 | App slot 3 (console) |
| 8006 | App slot 4 |
| 8007 | App slot 5 |

## App Tag Mapping

| Slot | Tag | Port | Purpose |
|------|-----|------|---------|
| 1 | api | 8003 | Backend API |
| 2 | kiosk | 8004 | Kiosk frontend |
| 3 | console | 8005 | Admin console |
| 4 | app4 | 8006 | Available |
| 5 | app5 | 8007 | Available |

## Browser

The devbox agent has browser access via Chromium CDP (port 9222). Config: `sandbox.browser.enabled: true`. The subagent can use the `browser` tool to navigate, screenshot, and interact with apps running inside the container (use `http://localhost:{port}`).

## Project Setup Scripts

Projects can include `.openclaw/setup.sh` that runs inside the devbox. It has access to all env vars (`APP_URL_*`, `APP_PORT_*`, `DEVBOX_ID`, etc.) via `/etc/profile.d/devbox.sh`.

See `references/setup-script-guide.md` for conventions.

### Known Projects

| Repo | Branch | Slot | Setup |
|------|--------|------|-------|
| `servierbar/sb-bend` | dev | 1 (api, 8003) | `.openclaw/setup.sh` — NestJS API, Stripe CLI |
| `servierbar/sb-kiosk` | dev | 2 (kiosk, 8004) | `.openclaw/setup.sh` — Next.js kiosk frontend |
