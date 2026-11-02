# Glossary

Synesyn's vocabulary is load-bearing: the same word can name a philosophical
position, a UI surface, and a stored record. This page fixes the operative
meaning of each term as the system actually uses it, and says where the term
came from only when that changes how you should read it.

Where a definition and the code disagree, the code is described here and the
discrepancy is stated.

## The three senses of "closure"

"Closure" is the most overloaded word in the project. Three distinct things carry
it, and conflating them is the most common way to misread the documentation.

**1. Closure, as a philosophical stance.** From Hilary Lawson's account of
closure: a provisional boundary drawn over open potential so that a world becomes
workable and action can proceed, knowing it may be reopened. This is the sense in
which nothing in Synesyn is ever final. It motivates the design but is not itself
a record in the system. See [the Closure Map](closure-map.md).

**2. A committed decision in a session.** In Workshop Catalyst, a closure is a
boundary the room draws so it can act — a decision, a risk accepted, a question
deliberately deferred. It exists only after a human commits it; the system may
propose, never close (ADR 0019).

**3. A navigable slice of the substrate.** In SynAxes, a closure is a saved
selection over accumulated material: criteria, constraints, a time window, and
optionally an orientation. It is what lets you return to a way of looking rather
than a result.

Senses 2 and 3 are stored as **different artifact types**: a session capture is a
`ui.workshop_closure`, a SynAxes slice is a `ui.closure`. They were once both
written as `ui.closure`; ADR 0026 records why that was separated.

**`ui.closure`** — the hub artifact type storing a committed closure. Note for
developers: this is sense 3 only — a SynAxes slice, carrying `name`, `intent`,
`selection`, `time_window` and, from `schema_version` 2, an `orientation`
quadrant. The hub validates it and rejects session captures written under this
type.

Artifacts stored before ADR 0026 may still hold a session capture under
`ui.closure`. Such a payload has a `statement` and no `selection`; SynAxes' saved
closure list skips them and reports how many it skipped.

**`ui.workshop_closure`** — the hub artifact type storing a session capture
(sense 2), carrying `kind`, `statement`, `outcome`, `owner` and vote fields.
Written by ScenSyn's closure bus and validated by the hub. Note that `outcome`
has no single vocabulary: a vote records `yes` or `no`, while a Compare Paths
commit records `committed`.

## Records and storage

**Artifact** — an immutable, typed, content-addressed output held by the hub: a
text, a JSON structure, an image, or a UI state snapshot. What makes something an
artifact rather than a file is that it carries a type and provenance and is
referenced by identity, so later work can cite it. Revising an artifact means
writing a new one, not overwriting.

**Provenance** — the record of how an artifact came to exist: `produced_by` (which
tool or model), `inputs` (the artifact or event identifiers it derived from),
`parameters`, and a timestamp. This is what makes a result traceable back to the
inputs and human decisions behind it.

**Latent reality** — the accumulated substrate of entities, relations, artifacts,
projections and closures that a group's work leaves behind, treated as something
navigable rather than as history. Used in two registers: technically, the
persisted substrate; conceptually, the view that reality is open potential made
workable through closures. Both are intended.

**Workspace** — a named container for one body of work, holding `substrate/`,
`artifacts/`, `exports/` and `logs/`. Selected through the hub, and in normal
operation the client tells the hub where it lives.

**Where files actually land.** Three locations, each correct for different things:

| Location | Holds |
| --- | --- |
| `Documents/Synesyn/Workspaces/<slug>/artifacts/` | Hub workspace artifacts, in normal client-launched operation |
| `Documents/Synesyn/scensyn/story_logs/` | Session files written by the client: the `.md` summary and its `.workshop.json` sidecar |
| `Documents/Synesyn/<slug>/` | The hub's own default, which applies only when the hub is started standalone with no client selecting a workspace |

`Documents/Synesyn/` is the user-visible root by design (ADR 0014), replacing
Godot's hidden `user://` location.

**Story log** — the running transcript of a session, shown in the interface and
persisted as JSON with a provenance sidecar. Both session types use the same
mechanism and present it differently: Story Catalyst posts many character voices,
Workshop Catalyst posts a single `Session Record` voice.

