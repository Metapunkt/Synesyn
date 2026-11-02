# LatentSubstrate — Data Model & Provenance Rules (v0)

**Status**: Draft-but-normative for initial implementation  
**Goal**: Provide a concrete, minimal canonical model that supports “latent reality” in practice without overengineering.

---

## 1) Core principles

- **Everything important is an Artifact**: if it matters, it is stored and referenced, not recomputed ad-hoc.
- **Everything derived must be traceable**: derived artifacts MUST link back to inputs and tool versions.
- **Versioning is cheap; ambiguity is expensive**: prefer immutable artifacts + new versions over in-place edits.

---

## 2) Canonical IDs and naming

All resources use stable IDs with prefixes:
- `sess_` sessions
- `evt_` events
- `ent_` entities
- `rel_` relations
- `art_` artifacts
- `job_` jobs

IDs can be ULID/UUID; must be globally unique.

---

## 3) Minimal resource types

### 3.1 Session
Represents a bounded run (workshop, kiosk session, rehearsal, batch dreaming run).

Minimum fields:
- `id`, `created_at`, `workspace_id` (optional), `app_id` (e.g., `scensyn`)
- `scenario_id` and `scenario_version` (or file hash)
- `participants` (human + agent identifiers)
- `metadata` (freeform)

Consent/retention flags (recommended fields in `metadata`, v0):
- `consent.local_retention` (bool; local storage on/off)
- `consent.cloud_retention` (bool, opt-in; cloud upload/sync on/off)
- `consent.voice_transcription` (bool; required if STT is used)
- `consent.save_recordings` (bool, opt-in; controls whether `audio.input` may be persisted)
- `consent.analytics` (bool, opt-in; allows aggregate analytics if/when implemented)

Default guidance:
- `consent.save_recordings` should be **false** unless explicitly enabled by the user.
- If `consent.voice_transcription` is true but `consent.save_recordings` is false, store **transcript-only** by default.

### 3.2 Event
Time-ordered facts (sensor update, user turn, agent output, render progress).

Minimum fields:
- `id`, `session_id`
- `event_type`
- `source_id`, `seq`, `t_device` (optional), `t_received`
- `payload` (JSON)

### 3.3 Entity
Named “things” in the latent world: concept, character, node, signal, cluster, topic, prompt template, etc.

Minimum fields:
- `id`, `entity_type`
- `name` (optional), `summary` (optional)
- `tags` (list)
- `created_at`, `updated_at`

### 3.4 Relation
Typed edge between two entities.

Minimum fields:
- `id`, `relation_type`
- `from_entity_id`, `to_entity_id`
- `weight` (optional), `metadata` (optional)

### 3.5 Artifact
Immutable outputs: texts, images, audio, JSON blobs, embeddings, projections, cluster results, “closures”.

