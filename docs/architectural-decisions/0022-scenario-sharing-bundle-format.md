# 0022 — Scenario sharing bundles, and library parity for Workshop Catalyst

- **Status:** Accepted
- **Date:** 2026-09-17
- **Area:** scensyn

## Context

Users wanted to share authored Scenarios with each other. Two things blocked it.

First, there was no interchange file. Scenarios crossed machines only over ENet:
`Network._on_peer_connected` ships the whole normalized Scenario dictionary to a
joining peer, which rehydrates it through `Global.apply_synced_workshop_scenario`.
That payload is already treated as self-contained and portable — it just had no
persisted form.

Second, and more seriously, Workshop Catalyst had nowhere to put an incoming
Scenario. `RuntimeConfig` exposed only `get_workshop_draft_path()`, a single
`scenario_draft_v1.json`. Importing could only have overwritten the facilitator's
working draft — the same failure class as the resume-overwrite bug fixed earlier
the same day. Open Play, by contrast, already had a full library
(`save_to_library` / `list_saved_scenarios` / `make_unique_id`).

Generated character portraits are the one asset that lives outside the Scenario
JSON, under `<workspace>/scensyn/sprites_generated/<collection>/<scenario>/…`, so
a JSON-only share renders differently on the recipient's machine.

## Options considered

1. **Normalized contract dictionary in a versioned JSON envelope** — reuses the
   payload Network already transports and the `normalize()` sanitization that
   already exists. Human-readable and diffable. Not an authoring format.
2. **The authored bracketed `.txt` format** — human-editable and diff-friendly,
   but `ScenarioLoader.get_scenario_path()` resolves only `res://` paths, so it
   would need a second loader plus a dict→text serializer that loses
   `stage_guidance` and `time_model` structure.
3. **Godot `.tres` / `.pck`** — engine-coupled; `.pck` can carry scenes, an
   executable surface that does not belong in user-shared content.
4. **Metapunkt-style `pack.json`** — that is a capability manifest with
   permissions and entrypoints. Scenarios are inert data; reusing it would imply
   executability and invite a permissions model they do not need.
5. **Hub artifact publishing** — exists, but requires the Hub running and is
   about provenance, not peer-to-peer sharing.

## Decision

Option 1, with four specifics.

**The envelope holds an array from the start** (`schema`, `exported_at`,
`exported_by_app_version`, `scenarios[]`, each entry carrying its own
`session_type`), so sharing a themed set later is not a breaking change. Schema
id is `synesyn.scensyn.scenario_bundle.v1`; the importer validates on that field,
never on the filename.

**Zip is implemented now, and chosen automatically.** A Scenario with no carried
files exports as a bare `.json`; one with generated sprites exports as a `.zip`
holding the same `scenario.json` at its root plus `assets/<index>/sprites/…`.
Users are told what was included rather than asked to pick a container.

**Workshop gets the library Open Play already had**, and the duplicated
persistence in both contracts is extracted into `ScenarioLibraryStore`. Each
contract keeps its own `normalize()` — that stays the trust boundary — while file
layout, id minting, and value coercion are shared.

**Import sets aside the fields that carry authority rather than content.** Two
Scenario fields direct the app instead of describing the subject.
`stage_guidance` is the specialists' per-stage operating contract, and authored
guidance beats `default_stage_guidance()`, so a bundle could otherwise replace the
facilitation method ADR 0012 asserts. `system_config` selects the specialist /
synthesizer / director / actor model and the output word limits; model ids are
validated against `AIModelManager`'s registered list, so a bundle cannot reach an
arbitrary endpoint, but it could redirect calls to another of the user's own
models. `ScenarioBundle.QUARANTINED_ON_IMPORT` names both. On import they are
moved into `imported_from.quarantined` — a record nothing reads — leaving the
Scenario to run on this machine's defaults. The test is against the raw bundle,
not the normalized value, because `normalize()` substitutes default guidance when
a Scenario carries none.

Implemented 2026-09-17 in `ScenarioBundle._quarantine_authority_fields`, covered
by `test_scenario_bundle_sharing.gd::_test_import_quarantines_authority_fields`,
which asserts a sender's instruction reaches neither the saved guidance nor the
model selection. Due for review: the field list is a judgement about which parts
of the contract carry authority, and it is correct only for the contract as it
stands today — see "Revisit when" below.

