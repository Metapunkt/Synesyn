# Synesyn Hub (v0)

Local-first Python service that provides:
- LatentSubstrate system-of-record (SQLite + file-backed artifacts) rooted at `~/Documents/Synesyn/<workspace_slug>/`
- UDP sensor ingestion → normalized events → WebSocket broadcast
- Voice API: `POST /voice/speak` and `POST /voice/transcribe`
- Session export: `POST /export/session`

## Dev run (local)

1) Create a virtual environment and install deps:

```bash
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
```

2) Start the hub (defaults to `127.0.0.1:17777`):

```bash
.\.venv\Scripts\python -m app.main
```

## Configuration

The hub reads `app/config.yaml` and environment variables. For local dev you can set:
- `SYNESYN_WORKSPACE_NAME`
- `SYNESYN_WORKSPACE_SLUG`
- `SYNESYN_ENFORCE_PROVENANCE` (default: `true`)

If workspace is not configured, `/health` will return `ok=false` and the reason.

## Workspace selection (no CLI / Godot-managed)

For packaged builds, Godot should:
- Start the hub executable
- Call `POST /workspace/select` on first run to choose the workspace
- Poll `GET /health` and `GET /status`

## Packaging (Windows)

See `packaging/README.md`.


