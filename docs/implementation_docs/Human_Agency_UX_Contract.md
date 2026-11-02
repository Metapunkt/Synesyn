# Human Agency UX Contract (Synesyn / Latent Reality)

**Status**: Normative UX contract (v0→v1)  
**Purpose**: Ensure “Latent Reality” remains **human-shaped** rather than automation-first, across SynAxes → SynTree → SynPunkt, with the Hub/LatentSubstrate as system-of-record.

---

## 1) Core principle: the system proposes; the human closes
Synesyn is designed so that:
- **Models propose** candidates (patterns, closures, prompt chains, layouts, renders)
- **Humans commit closures** (and related “publication” artifacts) into canonical reality

This is implemented via versioned artifacts + explicit decision events.

---

## 2) Global UX invariant (apply everywhere)
### Propose → Preview → Commit → Version
- **Propose**: show candidate outputs as *drafts*, never silently “truth”
- **Preview**: user can inspect impact without committing changes
- **Commit**: user explicitly accepts (creates/updates canonical artifacts)
- **Version**: edits do not overwrite history; new versions are created with provenance

### “Editable by default” rule
Where practical and helpful, **every proposal should be editable before commit**:
- Suggested prompts are editable
- Prompt-chain order/activation is editable
- Closure selection/filters/pins/time-window are editable
- SynDeck frames, camera path, and text blocks are editable
- Render recipes (workflow preset + prompt mapping + params) are editable

If something cannot be edited (e.g., a deterministic hash output), the UI must clearly indicate “read-only.”

### “Isolation by default” rule (cross-surface)
Because Synesyn includes multiple prompt surfaces (SynTree editor, ScenSyn runtime sessions, and future clients),
the UX must prevent accidental context bleed:
- **Never** implicitly mix conversation history between surfaces.
- **Never** implicitly inject SynTree content sources into runtime app prompts.
- Any cross-surface context use must be **explicitly enabled** and user-visible (toggle), and ideally recorded as an event.

---

## 3) Canonical record & provenance (non-negotiable)
### Hub is the system-of-record
- Canonical artifacts/entities/relations/events live in the Hub (LatentSubstrate).
- Godot modules are **clients** that read/write via hub APIs.

### Every derived artifact must be traceable
For any derived artifact (prompt sets, projections, cluster results, renders, exports), the UI must support:
- **Show provenance**: “what produced this” and “what it used”
- **Show inputs**: linked artifacts/events/closures
- **Re-run**: rerun with tweaks (produces a new version, never overwrites)

---

## 4) UX surfaces required (v0 baseline)

### 4.1 Session Timeline / Inspector (shared, cross-app)
**Goal**: users can always answer “what happened and why?”
- Timeline of session events (turns, sensor updates, jobs, commits)
- Drill-down inspector for artifacts/entities/relations
- “Compare versions” for closures and prompt sets

### 4.2 Dream Inbox (SynAxes)
**Goal**: model outputs become actionable proposals, not hidden decisions.
- List candidate patterns, projections, and closure seeds
- Controls per candidate:
  - accept / reject / defer
  - adjust parameters (time window, sensitivity, exclusions)
  - rerun with changes
- Accept creates draft closure artifacts; reject creates an explicit decision record to reduce repeated suggestions.

### 4.3 Closure Editor (SynAxes)
**Goal**: closure is a human act.
Editable fields (pre-commit):
- selection criteria (entities/tags/filters)
- pins/constraints
- time window (the “+1 temporal dimension”)
- intent notes / label
Commit behavior:
- Creates/updates `ui.closure` as an immutable artifact (new version per edit)
- Emits a commit event (for replay + audit)

### 4.4 Synthesis Brief + Prompt Chain Editor (SynTree)
**Goal**: prompts are editable plans, not opaque internals.
Editable:
- synthesis “brief” (what we are trying to achieve)
- suggested prompt templates (text)
- variables/slots (and whether they are locked)
- chain structure (order, enabled/disabled nodes, branching if supported)
Commit behavior:
- writes a `prompt_set` artifact (and optionally a `ui.prompt_chain` artifact) with provenance back to the closure

### 4.4.1 Context Graph (SynTree)
**Goal**: users can inspect and control what context an AI receives and why.

Editable before commit:
- nodes, typed relationships, annotations, and provenance corrections
- named context sets, traversal rules, priorities, pins, and budget policy
- AI-proposed links, clusters, contradictions, splits, and merges

Preview must show:
- the semantic graph diff being proposed
- included context, ordering, inclusion reasons, omissions, and estimated budget
- affected context sets and Prompt Chain bindings

Commit behavior:
- writes a new immutable `ui.context_graph` version with provenance
- never silently rewrites a legacy graph or rebinds a committed Prompt Chain
- keeps layout/viewport changes separate from semantic graph changes

Post-run inspection:
- may show deterministic inclusion, omission, traversal, and citation facts
- must label influence/attention claims as heuristic unless supported by reliable
  provider evidence

### 4.4.2 Live Thinking Map (Workshop Catalyst)
**Goal**: participants and facilitators can see and shape an evolving account of
causes, effects, opportunities, and workshop outcomes.

