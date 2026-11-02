# ScenSyn Scenario Continuity Contract

**Status**: Implemented app-adapter contract  
**Scope**: ScenSyn-facing continuity state derived from app-agnostic memory context  
**Canonical upstream dependency**: `STFX_Memory_Capability_Spec.md`

---

## 1) Purpose

This document defines the first ScenSyn-specific continuity contract:

- `scensyn.scenario_continuity_state`

It is **not** part of the canonical `StfxMemory` data model.  
It is a ScenSyn-facing adapter contract that translates:

- `stfx_memory.continuity_context`

into a shape that ScenSyn can use for:

- session continuity
- scenario beat carry-forward
- narrative phase suggestion
- unresolved challenge seeding
- downstream consumers such as `vis_story`

---

## 2) Architectural position

Required flow:

`StfxMemory` -> `continuity_context` -> ScenSyn adapter -> `scenario_continuity_state`

This is the correct layering because:

- the memory capability remains symbolic and app-agnostic
- ScenSyn owns scenario/session semantics
- `vis_story` becomes one consumer of ScenSyn continuity, not the defining shape for every future consumer

---

## 3) Contract name and version

- `contract_type`: `scensyn.scenario_continuity_state`
- `contract_version`: `1`

---

## 4) Input contract

The adapter consumes:

- `stfx_memory.continuity_context`

Typical source request:

```json
{
  "document_id": "stfxmem_example",
  "chunk_path": "chapter_1.scene_a",
  "depth": 2,
  "sibling_window": 1
}
```

---

## 5) Output contract

Example response:

```json
{
  "ok": true,
  "contract_type": "scensyn.scenario_continuity_state",
  "contract_version": 1,
  "source_contract": {
    "contract_type": "stfx_memory.continuity_context",
    "contract_version": 1
  },
  "scenario_focus": {
    "document_id": "stfxmem_example",
    "chunk_path": "chapter_1.scene_a",
    "summary": "Doorway negotiation",
    "source_ref": {"kind": "file", "path": "..."}
  },
  "continuity": {
    "anchors": [
      "Doorway negotiation",
      "Assembly memory",
      "Threshold crossing"
    ],
    "latent_tensions": [
      {
        "path": "chapter_1.scene_b",
        "summary": "Threshold crossing",
        "seed_family": "alternating",
        "tension_role": "alternative_branch"
      }
    ],
    "focus_terms": ["assembly", "doorway", "threshold", "crossing"],
    "seed_emphasis": ["rhythmic", "primary"],
    "recommended_narrative_phase": "rising",
    "phase_instruction": "Use this branch to escalate complications, trade-offs, and conflicting interpretations."
  },
  "symbolic_signals": {
    "root_seed_family": "primary",
    "active_seed_family": "rhythmic",
    "expansion_depth": 2,
    "matrix_shape": [64, 64],
    "complementarity_verified": true
  },
  "state_patch": {
    "current_narrative_phase_hint": "rising",
    "unresolved_challenges": [
      "Threshold crossing",
      "Branch focus."
    ],
    "memory_context": {
      "continuity_anchor": "Doorway negotiation",
      "summary_fragments": [
        "Doorway negotiation",
        "Assembly memory",
        "Threshold crossing"
      ],
      "focus_terms": ["assembly", "doorway", "threshold", "crossing"],
      "seed_emphasis": ["rhythmic", "primary"]
    }
  },
  "prompt_cues": {
    "scenario_brief": "Doorway negotiation | Assembly memory | Threshold crossing",
    "continuity_prompt": "Use this branch to escalate complications, trade-offs, and conflicting interpretations.; Doorway negotiation; Assembly memory; assembly; doorway; threshold; crossing"
  },
  "provenance": {
    "source_ref": {"kind": "file", "path": "..."},
    "origin": "stfx_memory.adapter_contract"
  }
}
```

---

## 6) Field meanings

### 6.1 `scenario_focus`

The active branch or memory locus ScenSyn should treat as the current continuity source.

### 6.2 `continuity.anchors`

Short carry-forward fragments that should remain legible in the next beat, scene, or turn cluster.

### 6.3 `continuity.latent_tensions`

Neighboring symbolic alternatives or counter-branches that can become:

- dilemmas
- contrasting positions
- alternate scene directions
- dramatic pressure

In the Stochastic Dreams scenario (v5.2), latent tensions are narratively
framed as "what the Tapestry was dreaming between turns." The Echo character
(Keeper of Memory and Dreaming) uses these as source material for naming the
world's dreaming state. This framing operationalizes the project's Social
Dreaming concept: between closures, latent possibilities gestate, combine,
and decay.

### 6.4 `continuity.recommended_narrative_phase`

A deterministic adapter-level suggestion for where this memory branch most naturally fits in ScenSyn’s narrative phase flow:

- `setup`
- `incident`
- `rising`
- `climax`

This is a **hint**, not a forced state transition.

### 6.5 `state_patch`

A non-destructive suggested patch for ScenSyn runtime state.

The hub-side adapter does **not** directly mutate `StoryStateManager`.  
It returns a patch-like structure that ScenSyn runtime may selectively apply.

