# Local development

## Recommended builds

Synesyn does **not** ship or bundle Godot or LimboAI. Both are open-source
dependencies that each user installs themselves. The versions below are
**recommended / tested-with** builds: what CI runs and what we recommend for
local development. The single source of truth (including download URLs and
SHA256 checksums) is
[`utilities/checks/tool_versions.env`](https://github.com/Metapunkt/Synesyn/blob/main/utilities/checks/tool_versions.env).

| Dependency | Recommended build | Official download |
| --- | --- | --- |
| Godot | **4.7.2-stable** (project declares `4.7`) | [Godot download](https://godotengine.org/download/) · [4.7.2-stable release](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip) |
| LimboAI | **v1.8.0**, GDExtension build labeled for Godot **4.6** (`limboai+v1.8.0.gdextension-4.6.zip`) | [LimboAI releases](https://github.com/limbonaut/limboai/releases) |

The LimboAI 4.6 GDExtension build works under Godot 4.7.x. Upstream does not
publish a `gdextension-4.7` zip yet; we stay on the GDExtension 4.6 artifact
(not a custom LimboAI module editor).

## Prerequisites

- **Godot 4.7.x** — install the recommended build above yourself.
- **Python 3.11** for the hub. `services/synesyn_hub/environment.yml` pins it.
- **LimboAI v1.8.0 binaries** — not redistributed in this repository. Install
  them before opening the project — see below. CI uses the same recommended
  build from `utilities/checks/tool_versions.env`.

### Installing LimboAI (required before the first open)

`synesyn_client/addons/limboai/bin/` is excluded from this repository: 34 files
and roughly 130 MB of precompiled libraries for Windows, Linux, macOS and
Android, all published upstream under MIT. That directory also holds
`limboai.gdextension`, the descriptor Godot reads to register the extension, so
without it the addon does not load and the project will not open cleanly.

1. Download the recommended release matching
   `synesyn_client/addons/limboai/version.txt` (**v1.8.0**) — the GDExtension
   zip for Godot 4.6 — from
   [LimboAI releases](https://github.com/limbonaut/limboai/releases).
2. Copy the `addons/limboai/bin/` directory from the archive into
   `synesyn_client/addons/limboai/bin/`.
3. Confirm `synesyn_client/addons/limboai/bin/limboai.gdextension` exists, then
   open `synesyn_client/` in Godot.

Matching the recommended build matters: the GDExtension ABI is tied to the
Godot version, so a mismatched build fails to load rather than degrading.

### First launch (fresh clone)

The first time you open `synesyn_client/` in Godot (or run
`godot --headless --path synesyn_client --import`), Godot imports assets and
registers GDExtensions. LimboAI is discovered from
`synesyn_client/addons/limboai/bin/limboai.gdextension` — there is no
`[gdextension]` section in `project.godot` for that. Godot writes `.godot/`
(including `extension_list.cfg`); that cache is local — do not commit it.

On that first open you may see transient errors such as
`Could not find base class "BTPlayer"` / `BTTask` / `BTAction`, or
`Failed loading resource` for theme / JetBrains Mono fonts under the
project's `theme/fonts` and `csr/thirdparty/fonts` folders. Those clear
after the import finishes. Use **Project → Reload Current Project**, or
run a headless import first, then open the editor again.

Benign init-order warnings that can appear even after a healthy reload (safe
to ignore): `Logging service not available`,
`ContentBus: NotificationManager not found`, and
`ContentListView: ContentStateResource not injected yet`. They come from
autoload/plugin startup order, not from a broken LimboAI install.

If `Could not find type "BTPlayer"` persists on the ReadyMade A1 agent script
after reload, LimboAI did not register — confirm
`synesyn_client/addons/limboai/bin/limboai.gdextension` and the platform binary
exist (see Recommended builds above).

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

## Running ScenSyn from source with voice and avatars

A packaged Windows release ships a Hub binary beside the client. A source
checkout does not: `dist/` is gitignored, and `HubLocator` only finds a built
`services/synesyn_hub/synesyn_hub` (or `hub.exec_path`). Without a reachable Hub,
ScenSyn still shows AI text, but voice stays silent. Without a Story Stage art
pack, characters fall back to the spectrum visualiser.

### Voice (Synesyn Hub)

1. Install Hub dependencies and start it from the repo:

```bash
cd services/synesyn_hub
python -m venv .venv
# Windows: .\.venv\Scripts\pip install -r requirements.txt
# Unix:
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m app.main
```

2. Confirm it answers health (any HTTP 200 JSON with `ok` is enough for
   reachability; workspace configuration can come later):

```bash
curl -s http://127.0.0.1:17777/health
```

3. In Godot, run ScenSyn with voice provider mode `hub` (the default in recent
   configs). If the Hub is down you should see a one-time notice:
   `Voice unavailable: Synesyn Hub isn't running at 127.0.0.1:17777`.

**Alternatives when you do not want a manual terminal:**

- Set `hub.exec_path` in `Documents/Synesyn/synesyn/config/synesyn_client.json` to
  an absolute path of a built Hub binary, with `hub.autostart` left true.
- For editor/source runs only, set `"autostart_from_source": true` under `hub`.
  That starts `python -m app.main` in `services/synesyn_hub` when no binary is
  found. It defaults to **false** so a generic checkout never spawns Python
  unless you opt in. Packaged builds ignore this setting.

### Avatars (Story Stage art)

1. Install a pack (Cultural Narratives only ship art):

```bash
python utilities/assets/story_stage_sprites.py status
python utilities/assets/story_stage_sprites.py install ireti-okan --from <archive>
```

Details and bring-your-own art paths are in
[Story Stage sprite packs](../user-guide/story-stage-sprites.md).

2. Open a Cultural Narratives scenario (*Ireti Okan* or *Stochastic Dreams*) and
   use the **Visual Stage** window. Without a pack you get one warning —
   `Story Stage art pack not installed` — and the spectrum visualiser instead of
   portraits.

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



