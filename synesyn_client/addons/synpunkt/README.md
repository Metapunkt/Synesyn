# SynPunkt (editor plugin) — v0

This addon is the **SynPunkt** authoring surface.

## v0 scope
- Load `ui.closure` artifacts from the Synesyn Hub
- Preview a closure JSON
- Generate an editable `ui.syndoc` draft from the closure
- Save/version the `ui.syndoc` back to the hub (as an artifact)
- Present `ui.syndoc` via Outline and Edgeless (Prezi-style) views, including camera capture/apply and optional `presentation.steps[]` deck
- Render via ComfyUI bridge (direct or hub-submit), appending RenderResults with artifact actions (copy id, open folder, clear)

## Notes
- The dock uses the shared `HubSubstrateClient` (`res://addons/synesyn_core/scripts/hub_substrate_client.gd`).
- `ui.syndoc` schema is intentionally minimal and versioned (`schema_version: 0.1.0`) so we can evolve it.