Current runtime behavior:

- ScenSyn stores the returned continuity payload in `StoryState`
- ScenSyn applies `state_patch.memory_context` as advisory continuity memory
- ScenSyn applies `state_patch.current_narrative_phase_hint` as a hint only, not a forced phase transition
- ScenSyn merges `state_patch.unresolved_challenges` into existing unresolved challenges
- ScenSyn may surface `prompt_cues` into metaprompt construction as advisory guidance

### 6.6 `prompt_cues`

Condensed continuity strings for prompt-building, director prompts, narration prompts, or downstream modules like `vis_story`.

---

## 7) Normative rules

- The contract must remain ScenSyn-specific but scenario-generic.
- It must not mention `vis_story` in the contract schema.
- It must remain derivable deterministically from `continuity_context`.
- It may add ScenSyn narrative hints, but not opaque model decisions.
- It must be usable by any ScenSyn scenario, not only Stochastic Dreams.

---

## 8) Hub route

Initial hub-facing route:

- `POST /scensyn/continuity-state/from-memory`

Purpose:

- obtain `scenario_continuity_state` directly from memory inputs without requiring the client to manually perform both translation steps

---

## 9) Downstream use

Possible ScenSyn consumers:

- runtime session orchestration
- story-state enrichment
- narrator prompt building
- scenario transition planning
- story-log summarization
- `vis_story` cycle/panel planning

The important rule is:

`vis_story` consumes this contract as one downstream specialization; it does not define it.

---

## 10) Runtime integration status

Initial ScenSyn runtime integration is now in place:

- scenario files may declare `[MEMORY_CONTINUITY]`
- ScenSyn startup may derive or write a workspace-local scenario memory source
- ScenSyn ingests that source into `StfxMemory`
- ScenSyn requests `POST /scensyn/continuity-state/from-memory`
- the resulting payload is stored as non-destructive continuity enrichment in `StoryState`

This keeps the capability layered correctly:

- `StfxMemory` remains app-agnostic
- the adapter remains ScenSyn-specific
- ScenSyn runtime consumes the adapter output without hard-coding `vis_story`

---

## 11) vis_story translator status

An initial downstream translator is now implemented without changing the core
contract schema:

- hub route: `POST /scensyn/vis-story-cycle/from-continuity`
- convenience route: `POST /scensyn/vis-story-cycle/from-memory`
- adapter builder: `build_vis_story_cycle_payload(...)`

Important constraints of this translator:

- it consumes `scensyn.scenario_continuity_state` as input
- it emits `vis_story`-shaped cycle JSON as a downstream product
- it remains deterministic and auditable
- it does not make `vis_story` a required runtime dependency for ScenSyn

ScenSyn runtime exposure is opt-in:

- scenarios may declare `[VIS_STORY]`
- if absent or disabled, nothing changes for that scenario
- if enabled, ScenSyn can export a workspace-local `vis_story` cycle JSON from
  the already-loaded continuity state

This preserves the intended layering:

`StfxMemory` -> `continuity_context` -> `scenario_continuity_state` -> optional downstream `vis_story` cycle JSON

---

## 12) Cross-session continuity (April 2026)

### 12.1 Session digest write-back

At session end (or scene exit), `ScenSynSessionDigestService` appends a structured
digest to the scenario's memory markdown under a `## Session Digests` section.
The digest captures: speakers, turn count, final phase, last speech excerpts per
character, unresolved threads, latent tensions, and Seeker journey bookends.

This mutates the same file that `ScenSynContinuityService._write_scenario_scaffold_markdown`
creates, extending it with accumulated session data.  The memory document cache is
invalidated after write to force re-ingestion on next startup.

### 12.2 Session history injection

On startup, `ScenSynContinuityService._inject_session_history` reads the raw
`## Session Digests` section from the memory markdown and injects it as
`state_patch.memory_context.session_history` in the continuity state dictionary.
This ensures session history reaches `StoryState.memory_context` and is surfaced
by `BaseMetapromptManager._get_story_continuity_prompt_block` as a
`CROSS-SESSION CONTINUITY` instruction.

### 12.3 Contract compatibility

This extension adds no new contract fields to `scensyn.scenario_continuity_state`.
Session history flows through the existing `state_patch.memory_context` dictionary.
The `session_history` key is an optional string; consumers that do not understand it
ignore it.  The continuity contract version remains `1`.

### 12.4 Dual write path

- **Formal end**: `handle_session_ended` → `write_session_digest` (async, with re-ingestion)
- **Interrupted exit**: `_exit_tree` → `write_digest_sync` (sync, markdown-only, deferred re-ingestion)
- `_digest_written` flag prevents double-writes within a session

### 12.5 Narrative integration note (v5.2)

In Stochastic Dreams, session digests are narratively framed as "what the Tapestry
remembers."  The dreaming layer concept means that between sessions (not just between
turns), the latent space continues to evolve.  Each session's digest becomes a memory
trace that the characters can reference — The Echo as keeper of dreaming and memory,
The Seeker as accumulating pilgrim experience, The Narrator as naming what was gained
and foreclosed across the arc of multiple closures.
