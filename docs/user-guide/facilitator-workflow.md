# Facilitator workflow (Sense → Structure → Synthesize → Stage)

This is a facilitator-facing guide to running a Synesyn session using the Metapunkt pipeline. It focuses on practical steps: what to do, where to do it in the interface, what artifacts to expect, and how to keep participants oriented.

---

## Before you start (5–10 minutes)

- **Decide your outcome**: What should participants leave with?
  - A decision record or scenario transcript (ScenSyn), a set of committed Closures (SynAxes), a SynDoc presentation deck (SynPunkt), or a sequence that connects them.
- **Pick your operating mode**
  - **Offline / minimal**: Use a local model (such as Ollama) without the Hub. You can still run ScenSyn and basic SynTree chat.
  - **Full features**: Run the **Hub** (recommended). This enables artifact persistence, embeddings, voice, and cross-tool provenance.
- **Confirm the active model**
  - In **Tools → SynTree** (or ScenSyn settings), choose the provider and model.
  - If you plan to use SynAxes **Model themes** (the opt-in under Advanced), choose a model that supports embeddings (shown as `[embed]` in SynTree).

---

## Stage 1 — Sense (collect signals and context)

**Goal**: Gather what the group holds (documents, notes, prior session logs) and turn it into a shared context graph.

### Use SynTree (Tools → SynTree)

- **Add content sources**: Open **Manage Sources** and add the folders or files relevant to the workshop.
- **Curate**: Select which sources are active and use filters to reduce noise.
- **Build a context graph**: SynTree organises active sources into a structured context graph.
- **Publish (when the Hub is running)**: Click **Publish Context Graph** so downstream tools (SynAxes and SynPunkt) can load it.

**Artifacts and outputs**
- `ui.context_graph` (when published to the Hub)
- Local conversation threads and optional prompt-chain outputs

**Facilitator tips**
- Keep the set of active sources small and legible. Adding sources in stages works better than loading everything at once.
- Explain what "active sources" means to the room: "these are the materials the assistant is allowed to draw from."

---

## Stage 2 — Structure (map and connect meaning)

**Goal**: Move from a pile of source material to a navigable space where patterns can be inspected, then select the candidate groupings worth keeping.

The default path in SynAxes is **Import → Explore → Choose → Name → Commit** (see [`synaxes.md`](./synaxes.md)).

### Use SynAxes (Tools → SynAxes)

Keep **Advanced** closed unless you need to change the discovery method, dimensionality reduction, Hub jobs, or embedding tier.

- **Import**:
  - Prefer **Import latest Hub context graph** when a graph has already been published.
  - Or import a specific Hub context graph, a ScenSyn session, or the labelled demo source.
  - From Workshop Catalyst's Session Record, clicking **Propose themes** opens Tools → SynAxes with that session's Hub turns preloaded and discovery queued on the Closures tab.
- **Discover** with defaults (local themes). The theme-count control stays on the main panel; discovery method and embedding tier live under Advanced.
- **Explore** in **Pattern Overview**, which opens by default after discovery. The 3D Pattern Space remains available when spatial comparison is useful.

**Artifacts and outputs**
- Projection and cluster artifacts (when persisted through the Hub)
- An analysis-run record with provenance (Hub)

**Facilitator tips**
- Explain the step once: we are turning raw material into a few named holds the group can stand behind.
- Use Pattern Overview for shared attention on a projector, and switch to 3D Pattern Space only when spatial comparison helps.
- If the group needs richer semantic grouping than local TF-IDF provides, disclose **Model themes** under Advanced before enabling it (it is opt-in and sends item text to the configured provider).

---

## Stage 3 — Synthesize (commit closures)

**Goal**: Turn machine-suggested groupings into human-confirmed closures with an explicit name and intent.

### Use SynAxes (Closures / Dream Inbox)

- **Choose**: Select a candidate from Pattern Overview or the Dream Inbox and click **Work on this** to load the Closure Editor.
- **Name**: Adjust item membership if needed, set **Name** and **Intent**, and optionally tag an **Orientation** (the four quadrants of the [Closure Map](../concepts/closure-map.md), with plain-language subtitles).
- **Commit**: Commit explicitly to the Hub (closures are never overwritten silently). The coverage strip updates once saved closures exist, and you can hand off directly to SynPunkt Closures.

**Artifacts and outputs**
- `ui.closure` artifacts (Hub) with provenance: inputs, parameters, orientation, and timestamps

**Facilitator tips**
- Make intent explicit. Ask the room: "What is this cluster about for us?" and "What decision or next step does holding this pattern enable?"
- Closures are the human checkpoint in the pipeline: the system proposes, and the room decides what is held.

---

## Stage 4 — Stage (rehearse futures and present outputs)

**Goal**: Use committed closures or scenarios to rehearse a situation, run a structured workshop, or assemble a presentation deck.

### Use SynPunkt (Tools → SynPunkt)

- **Load Closures** and click **Generate** to create an editable SynDoc draft.
- **Edit**: Refine frames, add notes and narrative blocks, and build an edgeless layout.
- **Render (optional)**: Submit image-generation jobs when ComfyUI is configured.
- **Present**: Step through the Outline or navigate the Edgeless canvas (SynDeck).

**Artifacts and outputs**
- `ui.syndoc` presentation documents, `image.generated` renders, and camera decks (Hub)

### Use ScenSyn (main application)

- Run a facilitated decision workshop in [Workshop Catalyst](workshop-catalyst-facilitator-manual.md) or a character-driven rehearsal in [Story Catalyst](story-catalyst.md).
- Export session summaries, decision records, and story logs for sharing and archival.

**Facilitator tips**
- Treat ScenSyn as the live session and rehearsal layer, and SynPunkt as the curatorial and presentation layer.
- Keep the room oriented to where they are in the four-stage loop: Sense, Structure, Synthesize, or Stage.

---

## Troubleshooting quick notes

- **Hub offline**: Voice, embeddings, and artifact publishing require the Hub; basic chat and local session logs still work depending on your model provider.
- **Model themes unavailable**: Select a provider and model that supports embeddings (marked `[embed]` in SynTree), or stay on local themes (the default).
- **Too much UI on screen**: Hide the Main Menu or Chat Menu in SynTree using the toolbar toggles and bring them back only when needed.
