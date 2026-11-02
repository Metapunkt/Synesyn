# Concepts

This page introduces the working concepts you meet in the Synesyn interface. For complete definitions of the project's terminology, read the [Glossary](../concepts/glossary.md); for the four-quadrant orientation instrument used in SynAxes, see [The Closure Map](../concepts/closure-map.md).

## Artifacts and provenance

An **artifact** is an immutable, versioned record stored by the Hub and addressed by its artifact ID (for example a context graph, a closure, a workshop summary, a presentation document, or a generated image). Editing an item writes a new artifact version rather than overwriting the old one.

Every artifact carries **provenance**: which tool or model produced it, which upstream artifacts or session turns it drew from, its parameters, and when it was committed. That lineage is what allows one session to build on another without losing track of where a claim or image came from.

## Two kinds of closure

In Synesyn, a **closure** is a provisional boundary that a human explicitly commits so work can proceed. Two tools produce closures of different kinds, stored under distinct artifact types (ADR 0026):

- **Workshop captures (`ui.workshop_closure`)** — committed during a [Workshop Catalyst](workshop-catalyst-facilitator-manual.md) session in ScenSyn when the room records a decision, a named risk, or a deferred question.
- **SynAxes slices (`ui.closure`)** — committed in [SynAxes](synaxes.md) when you group and name a pattern discovered across imported material, optionally tagged with an A–D [Closure Map](../concepts/closure-map.md) orientation.

Both are read-only once committed. Downstream tools such as SynPunkt load `ui.closure` slices as source material without modifying them.

## Context graphs, projections, and clusters

- **Context graph (`ui.context_graph`)**: a structured snapshot of the active sources curated in **SynTree**, published to the Hub so SynAxes and SynPunkt can work over a known set of materials.
- **Projection**: 2D or 3D coordinates computed over items in SynAxes, used both for visual exploration and for placing cards meaningfully on SynPunkt's edgeless canvas.
- **Clusters**: groupings of related items (centroids and membership) discovered in SynAxes that can be reviewed as candidate closures or overlaid on a layout. When a closure has no projection attached, SynPunkt falls back to an automatic grid layout.

## SynDocs (editable presentations)

A **SynDoc** (`ui.syndoc`) is an editable presentation document authored in [SynPunkt](synpunkt.md). You generate a draft from a committed Closure, edit its frames and content blocks, arrange them on an edgeless canvas with optional camera bookmarks (**SynDeck**), and save new versions as the presentation evolves.

## Render requests

Image generation in SynPunkt and ScenSyn uses a shared, versioned contract (`SynesynRenderRequestV1`):

- **Routing parity**: requests can be sent either directly to ComfyUI (`direct`) or asynchronously through the Hub's job queue (`hub`) with the same status reporting (`queued`, `started`, `completed`, `failed`, `canceled`).
- **Workflow presets**: saved ComfyUI workflows (`json.workflow`) carry tags (`scensyn:render_purpose`, `scensyn:collection`, `scensyn:scenario`, `scensyn:character`) so ScenSyn can pick the right preset automatically during a session.
- **Provenance links**: every generated image (`image.generated`) links back to the render request, workflow preset, seed, and prompt that produced it.

## The Hub

The **Synesyn Hub** (`synesyn_hub.exe`) is the optional local Python service that stores workspace artifacts, runs background jobs (embeddings, projections, ComfyUI renders, speech synthesis and transcription), and streams events over WebSocket. When you work on one machine, the client starts and adopts the Hub automatically; when working as a group, one machine hosts the Hub and others point at its URL under **Settings → Host/Join**.