Minimum fields:
- `id`, `artifact_type`
- `uri` (file://, s3://, http(s)://) OR `inline_json` for small payloads
- `hash` (content hash for dedupe)
- `created_at`

Artifacts should be stored with clear type taxonomy, e.g.:
- `text.prompt`, `text.dialogue_turn`, `text.summary`
- `text.transcript` (STT output)
- `image.generated`, `image.input`, `image.annotation`
- `audio.tts`
- `audio.input` (optional raw recording; only if explicitly enabled + consented)
- `json.workflow`, `json.metrics`
- `json.lipsync` (optional lipsync keyframes for spoken lines)
- `vector.embedding`
- `coords.projection_2d`, `coords.projection_3d`
- `graph.cluster_result`, `graph.bridge_result`
- `ui.closure` (SynAxes saved view/slice/constraint)
- `ui.workshop_closure` (session capture committed through the ClosureBus; see ADR 0026)
- `ui.syndoc` (SynDeck document: outline + edgeless canvas + camera paths)
- `ui.context_graph` (SynTree-published context selection graph for downstream analysis)
- `ui.workshop_thinking_map` (Workshop Catalyst's reviewed live thinking-map snapshot)
- `ui.graph_layout` (optional non-semantic layout state for a graph artifact/version)
- `ui.prompt_chain` (SynTree-authored prompt program: blocks + slots + rules; versioned)
- `json.context_execution_trace` (SynTree compiler/retrieval execution record; versioned)
- `json.workshop_transcript_segment` (original STT segment plus correction lineage)
- `json.workshop_specialist_trace` (privacy-controlled hidden-synthesis inputs)
- `ui.workshop_summary` (facilitator-reviewed Session Record snapshot)
- `ui.workshop_path_set` (facilitator-reviewed path comparison and selection)

### 3.6 `ui.context_graph` (existing schema v1)
`ui.context_graph` is a versioned snapshot of a user-curated context graph authored in SynTree and published to the substrate.

Minimum fields (JSON payload):
- `schema_version` (int)
- `name` (string, optional)
- `nodes`: list of nodes; at minimum include content sources with:
  - `id` (stable node id; typically SynTree `source_id`)
  - `kind` (e.g. `content_source` or `stack`)
  - `meta` (name/path/origin/type flags as needed)
- `edges`: list of edges:
  - `from`, `to`, and the existing `kind` discriminator (currently
    `stack_member`)
- `selection`:
  - `active_source_ids` (array of source ids)

SynAxes consumes `ui.context_graph` as a dataset descriptor; it does not scrape SynTree internals directly.

#### 3.6.1 Shared Graph Workspace envelope (v1)

Graph-capable clients may reuse the shared Graph Workspace implementation, but
their artifacts retain product-owned semantics and artifact types. A shared code
model does not make `ui.context_graph` and `ui.workshop_thinking_map`
interchangeable.

The common semantic graph envelope is versioned independently from each
product-owned artifact contract:

- `schema_version` (int; version of the product-owned artifact contract)
- `graph_schema_version` (int; Shared Graph Workspace envelope version; initial
  value `1`)
- `graph_kind` (string; contract discriminator such as `context_graph` or
  `workshop_thinking_map`)
- `name` (string, optional)
- `nodes` (array):
  - `id` (stable string within the artifact lineage)
  - `kind` (product-owned controlled string)
  - `label` (human-readable string)
  - `status` (`committed`, `suggested`, `accepted`, `edited`, or `rejected`)
  - `annotations` (object, optional)
  - `provenance_refs` (array of artifact/event/trace/source references; empty only
    when provenance is explicitly unavailable)
- `edges` (array):
  - `id` (stable string within the artifact lineage)
  - `from`, `to` (existing node ids)
  - `relation` (product-owned controlled string)
  - `status` (same review-state vocabulary as nodes)
  - `notes` (string, optional)
  - `confidence` (number in `[0,1]`, optional; confidence is not verification)
  - `provenance_refs` (array)
- `layout_ref` (artifact id for optional `ui.graph_layout`; absent when layout is
  local-only)
- `previous_version_id` (artifact id, optional)

Rules:

- Canonical graph commits are immutable artifact versions.
- AI-produced nodes/edges remain proposals until an explicit human commit creates
  a new canonical version.
- `from`/`to` supplies canonical direction. Display inverses do not require a
  duplicate stored edge.
- Layout, viewport, zoom, transient selection, and focus state are non-semantic
  and must not affect semantic graph diff/hash behavior.
- Deleting a node must either remove its incident edges in the same proposed
  change or fail validation.
- Readers must reject or visibly quarantine dangling edges, duplicate ids, and
  unknown required discriminators; they must not silently repair canonical data.
- Cross-product conversion requires an explicit, user-visible operation that
  creates a new artifact with provenance to its source.

`ui.graph_layout` minimum fields:

- `schema_version`
- `graph_artifact_id` and, when applicable, `graph_version_id`
- `positions` (`node_id` → `{x,y}`)
- optional collapsed groups and viewport defaults

#### 3.6.2 `ui.context_graph` v2 additions

Existing SynTree publishers already emit `schema_version: 1` using the minimal
shape above. That schema remains readable. An enhanced v2 SynTree Context Graph
adds `graph_schema_version: 1` and:

- node kinds such as `content_source`, `stack`, `chunk`, and `derived_content`;
- typed relationships governed by the Context Graph contract (structural,
  dependency, evidential, and semantic relations);
- `context_sets`, each with a stable id, entry-node ids, allowed relationship
  types, traversal depth, activation rules, and budget policy;
- transparent activation modes and priorities;
- optional links to context-compilation and execution-trace artifacts.

Activation policy v1 is deterministic and inspectable. A node may carry an
`activation` object with `mode`, optional `conditions`, and optional `priority`.
Allowed modes are `always`, `when_relevant`, `conditional`, `manual_only`, and
`excluded`. Conditions may match only explicit inputs (`tags`, `thread_scope`,
`app_scope`, `prompt_chain_id`, and `slots`); they must not invoke an LLM or use
hidden relevance scoring.

Activation precedence is:

1. rejected graph records are omitted;
2. an explicit user pin includes a non-rejected node;
3. `excluded` omits the node;
4. `always` includes it;
5. `manual_only` includes it only when it is an explicit context-set entry;
6. `conditional` includes it only when every declared condition matches;
7. `when_relevant` includes it when graph traversal reaches it.

The legacy Active checkbox is a compatibility projection onto the entry-node
list of the generated `active-sources` context set. It is not a second,
conflicting node activation mode. Context-set policy overrides compiler preset
defaults; explicit preview options override context-set policy; an explicit
user pin has the final inclusion precedence described above.

Legacy parent/child and bare stack edges must be migrated deterministically by a
compatibility reader before v2 is written. Reading a legacy artifact must not
silently overwrite it.

Context Graph relationship vocabulary v1 is controlled:

- structural: `contains`; `part_of` is an authoring/display inverse that is
  canonicalized by swapping endpoints and storing `contains`;
- dependency: `depends_on`, `precedes`;
- evidential: `supports`, `contradicts`, `derived_from`;
- semantic: `refines`, `example_of`, `related_to`.

Each stored edge also carries `created_at` and `updated_at` ISO-8601 timestamps.
An edge id remains stable while its relation, endpoints, notes, confidence,
provenance, or review status is edited. Structural containment must be acyclic;
dependency, evidential, and semantic relations may form cycles. Hierarchy reads
only canonical `contains` edges (plus its legacy parent/child compatibility
projection) and must not reinterpret other edge types as containment.

Within editable SynTree source files, rich edge records are stored under
`content.context_graph_edges`. During the compatibility period, `contains`,
`depends_on`/`precedes`, and `related_to` mutations are mirrored to the existing
children/parents, dependencies, and associations arrays respectively. Rich
records remain authoritative for distinctions, annotations, timestamps, and
provenance that those legacy arrays cannot express.

#### 3.6.3 `ui.workshop_thinking_map` v1

`ui.workshop_thinking_map` is a versioned Workshop Catalyst snapshot authored
through facilitator-reviewed live proposals.

Its product `schema_version` begins at `1` and it includes
`graph_schema_version: 1`. In addition to the shared graph envelope it includes:

- `session_id`
- `scenario_id` and Session Type/Collection references where available
- workshop-owned node kinds/categories including `cause`, `effect`,
  `opportunity`, `question`, `decision`, `risk`, `owner`, and `next_step`
- source classification distinguishing participant statements, AI inference,
  and externally supported evidence
- references to transcript segments, Session Record entries, closures, and
  specialist synthesis traces where applicable

The artifact does not authorize automatic injection into specialist prompts.
Prompt use requires a separate visible user choice and trace. Approved outcomes
enter the Session Record or ClosureBus through Workshop Catalyst commands, not by
reinterpreting the artifact as `ui.context_graph`.

The live specialist batch may emit a transient `map_candidates` envelope before
facilitator review. This is not a separate canonical artifact. Envelope version
1 contains:

- `schema_version: 1`;
- `map_candidates[]`, each with a stable/local `id`, controlled `category`
  (`cause`, `effect`, `opportunity`), concise `proposition`, `source_class`,
  non-empty `source_refs[]`, brief `rationale`, numeric `confidence` in `[0,1]`,
  and controlled `evidence_status`;
- `facilitator_cues[]` for process guidance that must not become semantic nodes;
- rejected-candidate reason codes retained in the specialist trace without
  private chain-of-thought.

Unknown categories, vague/empty propositions, malformed provenance,
instruction-like/meta content, and duplicate semantic keys are rejected.
Malformed or degraded batches produce no map candidates. Valid candidates enter
the map through the Workshop-owned command seam as `suggested`; they are never
auto-committed or auto-routed to the Session Record.

#### 3.6.4 Workshop Catalyst review artifacts (v1; staged implementation)

All records use the standard artifact envelope, immutable versions, provenance,
and session references. The `json.workshop_specialist_trace` writer and Hub
validator are implemented for Stage 5; the `json.workshop_transcript_segment`
writer and Hub validator for Stage 6; the `ui.workshop_summary` writer and
validator for Stage 7; and the `ui.workshop_thinking_map` writer and validator
for Stage 8. Stage 9 implements the `ui.workshop_path_set` writer, compatibility
reader, and Hub validator.

Stage 8 keeps live node/edge commands incremental and local until explicit
facilitator review. Preview computes a semantic diff without mutation. Commit
uses the generic artifact seam, includes facilitator provenance and
`previous_version_id`, and advances local lineage only after Hub success. A
failed write retains the exact reviewed payload for retry. Specialist prompt use
is absent by default and can include only the last committed map after a visible
toggle creates a trace reference.

`json.workshop_transcript_segment` schema v1 stores:

- `schema_version: 1`, stable `version_id`, `session_id`, `segment_id`,
  `origin: user`, `capture_started_at`, `capture_completed_at`, and `created_at`;
- immutable provider `original_text`, explicitly confirmed `submitted_text`,
  provider/model metadata, and optional `source_audio_artifact_id`;
- empty `corrected_text`, `correction_reason`, and `previous_version_id` in the
  original version;
- non-empty `corrected_text`, `correction_reason`, `corrected_at`, and
  `previous_version_id` in each correction version;
- consent and retention objects. Raw audio may be referenced only when
  `consent.save_recordings` is true and `retention.raw_audio_retained` is true.

The generic Hub artifact route validates this shape, normalizes the earlier
draft `captured_at` alias on read/commit, and rejects embedded raw audio,
credentials, silent correction fields on an original version, or corrections
without lineage. A correction changes the transcript record only; it does not
rewrite `StoryState` or imply a second conversational turn.

`json.workshop_specialist_trace` stores:

- `schema_version`, `session_id`, `turn_id`, and specialist contribution records;
- specialist role ids, contribution text or a redacted hash/reference, model id,
  and timestamps;
- the synthesized response reference and review/retention status;
- generation and persistence failure/degraded status, including truthful Hub
  unavailability;
- accepted structured map candidates, facilitator cues, and safe rejection
  reason codes from the same batched operation;
- privacy flags confirming that credentials and chain-of-thought are absent.

This trace is not a workshop decision. Access follows the configured privacy
policy and the user-facing, collapsed-by-default reasoning control. Specialist
records contain concise role outputs only. Trace persistence is best-effort and
must not block or invalidate a successful synthesized chat response.

`ui.workshop_summary` stores:

- `schema_version`, `session_id`, and proposal/review status;
- arrays of decisions, risks, open questions, owners, and next steps with stable
  ids and provenance references;
- accepted, edited, rejected, and deferred proposal decisions;
- facilitator identity/reference, `previous_version_id`, and closure references.

The five reviewed arrays contain objects with stable `id`, editable `text`,
`provenance_refs`, normalized provenance, reviewer identity, facilitator-edit
status, and update timestamp. Stage 7 commits only
`review_status: facilitator_reviewed`; AI extraction cannot call persistence.
Rejected/deferred exact and semantic suggestion keys remain in the local review
ledger and their decisions are included in later summary versions. A failed Hub
write does not advance `previous_version_id` or discard the retry payload.

`ui.workshop_path_set` stores:

- `schema_version`, session/scenario and Session Type/Collection references,
  facilitator provenance, `previous_version_id`, and stable path ids;
- each path's title/label, outcomes, biggest risk, assumptions, uncertainty, time
  horizon, `is_do_nothing`, proposal/review state, provenance, timestamps,
  optional `previous_path_id`, and evidence references;
- `evidence_status` as `supported`, `partial`, `none`, `degraded`, or
  `unavailable`; an empty reference array cannot be labelled supported;
- exactly one reviewed do-nothing path, which carries the same required outcome,
  risk, assumption, uncertainty, and time-horizon fields as other paths;
- one explicit facilitator selection, either a single accepted path or a named
  combination of at least two accepted paths;
- proposal decisions, retrieval trace/context-pack metadata, and
  `store_trace_ids`.

Preview computes the complete resulting comparison and semantic diff without
mutation. The generic Hub artifact write receives an empty `closure_ref`; only
successful explicit ClosureBus delivery establishes the local closure reference
and advances the client's committed lineage. If Hub persistence fails, the exact
payload remains retryable. If ClosureBus delivery fails after Hub persistence,
retry reuses the returned artifact id and does not create a duplicate artifact.

Thinking-map items remain nodes inside `ui.workshop_thinking_map`; they are not
separate canonical artifacts. Their stable ids, proposal states, provenance, and
transcript/synthesis references follow sections 3.6.1 and 3.6.3.

### 3.7 `ui.prompt_chain` (schema v1)
`ui.prompt_chain` is a versioned, human-editable “prompt program” authored in SynTree.
It is designed to be reusable across threads and apps, while still allowing thread-local drafts in the UI.

Minimum fields (JSON payload):
- `schema_version` (int)
- `name` (string)
- `blocks` (array):
  - `id` (string, stable within the chain)
  - `label` (string)
  - `enabled` (bool)
  - `text` (string; prompt content; may include slot variables like `{{slot_name}}`)
- `slots` (object, optional):
  - key = slot name → value = default value (string) OR structured slot definition (v1)
- `notes` (string, optional)
- `context_binding` (object, optional):
  - `context_graph_artifact_id` (string; required for committed bindings)
  - `context_graph_version_id` (string, optional immutable version pin)
  - `context_set_id` (string, optional owner-qualified set id)
  - `owner_source_id` (string, used for scope validation)
  - `compiler_preset` (`full`, `balanced`, or `minimal`)
  - `max_tokens` (int)

Each block may additionally carry `context_override` with
`traversal_depth`, `allowed_relationship_types`, and `pinned_node_ids`.
Overrides are declarative and do not turn the linear Prompt Chain editor into a
graph editor. A committed binding must never silently move to another graph,
version, owner scope, or context set. Binding edits follow the same
Propose → Preview → Commit → Version boundary as block edits.

Recommended metadata/provenance (artifact metadata, not necessarily inside payload):
- `provenance.generated_by`: `syntree.prompt_chain_editor@<version>`
- `provenance.source_artifacts`: optional links to `ui.context_graph` / `ui.closure` / other inputs
- `provenance.app_id`: which app/surface created it (e.g. `scensyn`, `readymade`, `syntree_editor`)

### 3.8 `json.context_execution_trace` (schema v1)

`json.context_execution_trace` records the deterministic context package used
for one model request without claiming that the model attended to, relied on,
or was influenced by every included item.

Minimum fields:

- `schema_version: 1`
- stable `run_id` and `created_at`
- `thread_scope`, `thread_id`, `context_path`
- `graph_artifact_id`, `graph_version_id`, and `context_set_id`
- `prompt_chain_id` and optional prompt-chain artifact/version references
- `model_id`, `provider_id`, and estimator identity
- compiler `policy`, token estimate/budget, ordered `included_nodes`, and
  explained `omitted_nodes`
- `compiled_text_hash`; raw compiled text is not stored in the canonical trace
- stable `message_refs` for user/assistant messages
- optional STFX Store trace/context-pack references
- optional resulting Hub artifact ids

Included/omitted status and traversal paths are deterministic facts. Citation
and provider-supplied usage may be recorded as facts when available.
Labels such as `apparently_unused` are heuristic and must be explicitly marked
as such. Trace persistence is best-effort and must never block or invalidate a
successful chat response.

---

## 4) Provenance (normative)

Every derived artifact MUST include provenance:

### 4.1 Provenance record
- `produced_by`:
  - tool name + version (e.g., `synaxes@0.1`, `syntree_voice@0.1`, `comfyui@<ver>`)
  - model identifiers where relevant (LLM model name, embedding model name, checkpoint name)
- `inputs`:
  - list of `artifact_id` and/or `entity_id` and/or `event_id`
- `parameters`:
  - seeds, workflow hash, config snapshot, thresholds, reduction method, etc.
- `timestamp`

#### 4.1.1 Graph record provenance

Every committed Context Graph node and rich edge carries a normalized
`provenance` object in addition to compatibility `provenance_refs`:

- `authorship_kind`: `imported_quotation`, `user_authored`,
  `deterministic_summary`, `ai_summary`, `ai_inference`, or `unknown`
- `origin_ref`: stable source/entity/event/trace reference, or `unknown`
- `source_location`: optional `{uri, line_start, line_end, fragment_id}`
- `source_artifact_id` and `source_version_id` when artifact-backed
- `author_id`, `produced_by`, `model_id`, and `created_at` when recorded
- `derivation_refs`: stable references to inputs used to produce the record
- `review_status`: `unreviewed`, `reviewed`, `needs_review`, or `unknown`
- `evidence_status`: `unsupported`, `supported`, `conflicting`, or `unknown`

`evidence_status` is independent of edge `confidence`: confidence records an
author/model assessment, while evidence status records reviewable support.
Missing values are stored as `unknown` or omitted where explicitly optional;
clients must never infer authorship, evidence, or source location from content
style. Node split/merge and edge edits preserve derivation references and add
the prior record id rather than replacing provenance.

#### 4.1.2 Context Graph proposal records

AI-assisted graph changes remain outside canonical `nodes` and `edges` until a
human explicitly commits a reviewed preview. A proposal record contains:

- stable `id`, `proposal_type`, and constrained `operation`
- `status`: `suggested`, `accepted`, `edited`, `rejected`, or `deferred`
- proposed `payload`, rationale, evidence references, and affected record ids
- model/provider, prompt/configuration hash or snapshot, and confidence
- created/reviewed timestamps and optional reviewer decision note

Model-facing services may create `suggested` proposals only. Review actions may
change proposal status and payload but cannot call graph persistence. A separate
human-invoked commit command materializes accepted proposals into a preview,
validates and displays its semantic/context-budget impact, and commits a new
`ui.context_graph` version. Rejection/defer decisions are retained so an
identical proposal is not resurfaced without new evidence.

### 4.2 “Do not lose determinism” rules
If ComfyUI output matters, provenance MUST include:
- workflow JSON hash (API-format JSON)
- seed(s) and any offsets used
- model/checkpoint identifiers
- node parameter patch set (what was changed at runtime)

---

## 5) Storage backends

### 5.1 Local-first (default)
- SQLite database for metadata (sessions/events/entities/relations/artifact index/provenance)
- File-based artifact store:
  - `services/synesyn_hub/data/artifacts/<type>/<artifact_id>.<ext>`

### 5.1A STFX Store boundary
The LatentSubstrate remains the operational substrate for sessions, events, entities, relations, jobs, artifact indexes, and cross-app provenance queries.

The STFX Store is the canonical file-backed memory substrate for source/chunk/memory/closure/trace/context-pack records. For those records, SQLite and artifact indexes are mirrors, accelerators, or compatibility handles. If a generated index, SQLite mirror, or artifact index disagrees with an STFX Store canonical record, the store record wins.

Embeddings, projections, clusters, bridges, and hubs are generated analytic artifacts. They may inform memory work, but they do not become canonical memory unless a human or app commits an explicit STFX memory or closure record with provenance.

### 5.2 SaaS mode (future)
- Postgres for metadata
- Object storage for artifacts (S3-compatible)

The API should hide backend differences.

---

## 6) Projections and “closures” (SynAxes → SynTree → SynPunkt loop)

### 6.1 Projection artifact
Represents a coordinate layout computed by SynAxes or edited by SynPunkt.

Required metadata:
- `projection_id`, `method` (pca/umap/tsne/manual)
- `input_set` (which entities/artifacts were projected)
- `dim` (2 or 3)
- coordinate map: `{ entity_id: [x,y,(z)] }`

### 6.2 Closure artifact (saved view/slice)
A closure captures a navigable “slice” of latent reality:
- selection criteria (entity ids, tags, filters)
- constraints (pinned nodes, locked regions, narrative intent)
- time window (session range)
- camera/view state (optional; used by SynPunkt/SynDeck/Story Stage as a performance surface)

Closures must be immutable artifacts; edits create new versions.

When a closure is part of STFX memory, symbolic selection, or repairable retrieval context, it should also be committed as an STFX Store closure record under `stfx_store/closures/`. The LatentSubstrate `ui.closure` artifact remains the operational/provenance mirror and cross-app handle; the store closure record is the canonical memory form.

**Authorship principle** (normative UX): the system may propose closure drafts, but **humans commit closures** (see `Human_Agency_UX_Contract.md`).


