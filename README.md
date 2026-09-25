# code-server + opencode

Docker image with [code-server](https://github.com/coder/code-server) and [opencode](https://opencode.ai) preinstalled, rebuilt automatically whenever either publishes a new release. The image is published to `ghcr.io/maksimstojkovic/code-server` for `linux/amd64` and `linux/arm64`.

## Features

- [opencode](https://opencode.ai) CLI installed and pinned
- vim, python3, pip and venv preinstalled
- Select-to-copy works in the browser terminal
- Terminal Ctrl+shortcuts reach the shell (nano, TUI apps), copy/paste via `Ctrl+Shift+C/V`
- Workspace trust disabled, no welcome screen or AI UI
- Optional opencode web server in the same container

## Quick start

```bash
git clone https://github.com/maksimstojkovic/code-server
cd code-server
cp .env.example .env   # adjust to taste
docker compose pull && docker compose up -d
```

Open `http://localhost:8080`. There is no login screen by default (`AUTH=none`); set `AUTH=password` and `PASSWORD` in `.env` if you want one.

## Configuration

Copy `.env.example` to `.env` and adjust. All variables are optional.

| Variable | Default | Description |
|---|---|---|
| `PUID` / `PGID` | `1000` / `1000` | Runtime user/group of code-server. Changing after data exists re-chowns the home mount on the next start. `PUID=0` is not supported |
| `AUTH` | `none` | `none` — no login screen; `password` — code-server login screen |
| `PASSWORD` | *(unset)* | Login password when `AUTH=password`; overrides the generated one in `config.yaml` |
| `DEFAULT_WORKSPACE` | `/home/coder/workspace` | Folder code-server opens on startup (created if missing) |
| `CODE_SERVER_PORT` | `8080` | code-server port, inside the container and on the host |
| `TZ` | `Australia/Sydney` | Container timezone |
| `DOCKER_USER` | `coder` | Cosmetic username inside the container (shell prompt, sudo) |
| `OPENCODE_WEB` | `false` | Set `true` to run the opencode web server (`opencode serve`) alongside code-server |
| `OPENCODE_WEB_PORT` | `4096` | opencode web server port, inside the container and on the host |
| `OPENCODE_WEB_HOSTNAME` | `0.0.0.0` | Bind address for the opencode web server |
| `OPENCODE_SERVER_PASSWORD` | *(unset)* | Password for the opencode web server (recommended; unsecured without it) |
| `OPENROUTER_API_KEY` | *(unset)* | OpenRouter API key; opencode reads it automatically (no manual `/connect` setup) |
| `OPENCODE_MODEL` | `openrouter/z-ai/glm-5.3-flash` | Default model; applied on every start (changing it and restarting updates the default). To default to a 9Router model, use `9router/<model>` |
| `OPENCODE_ZDR` | `true` | Zero-data-retention on OpenRouter (sends `provider.zdr=true` per request, restricting to non-retaining endpoints). Set `false` to allow providers that may retain data |
| `N9ROUTER_BASE_URL` | *(unset)* | Enables [9Router](https://github.com/nightwalker89/n9router) as an OpenAI-compatible opencode provider (base URL incl. `/v1`, e.g. `http://host:20128/v1`) |
| `N9ROUTER_API_KEY` | *(unset)* | 9Router dashboard API key |
| `N9ROUTER_MODEL` | `openrouter/glm-5.3-flash` | 9Router model ID. Becomes the default model when 9Router is enabled (`N9ROUTER_BASE_URL` set) |
| `N9ROUTER_AUTO_MODELS` | `true` | Sync the full 9Router model list (`GET /models`) into opencode at startup so any model can be selected |

> **9Router token compression:** 9Router's `/v1/compress` endpoint (RTK/headroom) auto-compresses `tool_result` content, saving ~20–40% tokens. It's handled automatically by 9Router — no extra opencode config needed.
| `TAVILY_API_KEY` | *(unset)* | Enables the Tavily web-search MCP server in opencode when set |
| `TAVILY_MCP_URL` | `https://mcp.tavily.com/mcp` | Tavily MCP server URL |
| `OUTLINE_API_KEY` | *(unset)* | Enables the Outline notes MCP server when set |
| `OUTLINE_MCP_URL` | `https://outline.example.com/mcp` | Outline MCP server URL (set to your instance). `/mcp` must bypass any SSO redirect - the API token does the auth |
| `ACTUAL_MCP_TOKEN` | *(unset)* | Enables the Actual Budget MCP server when set (Bearer token from actual-mcp-server's `MCP_SSE_AUTHORIZATION`) |
| `ACTUAL_MCP_URL` | `http://actual-mcp-server:3600/http` | Actual MCP server URL (your actual-mcp-server instance, streamable HTTP) |

Advanced: `BIND_ADDR` overrides the full listen address (`host:port`) of code-server.

## Updates

A GitHub Actions workflow checks for new code-server and opencode releases every 6 hours. When either changes, it bumps the pins in `versions.env`, rebuilds the image and pushes it to GHCR. To apply:

```bash
git pull && docker compose pull && docker compose up -d
```

## Networking

- code-server listens on `0.0.0.0:8080` (see `CODE_SERVER_PORT`), with password auth off by default — keep it behind a reverse proxy or VPN.
- Behind [SWAG](https://docs.linuxserver.io/general/swag/), use the bundled `code-server` proxy conf (it enables websockets) and point it at this container.
- When `OPENCODE_WEB=true`, the opencode web server is available on port `4096`.

## Repository layout

| Path | Purpose |
|---|---|
| `versions.env` | Pinned `CODE_SERVER_VERSION` / `OPENCODE_VERSION` (single source of truth) |
| `Dockerfile` | Image build |
| `docker-compose.yml` | Deployment |
| `patches/osc52-web.sh` | Clipboard fix applied at build time (guarded; build fails if the bundle changes) |
| `scripts/` | Entrypoint wrapper, startup hooks, clipboard wrappers |
| `.github/workflows/auto-update.yml` | Release checks, version bumps, image builds |
