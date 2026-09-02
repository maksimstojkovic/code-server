# code-server + opencode (auto-updated)

Docker image based on the [official coder/code-server image](https://github.com/coder/code-server) with:

- **opencode** CLI installed and pinned (auto-bumped on new releases)
- **vim**, **python3**, **pip**, **venv** preinstalled
- A one-line **OSC 52 clipboard patch** that fixes select-to-copy in the opencode TUI (and any other OSC 52 TUI, e.g. tmux) when using code-server in the browser

A scheduled GitHub Actions workflow checks for new releases of code-server and opencode every 6 hours, bumps the pins in `versions.env`, and pushes a fresh image to `ghcr.io/maksimstojkovic/code-server`.

## Files

| File | Purpose |
|---|---|
| `versions.env` | Pinned `CODE_SERVER_VERSION` and `OPENCODE_VERSION` (single source of truth) |
| `Dockerfile` | Builds the image from the official coder base + pins |
| `patches/osc52-web.sh` | The clipboard fix (guarded; build fails if upstream changes) |
| `docker-compose.yml` | Deployment for the Docker host |
| `.github/workflows/auto-update.yml` | Release checks, version bumps, image builds |

## The clipboard fix

**Symptom:** dragging to select text in the opencode TUI shows "Copied to clipboard" but nothing lands in the browser clipboard.

**Root cause chain (verified against sources, September 2026):**

1. opencode's TUI copies on mouse-up by emitting an **OSC 52** escape sequence (unconditional), then trying `xclip`/`xsel`/`wl-copy` — all silently failing headless. The toast displays regardless because failures are swallowed (`packages/tui/src/clipboard.ts`).
2. code-server's terminal (xterm.js `ClipboardAddon`) receives OSC 52 and hands it to VS Code's clipboard service. This has worked since VS Code 1.91 (June 2024).
3. **The break:** in the *web* clipboard service, `BrowserClipboardService.writeText` stores any write that passes a selection type in-memory only (`// With type: only in-memory is supported`), and the xterm addon provider always passes `"clipboard"`. So the write is silently discarded. Desktop VS Code uses a different service, which is why it works there.

**Fix:** `patches/osc52-web.sh` rewrites the single minified provider call in `workbench.web.main.internal.js` so clipboard writes go untyped → `navigator.clipboard.writeText`. It runs during image build with a hard guard: if a future code-server release changes the minified code, the build **fails loudly** rather than shipping without the fix. If that happens, locate the `ClipboardAddon` provider mapping in the new bundle (compare with `src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts` upstream) and update the pattern in the script.

**Requirements:** the browser clipboard API needs a **secure context** — access code-server via HTTPS (e.g. SWAG) or localhost. Plain HTTP over LAN IP will not work.

TUI mouse behavior is unchanged: opencode keeps mouse capture (scrolling, clicking) and its native select-to-copy just works. If something regresses, `Shift`+drag forces a native terminal selection as an emergency fallback.

## Setup (one-time)

1. Push this repo to `github.com/maksimstojkovic/code-server`
2. Run the workflow once manually: **Actions → auto-update → Run workflow** (or just push)
3. The first build creates a **private** GHCR package. Either:
   - Make it public: repo → Packages → `code-server` → Package settings → Change visibility, **or**
   - On the Docker host: `docker login ghcr.io -u maksimstojkovic` with a PAT that has `read:packages`

## Deploy / update (Docker host)

```bash
docker compose pull && docker compose up -d
```

The image is rebuilt automatically within ~6 hours of a new code-server or opencode release; just pull and recreate whenever you like.

## Verify the clipboard fix

1. Open code-server over HTTPS → terminal → `printf '\033]52;c;%s\033\\' "$(printf hello-osc52 | base64)"` → paste somewhere (`Ctrl+V`) → should paste `hello-osc52`
2. Run `opencode` → drag-select some text → expect the "Copied to clipboard" toast to actually mean it this time → paste in a browser text field

## Configuration

Copy `.env.example` to `.env` next to `docker-compose.yml` and adjust — compose picks it up automatically:

| Variable | Default | Purpose |
|---|---|---|
| `PUID` / `PGID` | `1000` / `1000` | Runtime UID/GID of code-server (set via the image's `fixuid`). Changing it after data exists triggers a **one-time recursive chown** of the home mount on the next start |
| `DEFAULT_WORKSPACE` | `/home/coder/workspace` | Folder code-server opens on start (created automatically if missing) |
| `TZ` | `Australia/Sydney` | Container timezone |
| `DOCKER_USER` | `coder` | Optional cosmetic username inside the container (shell prompt, sudo) |

## Notes

- The LinuxServer-style `/config` home directory carries over 1:1 (`/media/data/docker/opencode/config` is mounted at `/home/coder`)
- Startup hooks live in the image at `/usr/local/share/entrypoint.d` (the base image's hook location under `$HOME` would be shadowed by the volume mount)
- SWAG: use the bundled `code-server` proxy conf (it enables websockets) pointed at this container's port 8080
- Python is externally managed (PEP 668): use `python3 -m venv` or `pipx` rather than global `pip install`
