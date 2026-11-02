# SynPunkt

SynPunkt is the authoring and presentation surface for working with **Closures** and **SynDocs**.

## Mental model

- **Closures (`ui.closure`)** are **read-only** slices committed in SynAxes.
- **SynDocs (`ui.syndoc`)** are **editable** documents you author to curate and present material as linear frames and an edgeless canvas layout.

## Artifacts panel (Closures + SynDocs)

- **Closures**: read-only snapshots you can load and inspect as source material.
- **SynDocs**: editable documents you can load, edit, present, and save as new versions.

The Artifacts panel can be collapsed or expanded; your SynDoc and status messages remain usable either way.

## Workflow: Closure → SynDoc

1. Load a Closure from **Artifacts → Closures**.
2. Click **Generate** (right panel) to create a new **editable** SynDoc draft from that closure.
3. Edit frames and content blocks in **Design → SynDoc**.
4. Build an edgeless layout:
   - If the closure carries a **ProjectionRef**, SynPunkt builds a semantic layout from its projection coordinates.
   - If no projection is attached, SynPunkt falls back to an **automatic grid layout** generated from the frames.
5. Save the SynDoc, creating new versions as you iterate.

## Saving and versioning

- **Save** creates a SynDoc artifact if none exists yet, or writes a new artifact record for your current working state.
- **Save as new version** creates a new artifact version with provenance pointing back to the previous SynDoc.
- Closures are never overwritten.

## Edgeless view essentials

- Click a node or cluster on the canvas to select it.
- Rename it using the label field (enabled whenever an item is selected).

## Present mode (SynDeck)

Present mode offers two complementary views over the same SynDoc:

- **Outline**: step through frames in sequence (**Prev** / **Next**).
- **Edgeless (Prezi-style canvas)**: view the SynDoc as spatially arranged cards and navigate either by selecting a card or by stepping through a captured camera deck.

### Present → Edgeless (what you should see)

- The canvas renders the **full frame content** (text and image blocks), not just thumbnails.
- Frame cards are styled for presentation with readable labels.
- The edgeless preview is clipped to its viewport so content does not spill outside the canvas.

### Present → Edgeless: Capture Cam / Apply Cam

SynPunkt supports saving camera bookmarks while presenting:

- **Capture Cam**: stores the current camera transform as a bookmark for the **selected frame**.
- **Apply Cam**: moves the camera to the best available saved bookmark, using this order of precedence:
  - the selected frame's saved camera (if present),
  - otherwise the most recent captured deck step for that frame,
  - otherwise the active frame's camera.

Optional deck capture:

- When **Deck capture** is enabled, each Capture also appends a step to a presentation deck (`presentation.steps[]`), so **Prev** and **Next** step through the camera path in **Present → Edgeless**.

## Render tab (ComfyUI / Hub-submit)

SynPunkt submits standardised render requests (`SynesynRenderRequestV1`) and persists the generated images with provenance.

- **Test** checks whether ComfyUI is reachable and reports a clear `OK` or `FAIL` status.
- **Submit render** routes the request in one of two modes:
  - **Direct** (SynPunkt → ComfyUI), or
  - **Hub** (SynPunkt → Hub `/render/submit` → Hub worker → ComfyUI).

### Render results (what to expect)

- The results list can be refreshed from workspace artifacts (`image.generated`), so it is not limited to the current session.
- A newly completed render appears in the list as soon as generation finishes.
- Gallery controls:
  - text filter
  - sort by newest, oldest, or name
  - multi-select
- Actions on selected items:
  - insert selected artifacts into the current SynDoc frame as image blocks
  - copy selected artifact ID
  - open the selected artifact's folder on disk
  - delete selected artifacts (explicit destructive action)
  - clear or refresh the list

### Workflow selector (why it might be empty)

The **Workflow** dropdown is populated from saved workflow artifacts on the Hub:

- Primary: `json.workflow`
- Fallback: render requests (`json.render_request`) that embed or reference a workflow payload

If the workspace has no `json.workflow` artifacts yet, the selector remains empty until you save a workflow preset (or until the fallback list has entries).

### Workflow preset tags (ScenSyn integration)

ScenSyn can enqueue image-generation jobs using SynPunkt's saved workflow presets. To make a preset discoverable by ScenSyn, **tag** the workflow preset when saving it.

**Where tags live**:
- Clicking **Save Workflow Preset** stores a `json.workflow` artifact on the Hub.
- The tags you enter are stored in the artifact metadata under `metadata.preset.tags` (an array of strings).

**How to tag a preset**:
1. Open the **Render** tab.
2. Load or paste a valid ComfyUI API workflow (prompt graph).
3. In the **Preset Tags** field, enter a comma-separated list of tags.
4. Click **Save Workflow Preset**.

**Required tag (v1)**:
- `scensyn:render_purpose=<purpose_id>`

**Optional scoping tags** (for scenario/collection-specific overrides):
- `scensyn:collection=<collection_id>` (example: `cultural_narratives`)
- `scensyn:scenario=<scenario_key>` (example: `ireti_okan_awaiting_an_awakening`)
- `scensyn:character=<character_slug>` (example: `lucky`)
- `scensyn:variant=<variant_id>` (example: `happy`)
- `scensyn:phase=<phase_id>` (example: `setup`)

**Example presets**:
- Global background default:
  - `scensyn:render_purpose=background`
- Collection default background:
  - `scensyn:render_purpose=background, scensyn:collection=cultural_narratives`
- Scenario override portrait for a character:
  - `scensyn:render_purpose=portrait, scensyn:collection=cultural_narratives, scensyn:scenario=ireti_okan_awaiting_an_awakening, scensyn:character=lucky`

**Selection behavior**:
ScenSyn identifies the active collection and scenario at runtime and selects the most specific matching preset, falling back in order:
scenario + collection → collection → global.

### Artifact details and provenance links

Selecting an artifact in Render results opens a details panel showing:

- display name and artifact ID
- creation time, artifact type, file extension, and file size
- shortened content hash
- provenance links to related artifacts when available:
  - `render_request`
  - `workflow`
  - `prompt`

Link status uses text labels (`OK`, `MISSING`, `N/A`, `CHECKING`) rather than relying on colour alone.

Details actions:

- load linked workflow
- load linked `render_request` (and resolve its workflow)
- copy all linked IDs

### ComfyUI URL history

- The ComfyUI URL field is editable.
- A recent-URLs dropdown remembers up to the last five URLs used.
- Selecting a recent URL fills the input field.

## Settings: Host/Join (group sessions)

When sharing a workspace across machines, one machine hosts the Hub and other machines connect to its URL.

- **Host**: displays a shareable `http://<host-ip>:<port>` URL.
- **Join**: enter the host's Hub URL, optionally enable Bearer token authentication, test the connection, and save.