- Transcript- or model-derived items enter as visible proposals.
- Participant statements, AI inferences, and external evidence remain visibly
  distinct.
- The facilitator can accept, edit, reject, or defer proposed items and
  relationships.
- Commit creates a new `ui.workshop_thinking_map` version; it does not convert the
  map into `ui.context_graph`.
- Approved decisions, risks, owners, and next steps enter the Session Record or
  ClosureBus only through explicit Workshop Catalyst actions.
- The map must not feed specialist prompts without a visible, revocable choice.

### 4.4.3 Workshop buckets, Session Record, and paths

- Hidden specialists produce inspectable proposal summaries, not votes or
  decisions. Workshop Catalyst presents one synthesized preview per turn.
- The AI Assistant offers a collapsed-by-default, revocable reasoning disclosure
  showing retained specialist summaries and provenance/status only. It never
  exposes chain-of-thought and must label unavailable or degraded traces.
- Specialist concerns/options cannot create canonical closure. Participant and
  facilitator-visible voting plus explicit `/vote` and `/decide` remain
  authoritative.
- Extracted bucket and Session Record updates enter as diffs against the last
  reviewed state.
- The facilitator can accept, edit, reject, or defer each proposed change.
- Facilitator-authored text wins when a later model proposal conflicts with it.
- Rejected and deferred proposals remain recorded so the same suggestion is not
  silently repeated.
- Path comparison always includes a visible do-nothing path.
- Each path labels its evidence status. Missing evidence is shown as `none`, not
  hidden or inferred.
- Selecting or combining a path does not create closure until the facilitator
  previews and commits it.
- Summary and path commits create new `ui.workshop_summary` and
  `ui.workshop_path_set` versions with provenance and previous-version links.

Stage 7 implementation status: the Session Record uses scene-authored editable
sections and a separate proposal ledger. `Update Workshop Notes` creates
proposal rows only; per-item review actions cannot persist. Preview renders the
complete resulting summary and semantic diff without mutation. Commit is a
separate explicit action, creates one immutable `ui.workshop_summary` version,
and leaves a failed local draft visibly uncommitted and retryable. Exports use
the last committed summary reference when present and label the legacy path as
an uncommitted fallback otherwise.

Stage 8 implementation status: the Map preset contains a WC-owned
Causes/Effects/Opportunities projection over the Shared Graph Workspace
envelope. Transcript and synthesis inputs arrive as batched incremental
suggestions with visible source labels; they never commit themselves. The
facilitator reviews items, previews the semantic diff, then explicitly commits a
versioned `ui.workshop_thinking_map`. Hub failure retains the reviewed local
payload for retry without advancing lineage. Approved outcomes route to the
Session Record or ClosureBus only through explicit actions. The visible
specialist-context toggle defaults off, is revocable, records a trace, and can
expose only the last committed map.

Stage 9 implementation status: Compare Paths is a scene-authored part of the
Review workspace. Imported or record-derived candidates remain proposals until
the facilitator accepts, edits, rejects, or defers them. Every committable
comparison contains exactly one reviewed do-nothing path with stated outcomes,
risk, assumptions, uncertainty, and time horizon. Missing evidence is displayed
as `none`; retrieval failure is displayed as degraded or unavailable. Selection
and named combinations remain drafts until Preview and Commit. Hub persistence
is followed by a separate explicit ClosureBus action. Failure at either seam
remains visible and retryable without a false closure claim. Committed outcomes
enter the editable Session Record only when the facilitator invokes the route
action.

### 4.5 Render Recipe Editor (SynPunkt mode: generation orchestration)
**Goal**: user controls how closures become images.
Editable:
- mapping from prompt-set → workflow preset(s)
- workflow parameter overrides (seeds, sampler choices, etc.)
- batching rules
Commit behavior:
- writes a render-recipe artifact (workflow hash + overrides + links to prompt-set)
- submitting a render produces generated image artifacts with provenance

### 4.6 SynDeck (SynPunkt mode: presentation)
**Goal**: humans curate and perform closures.
Unified model:
- Outline (deck) and Edgeless/Prezi navigation are two views over one “SynDoc” schema.
Editable:
- text blocks, images, layout
- spatial arrangement (frame positions) and camera path
Commit behavior:
- writes SynDoc artifacts (and optionally HTML exports as artifacts)

### 4.7 Story Stage (SynPunkt mode: performance)
**Goal**: closure-driven staging.
Modes:
- 2D mode now (sprites/backgrounds)
- 3D mode later (world + characters), still closure-driven
Editable:
- cast selection, beats, camera, pacing, gating rules

---

## 5) “Human override” rules (guardrails)
- **Never auto-commit** closures, prompt chains, or render recipes without explicit user action.
- **Always allow edits** to suggested prompts and recipes *before commit* (unless a field is intentionally locked for determinism).
- **Always show** what a commit will change (preview) and how to roll back (version history).
- **Prefer branching** over overwriting when exploring alternatives (“fork closure”).

---

## 6) Implementation notes (pragmatic)
- Keep v0 UI minimal but complete: a small number of panels with strong inspectability beats many half-finished surfaces.
- Treat “editable by default” as the primary defense against black-box drift.
- Record user decisions as first-class events/artifacts so the system can learn from what users reject/accept.

