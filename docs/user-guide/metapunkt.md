# Metapunkt — Orchestrator & Agent Coordination

Metapunkt (`addons/metapunkt/`) is the **orchestration layer** in the Synesyn stack. It coordinates multi-agent workflows, routes tool and provider calls, manages capability permissions, and records session audit trails so that facilitators can see and steer what the system is doing.

*(The name **Metapunkt** is used in three ways across the project: the **Metapunkt method** is the foresight practice, the **`metapunkt` addon** described on this page is the orchestration layer, and **Metapunkt** is the R&D organisation.)*

---

## What the Metapunkt addon does

### 1) Agent coordination (SLOP protocol)
- Coordinates multi-agent workflows using **SLOP** (Simple Low-Overhead Protocol) and behaviour trees.
- Keeps agent actions visible and interruptible: facilitators can inspect agent status, pause execution, or override a step rather than treating orchestration as a black box.
- Works alongside **SynTree**, which authors ensembles and prompt chains, while Metapunkt wraps them with runtime contracts, permissions, and audit logging.

### 2) Tool routing and capability management
- Routes capability requests (LLM calls, voice synthesis, image rendering, sensor ingestion) to the configured provider (Hub, direct API, or local service).
- Defines the **capability pack** model: versioned bundles that declare tools, permissions, and optional UI panels without modifying the core Godot project.

### 3) Permissions and secret isolation
- Capabilities declare the permissions they require (such as network access or file read/write scopes) so they can be reviewed before enabling.
- API keys and tokens are stored in local runtime configuration outside capability packs, so secrets can be rotated and are never bundled into shared packs.

### 4) Session provenance and audit trails
- Emits audit entries with **correlation IDs** across tool calls and capability actions.
- Allows a facilitator or reviewer to trace why an output was produced and which provider, model, or tool call was involved.

---

## Role in the Metapunkt pipeline

Across the four-stage [facilitator workflow](facilitator-workflow.md), Metapunkt sits underneath the user-facing tools:

1. **Sense** (SynTree curates sources) → routes content and context-building calls.
2. **Structure** (SynAxes projects and clusters) → coordinates multi-step analysis jobs.
3. **Synthesize** (SynAxes commits closures) → records provenance and correlation IDs on committed artifacts.
4. **Stage** (ScenSyn and SynPunkt) → coordinates specialist batches, voice synthesis, and asynchronous render jobs.

---

## Capability packs

Metapunkt's extension model packages reusable capabilities as versioned bundles containing:
- **Tools**: structured operations that agents can invoke (for example session summarisation or render submission).
- **Optional UI panels**: Godot scenes mounted inside the Metapunkt surface to configure or drive that capability.

### Where packs live on disk
- **Pack repository (user-managed source folders):** `Documents/Synesyn/PacksRepo/...`
- **Installed packs (managed by Synesyn):** `Documents/Synesyn/synesyn/packs/<pack_id>/<version>/...`

Keeping packs under `Documents/Synesyn/` (ADR 0014) means you can inspect and back them up in your file manager in both editor runs and packaged builds.

### Example pack manifest
```yaml
pack_id: "workshop_export"
version: "1.0.0"
capabilities:
  - id: "export_session_bundle"
    type: "tool"
    permissions: ["file:write:/Documents/Synesyn/Exports/"]
    ui_panel: "res://packs/workshop_export/export_panel.tscn"
```

---

## Opening Metapunkt

1. From the Synesyn launcher, click **Synesyn Tools** (or click **Tools** from ScenSyn's home screen).
2. Select the **Metapunkt** tab.

From there you can inspect active orchestration status, toggle available capabilities on or off, and review the session audit log with its correlation IDs.

---

## Current state

- **Working today:** core workflow orchestration, tool and provider routing, correlation-ID audit logging, pack directory resolution under `Documents/Synesyn/`, and basic capability enable/disable controls.
- **Work in progress:** the full end-to-end UI wizard for installing, validating, and configuring external capability packs from zip archives, along with dedicated participant-consent capture dialogs.

---

## Conceptual grounding

In the Metapunkt method, AI is treated as both **mirror** and **instrument**:
- **Mirror**: surfacing patterns, tensions, and assumptions present in a group's shared material in a form that can be audited.
- **Instrument**: helping a group rehearse and test possibilities while keeping closure—the decision of what holds—in human hands.

---

## See also

- **[AI Orchestration, Packs, and Godot Dev Agent](../developer-guide/ai-orchestration-and-godot-dev-agent.md)**: how SynTree ensembles, prompt chains, and Metapunkt packs fit together.
- **[Metapunkt synterfaces and bindings](../implementation_docs/Metapunkt_Synterfaces_and_Bindings.md)**: the normative binding contract.
- **[SynPunkt](./synpunkt.md)**: consumes orchestrated render jobs and produces provenance-tracked presentations.
- **[ScenSyn](./scensyn.md)**: uses the orchestration layer for specialist synthesis, character turns, voice, and rendering.
