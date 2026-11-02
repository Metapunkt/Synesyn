# Local development

## Prerequisites

- **Godot 4.7.x.** The project declares `4.7`; harness runs are verified against
  4.7.1-rc2.
- **Python 3.11** for the hub. `services/synesyn_hub/environment.yml` pins it.
- **LimboAI v1.8.0 binaries**, which are not redistributed here. Install them
  before opening the project — see below.

### Installing LimboAI (required before the first open)

`synesyn_client/addons/limboai/bin/` is excluded from this repository: 34 files
and roughly 130 MB of precompiled libraries for Windows, Linux, macOS and
Android, all published upstream under MIT. That directory also holds
`limboai.gdextension`, the descriptor Godot reads to register the extension, so
without it the addon does not load and the project will not open cleanly.

1. Download the release matching `synesyn_client/addons/limboai/version.txt`
   (**v1.8.0**) for Godot 4.x from
   [LimboAI releases](https://github.com/limbonaut/limboai/releases).
2. Copy the `addons/limboai/bin/` directory from the archive into
   `synesyn_client/addons/limboai/bin/`.
3. Confirm `synesyn_client/addons/limboai/bin/limboai.gdextension` exists, then
   open `synesyn_client/` in Godot.

The pinned version matters: the GDExtension ABI is tied to the Godot version, so
a mismatched build fails to load rather than degrading.

### Story Stage character art (optional)

`synesyn_client/ScenSyn/story_stage/sprites/` is excluded for the same reason at a
larger scale: 545 MB of animation frames for two scenarios. Unlike LimboAI this is
genuinely optional — the project opens, every test passes, and sessions run
normally without it. When no sprite pack is installed, Story Stage draws speakers
with the spectrum visualiser rather than character portraits.

```bash
python utilities/assets/story_stage_sprites.py status
```

Installing a pack, and supplying your own art instead, are covered in
[Story Stage sprite packs](../user-guide/story-stage-sprites.md).

## Hub

Full detail is in `../implementation_docs/Local_Deployment_Runbook.md`. For a
local dev run, from `services/synesyn_hub/`:

```bash
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\python -m app.main
```

Key current defaults (local-first):

- Hub HTTP: `http://127.0.0.1:17777`
- Hub WS events: `ws://127.0.0.1:17777/ws/events`

`GET /health` returns `ok=false` with a reason until a workspace is configured.
The client normally starts and adopts the hub for you (ADR 0021); start it by
hand mainly when diagnosing a failure.

## Running the client in Godot

- Open the Godot project in `synesyn_client/`.
- Running the project opens the Synesyn launcher (ScenSyn, ReadyMade, Play a Story
  Log, and Synesyn Tools). You can also open individual addon docks such as
  SynTree, SynAxes, or SynPunkt directly in the editor or through Synesyn Tools.
- The client and addon docks read their Hub URL and settings from
  `Documents/Synesyn/synesyn/config/synesyn_client.json` by default.

## Script size policy check

- Canonical policy lives in `architecture.md` (Cursor rules mirror it for agent behavior).
- Run before merges/substantial script changes:
  - `python utilities/checks/check_line_limits.py`
- Current thresholds:
  - soft warning: 900 lines
  - hard limit: 1200 lines

## Runtime config (client)

Client runtime config is stored at:

- `Documents/Synesyn/synesyn/config/synesyn_client.json` — on Windows this resolves to
  `C:/Users/<you>/Documents/Synesyn/synesyn/config/synesyn_client.json`

Call `RuntimeConfig.get_config_path_abs()` rather than hardcoding it; the storage
root is overridable via `storage.root_dir`, and the helper falls back to
`user://synesyn_client.json` only when no Documents folder is available. See
ADR 0014 for the storage-root convention.



