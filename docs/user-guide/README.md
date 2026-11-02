# Synesyn User Guide

Welcome to the Synesyn user guide. This documentation helps you understand and use the Synesyn platform for co-creative foresight, speculative scenario synthesis, and collective imagination work.

For the full product, runtime, and documentation structure, see
[`../SYSTEM_MAP.md`](../SYSTEM_MAP.md).

---

## What is Synesyn?

**Synesyn** is a **local-first, artifact-centric platform** that enables collaborative interaction with AI over shared material, building up a traceable record that each session can build on. Combining **artistic praxis, speculative design and AI-assisted sense-making**, it implements the **Metapunkt method**: reading backward to archetypal patterns held in data and remembering forward into speculative futures, in a manner that can aid decision making.

Synesyn is designed for:
- **Foresight practitioners**: Running structured scenario workshops, design fiction sprints, or generative theatre sessions
- **Artists and speculative designers**: Exploring cultural futures, staging embodied rehearsals, creating provenance-tracked artifacts
- **Researchers and civic innovators**: Building long-term collective learning beyond one-off workshop deliverables
- **Organizations**: Strategic foresight work that is both **expansive** (creative, plural) and **accountable** (auditable, reusable)

---

## Core principles

### 1) Local-first, optional Hub
- Your work is stored on your own machine, in ordinary folders under
  `Documents/Synesyn/`, and there is no account, subscription or telemetry.
- The **Synesyn Hub** (optional Python backend) adds artifact storage, job orchestration, voice services, and realtime event streaming.
- Local-first is not the same as offline. By default, session text goes to a
  hosted model provider, and spoken output goes to Microsoft's Edge voices. A
  fully offline session is possible using Ollama and the offline voice fallback,
  at some cost in quality. [Privacy and data](privacy-and-data.md) sets out
  exactly what is sent where.

### 2) Artifact-centric paradigm
- All generated outputs (prompts, images, scenarios, projections, closures) are stored as **versioned artifacts** with **provenance** (who/what/when/how).
- Artifacts are reusable: outputs from one session can feed into future sessions, enabling long-term collective learning.

### 3) Co-creation, not just content generation
- Synesyn supports **sustained co-creation across diverse participants and across time**.
- Artifacts re-enter future sessions; workshops build on prior work rather than starting from scratch.

### 4) Auditability without flattening creativity
- Outputs are traceable to their inputs, prompts, models, and human decisions.
- Provenance supports accountability and reproducibility, without sacrificing creative exploration.

---

## The Metapunkt pipeline

Synesyn implements a repeatable four-stage pipeline for co-creative foresight:

1. **Sense**: Gather signals, stories, archives, and lived experience (documents, interviews, sensor data, cultural artifacts).
2. **Structure**: Parse, map, and connect meaning — concepts, tensions, relationships — using embeddings, projections, and human-in-the-loop closure formation.
3. **Synthesize**: Surface patterns and "closures" (human-legible decisions that collapse ambiguity into actionable frames).
4. **Stage**: Rehearse futures through scenarios, generative theatre, spatial canvases, and prototypes; produce shareable, versioned artifacts.

This pipeline is the practical expression of **Forward Remembrance**: simultaneously reflecting backward to archetypal patterns while "remembering forward" into speculative futures.

## Facilitator workflow (practical)

New here? [Getting started](getting-started.md) covers what you need installed,
setting up model access, and opening a first session. The
[glossary](../concepts/glossary.md) is worth reading early: *closure*, *artifact*
and *specialist* all mean something specific. If you're running a workshop, the facilitator workflow is path to explore, distinct from the story catalyst flow which is structured more for narrative based interaction:

- [Facilitator workflow](facilitator-workflow.md) — the shape of a session
- [ScenSyn](scensyn.md) — the session runtime, and which session type you want
- [Workshop Catalyst facilitator manual](workshop-catalyst-facilitator-manual.md) —
  running a decision-focused workshop, in detail
- [Story Catalyst](story-catalyst.md) — running a narrative session, and its three
  scenario collections
- [Story Catalyst authoring](story-catalyst-authoring.md) — writing your own Open
  Play stories, which needs no code
- [Story Stage sprite packs](story-stage-sprites.md) — installing the optional
  character art, or supplying your own
- [SynAxes](synaxes.md) — the default path to closures, without Advanced
- [Privacy and data](privacy-and-data.md) — what to tell participants
- [Troubleshooting](troubleshooting.md) — when something misbehaves mid-session

---

## System architecture

### Clients (Godot-based)
- **The Synesyn client**: base application hodling infrastructure that runs the different components that drive the platform and the two demonstration applications - ScenSyn and ReadyMade. Package builds for the Synesyn client would be named -
  (`Synesyn.exe`, `synesyn_hub.exe`).
- **Application layers**: ScenSyn (scenario synthesis + generative theatre), ReadyMade (agentic content workflows)
- **Component tools** (exist as Godot add-ons with their own clients exposed under Synesyn Tools interface): SynTree, SynPunkt, Metapunkt, SynAxes

