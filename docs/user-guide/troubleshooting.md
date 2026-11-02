# Troubleshooting

Common issues encountered when setting up or running a session, grouped by area.

---

## Hub and connection issues

### Hub says "started" but nothing connects (spawned then exited)

**Symptoms:**
- The launcher reports that the Hub started, but ScenSyn, SynAxes, or SynPunkt show connection timeouts.
- Restarting the Hub from the UI only works intermittently.

**What to do:**
- Run the Hub executable directly in a terminal to see the startup traceback:

```cmd
services\synesyn_hub\synesyn_hub.exe
```

- When running from source, activate your virtual environment and run `python -m app.main` from `services/synesyn_hub/`.
- If you see a `ModuleNotFoundError`, the environment or packaged build is missing a dependency. Voice (STT/TTS) providers are optional, but the Hub itself must start and answer `GET /health`.

### What still works when the Hub is offline

The client runs without the Hub, with reduced capability:
- **Works without the Hub:** ScenSyn text sessions (using a configured cloud API key or local Ollama), local Story Log saving and replay, and basic SynTree chat.
- **Requires the Hub:** workspace artifact storage (`ui.closure`, `ui.workshop_summary`, `ui.syndoc`), voice synthesis and microphone transcription, SynAxes Hub imports, and queued ComfyUI renders.

---

## ScenSyn and sessions

For Workshop Catalyst facilitation issues (empty buckets, vote cooldowns, specialist fallback messages, or stage timers), see the [Workshop Catalyst troubleshooting section](workshop-catalyst-facilitator-manual.md#troubleshooting).

### The session log folder looks empty

Session files are written to your user storage root under `Documents/Synesyn/` (ADR 0014), not inside the repository or Godot's hidden `user://` folder:
- Client-saved Story Logs and Workshop Catalyst `.md` / `.workshop.json` files: `Documents/Synesyn/scensyn/story_logs/`
- Hub-managed workspace artifacts: `Documents/Synesyn/Workspaces/<workspace_slug>/artifacts/`

### Story Stage shows a spectrum visualiser instead of character portraits

This is normal when no sprite pack or workspace art is installed for the active scenario. Only the two Cultural Narratives scenarios (*Ireti Okan* and *Stochastic Dreams*) have bundled sprite packs, which are an optional download. See [Story Stage sprite packs](story-stage-sprites.md#troubleshooting) for checking pack status or supplying your own character art.

### Session starts but the AI never responds

Confirm that an API key (or a running local Ollama instance) is configured for the provider selected in ScenSyn's hamburger menu (☰) or `synesyn_client/addons/syntree/config.cfg`. Remember that ScenSyn's active model selection is separate from SynTree's assistant dock.

---

## SynPunkt and rendering

### "Build Edgeless Layout from Projection" still says "(no edgeless layout)"

- If **ProjectionRef** is empty, SynPunkt falls back to a **frame-grid** edgeless layout.
- If you still see "(no edgeless layout)", confirm the SynDoc has at least one frame in **Design → SynDoc**, then build the layout again.

### ComfyUI test fails when ComfyUI is on another machine

Common causes:
- **ComfyUI is bound only to localhost** on the remote machine (launch ComfyUI with `--listen` so it accepts LAN connections).
- **A firewall is blocking port 8188** (or your chosen port) on the remote machine.
- **Wrong URL**: use `http://<remote-ip>:8188` rather than `127.0.0.1` when connecting from another machine.

### Hub-submit renders do not run

Check in order:
- The Hub is running and reachable (`GET /health`).
- SynPunkt is pointed at the right Hub URL (**Settings → Host/Join**).
- If Hub authentication is enabled, the client has the matching Bearer token configured.
- The machine running the Hub can reach the ComfyUI URL over the network.

### RenderResults is empty even though a render completed

- Check that the results list panel has not been collapsed by splitter sizing.
- Click **Refresh** to reload `image.generated` artifacts from the active workspace.

### Workflow dropdown is empty

The **Workflow** selector in SynPunkt is populated from Hub artifacts:
- Primary: `json.workflow`
- Fallback: `json.render_request` artifacts that embed or reference a workflow

In a fresh workspace with no saved workflows, paste or load a ComfyUI API workflow in the **Render** tab and click **Save Workflow Preset** to populate the list.