## Sessions

**Session type** — the top-level kind of session, currently `workshop_catalyst` or
`story_catalyst`. A session type owns its scenario collections, its metaprompt
manager, and whether its ensemble is visible or hidden. It replaced the earlier
"theme" terminology.

**Workshop Catalyst** — facilitated group foresight. Analysis happens out of sight
and is synthesised into one voice, so the room's attention stays on the
participants rather than on characters.

**Story Catalyst** — narrative and cultural exploration through an ensemble of
characters who speak in their own voices.

**Scenario** — the authored setup for a session: a `.txt` file of bracketed
sections (`[SCENARIO]`, `[CHARACTERS]`, `[WORKSHOP_AGENDA]`, `[STAGE_GUIDANCE]`)
that the scenario loader reads. Shipped scenarios live under the client's session
types; user-authored ones live under `Documents/Synesyn/scensyn/`.

**Metaprompt** — the system prompt assembled at runtime from the scenario, the
current stage's guidance, and live session state, then sent to the model. It is
composed per turn rather than stored as a fixed string.

**Specialist** — one of four analytical roles Workshop Catalyst runs over each
contribution. The facilitator manual calls these the **four lenses**; the code
calls them specialists or roles. They are the same four functions: systems and
consequences, stakeholders and communication, risk and feasibility, options and
innovation (ADR 0012).

**Six cross-checks** — the pairings between those four lenses that the synthesis
step must reconcile, such as stakeholder against risk to identify who bears a
cost. They exist so that synthesis is more than concatenation.

**Society of Minds** — the name for Workshop Catalyst's arrangement in which
several specialists contribute backstage and collapse into one response. It is
architectural vocabulary, not a class in the code.

**Thinking Map** — the causal surface built during a workshop session: causes,
effects and opportunities, persisted as `ui.workshop_thinking_map`. Authored by
the room, with the system proposing and a human committing (ADR 0019).

**Closure Map** — a corpus-scale instrument in SynAxes for orienting committed
closures, not a bigger Thinking Map. ADR 0020 draws the boundary: the workshop
audit borrows Closure Map vocabulary as an optional facet, and the two remain
distinct.

**Distal, Deep, Proxistance** — the Closure Map's orientation vocabulary. *Distal*
is outward extension, toward the remote and exposed. *Deep* is inward layering,
toward the latent and resonant. *Proxistance* is the movement between them from
where you presently stand. They are directions of attention, not measurements, and
they combine with past and future into four quadrants (ADR 0015).

## Modules

**Hub** — the optional Python service that acts as system of record: artifacts,
events, jobs, voice and memory, on `127.0.0.1:17777`.

**Client** — the Godot application holding every user-facing surface. It runs
without the hub, with reduced capability.

**ScenSyn** — the session runtime: scenarios, turns, story log, and both session
types.

**SynAxes** — pattern synthesis over accumulated material; where closures in the
third sense are formed and committed.

**SynTree** — the context graph over source material, and the editor-side
assistant built on it.

**SynPunkt** — authoring and presentation. A **SynDoc** is its document artifact,
stored as `ui.syndoc`: an outline, an edgeless canvas and camera paths.

**Metapunkt** — orchestration of role-based agent ensembles. Also the name of the
method the platform implements, and of the organisation; context distinguishes
them.

**ReadyMade** — a module for semi-automated content creation from the "Found
Concepts" method. Only a slice of that method is implemented; ADR 0024 records the
vocabulary its data model uses, including `cosmic_instrument`, and is the
authoritative scope statement rather than the module's own README.

**STFX Store** — the canonical file-backed memory substrate: sources,
chunks, memories, closures, traces and context packs. Its indexes are disposable
and can be rebuilt.

**STFX Memory** — the older document-centric service, retained as a
compatibility path and as the user-facing name of the capability. Both derive
from the **STFX** (Seed-to-Field Expansion) kernel (`stfx_core`): Store is where
data lives, Memory is what it is for.

**Dream Inbox** — SynAxes' queue of system-proposed candidates awaiting human
judgement. Accepting one opens it for editing; committing it writes a `ui.closure`.
The name is used only in SynAxes.