### Hub (Python backend)
- **synesyn_hub.exe**: Optional backend service providing:
  - **LatentSubstrate**: System-of-record for artifacts, sessions, entities, relations, provenance
  - **Job orchestration**: Rendering workflows, voice synthesis, "dreaming" (batch analysis/clustering)
  - **Realtime event bus**: WebSocket/SSE for sensor ingestion, live session events
  - **Voice services**: TTS (Edge TTS, SAPI, optional sidecar) and STT

### External services (optional)
- **Ollama**: Local LLM provider (e.g., `gemma4:26b`, `llama3.2`) for offline AI inference
- **AI model APIs**: API implementation for major AI model providers is in place, with the ability to select provider and model during session runs. 
- **ComfyUI**: Image generation engine (local or remote) for SynPunkt render workflows
- **SuperCollider**: Real-time generative audio synthesis for ambient soundscapes (OSC integration)

---

## The component tools (infrastructure)

These are crafted more as reusable addons rather than applications, though they can also be provisioned as applications as demonstrated through the Synesyn Tools interface. 

- **[SynTree](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/addons/syntree/README.md)**: Semantic assistant + context manager (technical overview; a dedicated user page is pending)
- **[SynPunkt](./synpunkt.md)**: Infinite canvas + presentation/generation surface (render workflows, Story Stage, SynDeck)
- **[Metapunkt](./metapunkt.md)**: Orchestrator + agent coordination (SLOP-native workflows, capability packs, tool routing)
- **[SynAxes](./synaxes.md)**: Pattern synthesizer + closure formation (default path: Import → Explore → Choose → Name → Commit). Packaging / developer notes: [`addons/synaxes/README.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/addons/synaxes/README.md). 

Three other components also support the platform and though they are less visible, their contribution is not any less significant: `synesyn_core`, the shared library every addon depends on, `syntree_voice`, which provides speech synthesis, transcription and
lip sync; and `story_stage` - the visual stage ScenSyn's Story Stage and the story-log
player both use.

---

## Application layers

The components above are **infrastructure**: reusable capabilities that can serve different applications. The applications below are built on them, and are examples
of how the infrastructure may be used, without being prescriptive. On building your own application with the stack, see
[building on Synesyn](../developer-guide/building-on-synesyn.md).

- **[ScenSyn](./scensyn.md)** — the session runtime, and the most developed
  application. One application, two **session types**:
    - **[Workshop Catalyst](./workshop-catalyst-facilitator-manual.md)** —
      facilitated group foresight, where AI specialists analyse out of sight and
      the group leaves with a decision record. The most thoroughly tested part of
      the project.
    - **[Story Catalyst](./story-catalyst.md)** — narrative and cultural
      exploration through characters who speak in their own voices, across three
      collections: Sustainability, Cultural Narratives and Open Play. Writing your
      own story needs no code:
      [authoring guide](./story-catalyst-authoring.md).
- **ReadyMade** — agentic content planning and document editing over a
  long-running workplan. Early and rough: see
  [`readymade/README.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/readymade/README.md)
  for what it does today, and
  [PRD-READYMADE-EDIT-SESSION](../product-requirements/PRD-READYMADE-EDIT-SESSION.md)
  for the Edit Session requirements. A dedicated user page is pending.
- **Play a Story Log** — replays a saved ScenSyn session on the Story Stage, with
  no model or hub, for showing a performance again or looping it in an exhibition.
  See [replaying a saved session](./scensyn.md#replaying-a-saved-session).
- **Synesyn Tools** — a shell that opens the SynTree, SynAxes and SynPunkt docks
  directly, without going through an application. Useful when you want the tools
  rather than an application session.

---

## Getting started

1. **[Getting Started Guide](./getting-started.md)**: First-time setup, launching Synesyn, navigating the interface
2. **[Troubleshooting](./troubleshooting.md)**: Common issues and solutions (hub not starting, voice not working, workspace errors, etc.)

---

## Conceptual background

For deeper understanding of Synesyn's conceptual foundations:
- **Latent Reality framing**: Ontological view of reality as open potential made intelligible through "closures" (human-legible decisions that collapse ambiguity). The instrument built on it is documented in [`concepts/closure-map.md`](../concepts/closure-map.md).
- **Metapunkt White Paper**: the open-core emergence engine...Held outside this repository.
- **Forward Remembrance PhD Overview**: the artistic research context and "Forward Remembrance" praxis, from the PhD project *Forward Remembrance: Exploring Latent Utopias* at the Trondheim Academy of Fine Art, NTNU. The overview document is held outside this repository; the project's provenance is summarised in the [root README](https://github.com/Metapunkt/Synesyn/blob/main/README.md#provenance).
- **Stochastic Dreams Concept Note v5**: narrative architecture including the v5.2 character redesign (Pilgrim arc, Dreaming Layer, Closure integration)...Held outside this repository.

---

## For technical overview

Start with [`SYSTEM_MAP.md`](../SYSTEM_MAP.md) for the runtime and documentation
hierarchy, then [`developer-guide/local-dev.md`](../developer-guide/local-dev.md)
to get the hub and client running.

Verification is executable rather than checklist-driven: the
[harness run specs](../technical-review/run_specs/README.md) carry their own
assertions, so running a spec both exercises a workflow and states what the
workflow is required to do. 