Packet text is deliberately *not* filtered. A Scenario about AI safety
legitimately contains adversarial phrasing, and prose-level injection detection
would mangle valid content without being reliable.

## Consequences

- Positive: import routes every Scenario back through the owning contract's
  `normalize()`, so sanitization already in place (Workshop stripping legacy
  roleplay text, Open Play filtering tags and re-iding characters) covers
  untrusted files for free.
- Positive: a colliding library id is re-minted rather than overwritten, and
  imports pass `sync_draft = false`, so nothing a user authored is replaced.
  `persistence_state = "imported"` plus `imported_from` keeps provenance visible.
- Positive: `ScenarioLibraryStore.carry_metadata` fixed a latent bug — `saved_at`
  was dropped by `normalize()` on load, so library newest-first sorting had been
  comparing empty strings.
- Negative: the bundle is not an authoring format. Contributing a Scenario back
  as a repo `.txt` template still means hand-writing it.
- Negative: sprite folders are keyed by Scenario *name*, matching runtime lookup,
  so two same-named Scenarios share portrait directories.
- Trade-off: asset paths inside a bundle are validated and refused rather than
  sanitized (`is_safe_relative_path`), so an odd-but-harmless archive layout is
  rejected instead of repaired.
- Positive: setting the authority fields aside rather than deleting them keeps the
  bundle's intent legible. A colleague whose authored guidance did not take effect
  can see why by opening the library file.
- Neutral: the quarantine costs nothing on any currently reachable path. Both
  export entry points build their payload from form fields — `create_custom` for
  Workshop, `_build_custom_scenario` for Open Play — and neither includes
  `stage_guidance` or `system_config`, so a bundle Synesyn produces never carries
  either field. Nothing exports a repo template or a library entry. The quarantine
  therefore only ever fires on a hand-edited bundle, which is exactly the case it
  is for. Note also that `stage_guidance` is developer-authored: at the time of
  this decision only `weight_of_decision_glp1_policy_triage.txt` defined a
  `STAGE_GUIDANCE` section, and the editor form does not expose the field, so
  facilitators cannot tune it through the app. That scenario is no longer
  distributed (see `.gitignore`), so no shipped template defines the section.
- Reservation (project owner, 2026-09-17): suspects the import safeguard is
  overcomplicated for what should be a simple thing. Recorded here for future
  review rather than resolved.
- Revisit when any of these happens, because each one invalidates part of the
  reasoning above rather than merely extending it:
  - **A field that directs the app is added to a contract's `normalize()`.** That
    fixed key set is the real gate: anything outside it is dropped, which is why
    `memory_continuity` and `turn_obligations` — present on `.txt`-loaded
    Scenarios — cannot arrive by bundle at all. `stage_guidance` and
    `system_config` are simply the two members of that key set which carry
    authority. `QUARANTINED_ON_IMPORT` is hand-maintained and nothing detects an
    omission, so a third such field would be applied from untrusted bundles by
    default. Story Catalyst has no equivalent today.
  - **An export path is added from a library entry or a repo template.** Bundles
    would then carry real guidance, the set-aside would become a genuine loss, and
    it would need the review-and-accept step below instead of a silent default.
  - **`stage_guidance` becomes editable in the app.** It is developer-authored
    today, which is why discarding it on import costs nothing; that stops being
    true the moment facilitators can tune it.
  - **The model allowlist stops bounding `system_config`.** The judgement that a
    bundle cannot exfiltrate prompts rests on `AIModelManager` validating ids
    against registered providers. A custom endpoint or base-URL setting would
    change the severity from "wrong model" to "prompts leave the machine".
- Follow-up (open): the review surface does not cover the authority fields. The
  Workshop editor form shows only packet text, so a facilitator cannot read an
  imported Scenario's guidance even to decide whether to accept it. The natural
  fix is a review-and-accept step that displays `imported_from.quarantined` and
  restores it on consent; worth building when sharing authored templates between
  trusted colleagues becomes a real workflow. Until then the Thinking Map's
  human-commit gate (ADR 0019) remains the backstop bounding what any injected
  instruction can make durable.
- Follow-up: BBCode escaping still matters wherever imported text is displayed.
