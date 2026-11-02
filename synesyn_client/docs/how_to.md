# Synesyn: How To / Help

## What is the “Hub”?

The **Synesyn Hub** is a **local service** that runs on your computer (usually at `http://127.0.0.1:17777`).

It provides:

- **Local storage (“substrate”)**: a system-of-record for artifacts/events (typically under Documents/Synesyn).
- **Real-time events**: WebSocket event stream used for job progress and status.
- **Hub-mode Voice**: optional TTS/STT endpoints (if voice is configured to use the hub).

Synesyn (the Godot app) connects to the hub over HTTP/WebSocket. The hub is *not* embedded inside Godot; it runs as a separate process.

## How do they work together?

- **Synesyn app**: UI + game/tool logic + client-side threads/content.
- **Hub**: local backend service (storage, voice, events, exports).

When the hub is running, Synesyn can use it for:

- `/health` and `/status` for status indicators
- `/workspace/select` to choose the workspace root/name/slug
- Substrate APIs to store artifacts and query entities

## Quick checks

On the landing page:

- **Hub: running** means Synesyn can reach `GET /health` and the hub reports `ok=true`.
- **Hub: down** means either:
  - the hub is not running, or
  - the URL is wrong, or
  - the hub started but is not configured (workspace missing), or
  - a firewall/AV rule is blocking the port.

## Troubleshooting

### 1) “Hub: down”

- Click **Start Hub**
- Click **Open Hub Config** and verify:
  - `hub.base_url` is `http://127.0.0.1:17777`
  - `hub.autostart` is `true` (if you want it automatic)

### 2) “Hub: down (…workspace…)”

The hub may be running but not configured with a workspace yet.

- Open ScenSyn, open the **Services panel** (F12 in ScenSyn), and set:
  - Workspace name
  - Workspace slug
  - (Optional) root folder

### 3) Voice doesn’t work

In config:

- If `voice.provider_mode` is `"hub"`, the hub must be running and voice must be enabled on the hub.
- If `voice.provider_mode` is `"direct"`, Synesyn will use the external voice service URL instead.

## Where is the config?

Synesyn stores the client config at:

- `Documents/Synesyn/synesyn/config/synesyn_client.json`

Use **Open Hub Config** to open it quickly.


