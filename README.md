# Devbox Skill for OpenClaw

An [OpenClaw](https://github.com/openclaw/openclaw) skill that provides self-registering development containers with web-accessible VSCode, VNC, browser automation, and multi-app routing via Traefik.

## Features

- **Self-registering containers** — auto-assigns ID, writes Traefik routes, builds `APP_URL_*` env vars
- **VSCode Web** — browser-based IDE on port 8000
- **noVNC** — visual desktop access on port 8002
- **Chromium CDP** — headless browser automation on port 9222
- **5 app slots** — routed via Traefik with configurable tags (e.g. `api`, `kiosk`, `console`)
- **Project setup scripts** — `.openclaw/setup.sh` convention for automated repo setup
- **nvm** — Node version management, reads `.nvmrc` automatically

## Architecture

```
┌─────────────────────────────────────────────┐
│  Devbox Container (openclaw-devbox:latest)  │
│                                             │
│  ┌─────────┐ ┌───────┐ ┌────────────────┐  │
│  │ VSCode  │ │ noVNC │ │ Chromium (CDP) │  │
│  │ :8000   │ │ :8002 │ │ :9222          │  │
│  └─────────┘ └───────┘ └────────────────┘  │
│                                             │
│  App 1 :8003  App 2 :8004  App 3 :8005     │
│  App 4 :8006  App 5 :8007                  │
└──────────────────┬──────────────────────────┘
                   │
            ┌──────┴──────┐
            │   Traefik   │  ← auto-configured by entrypoint
            └──────┬──────┘
                   │
         https://{tag}-{id}.{domain}
```

## Quick Start

### 1. Build the image

```bash
docker build -t openclaw-devbox:latest -f scripts/Dockerfile scripts/
```

### 2. Configure OpenClaw

Add the devbox agent to your `openclaw.json`:

```json5
{
  agents: {
    list: [
      {
        id: "main",
        default: true,
        subagents: { allowAgents: ["devbox"] },
        sandbox: { mode: "off" }
      },
      {
        id: "devbox",
        name: "Devbox Agent",
        sandbox: {
          mode: "all",
          workspaceAccess: "none",
          scope: "session",
          browser: { enabled: true, cdpPort: 9222 },
          docker: {
            image: "openclaw-devbox:latest",
            readOnlyRoot: false,
            network: "traefik",
            env: {
              ENABLE_VNC: "true",
              ENABLE_VSCODE: "true",
              DEVBOX_DOMAIN: "your.domain.com",
              APP_TAG_1: "api",
              APP_TAG_2: "kiosk",
              APP_TAG_3: "console",
              APP_TAG_4: "app4",
              APP_TAG_5: "app5",
              GITHUB_TOKEN: "ghp_..."
            },
            binds: [
              "/path/to/.devbox-counter:/shared/.devbox-counter:rw",
              "/path/to/traefik/dynamic:/traefik:rw"
            ]
          }
        }
      }
    ]
  }
}
```

### 3. Set up prerequisites

```bash
# Create Traefik network
docker network create traefik

# Create counter file (world-writable for sandbox containers)
echo "0" > /path/to/.devbox-counter
chmod 666 /path/to/.devbox-counter

# Ensure Traefik dynamic dir is world-writable
chmod 777 /path/to/traefik/dynamic
```

### 4. Spawn a devbox

Just ask your OpenClaw agent to spin up a devbox — the skill handles everything.

## Self-Registration

Each container's entrypoint automatically:

1. Reads and increments the shared counter → assigns `DEVBOX_ID`
2. Builds `APP_URL_1..5`, `VSCODE_URL`, `NOVNC_URL` from tags + domain + ID
3. Writes env vars to `/etc/profile.d/devbox.sh` (available in all shells)
4. Writes Traefik config to `/traefik/devbox-{id}.yml`

No manual routing or ID assignment needed.

## Project Setup Scripts

Projects can include `.openclaw/setup.sh` for automated setup inside a devbox:

```bash
#!/bin/bash
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

nvm install && nvm use
npm install

cp template.env .env
sed -i "s/PORT=.*/PORT=$APP_PORT_1/" .env

tmux new -d -s my-server "source /root/.nvm/nvm.sh; nvm use; npm run dev; exec \$SHELL"
echo "Running at $APP_URL_1"
```

See [setup-script-guide.md](references/setup-script-guide.md) for full conventions.

## Environment Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `DEVBOX_ID` | entrypoint | Auto-assigned sequential ID |
| `APP_URL_1..5` | entrypoint | Full external URLs |
| `APP_PORT_1..5` | Dockerfile | Internal ports (8003-8007) |
| `APP_TAG_1..5` | config | Route tags |
| `DEVBOX_DOMAIN` | config | Base domain |
| `GITHUB_TOKEN` | config | GitHub PAT |
| `VSCODE_URL` | entrypoint | VSCode Web URL |
| `NOVNC_URL` | entrypoint | noVNC URL |

## Important Notes

- Sandbox containers run with **all Linux capabilities dropped** (`CapDrop: ALL`). Bind-mounted files/dirs must be world-writable.
- Wildcard DNS (`*.your.domain.com`) must point to your server.
- Traefik must be configured with a file provider watching the dynamic config directory.

## License

MIT
