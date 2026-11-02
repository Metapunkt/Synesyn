# UWP x Ifa-Odu Coherence Design

Design record for the Stochastic Dreams scenario ontology, the Utopian Wheel of Progress (UWP) 16 bindings, and the Ifa-Odu relational matrix used by ScenSyn.

This document is written as a cold-start brief. A reader with no prior context should be able to take the code base in its pre-design state and execute every change captured here without additional conversation. Paths are relative to the workspace root (`StochasticDreams/`).

## 1. Purpose

This document records:

- the canonical orderings the Stochastic Dreams scenario uses for the UWP quadrants, the 16 UWP bindings, and the 16 Ifa Odu
- the structural audit of the pre-design runtime that motivated these orderings
- the visual audit of the UWP wheel image against the textual CSV source
- the decision to refactor the runtime ontology toward full 16-binding coherence (Option B)
- the staged plan for achieving that coherence without breaking current runtime behavior
- concrete, file-level actions and a reference index to the affected code

It is intentionally a living document. Each decision should be dated and attributable.

## 2. Artifacts In Scope

All paths are relative to the workspace root `StochasticDreams/`.

### 2.1 Definitional artifacts (textual sources of truth)

| Path | Role |
| --- | --- |
| `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/scenarios/Utopian_Wheel_16_Bindings.csv` | Canonical definition of the 16 UWP bindings grouped under 4 quadrants. Columns: `Quadrant, Binding, Domain, Tension, Thesis`. Treated as the authoritative source for binding identity and ordering. |
| `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/scenarios/Utopian_Wheel_x_Ifa_Odu_Relational_Matrix.csv.txt` | Cross-system interaction table. 16 rows (UWP bindings) x 16 columns (Ifa Odu). Each cell is an interpretive phrase for that binding under that Odu. |

### 2.2 Runtime artifacts (ontology, assembler, auto-input)

| Path | Role |
| --- | --- |
| `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/odu_ontology.json` | JSON narrative ontology consumed at runtime. Post task 11 (2026-04-16) it contains only the `odu` array of 16 entries with scenario-specific concept names and narrative cues; the legacy `sector_odu_pool` and `bead_sub_index` fields were removed. |
| `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/uwp_16x16_ontology.json` | Canonical Option B three-lattice ontology (renamed from `uwp_16x16_ontology.proposal.json` under task 11, 2026-04-16). Contains `uwp_bindings`, `ifa_odu`, `binding_x_odu`. |
| `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/turn_packet_assembler.gd` | Godot script that loads both ontologies and assembles the per-turn packet. Option-B-only after task 11: hosts `_select_binding`, `_select_odu_mode`, `_compose_preset`, `_load_uwp_16x16_ontology`. `BEAD_SUB_INDEX` is a module `const` (the canonical within-quadrant order is a design decision, no longer stored in JSON). |
| `synesyn/synesyn_client/pendulum_bridge/turn_processing/turn_packet_assembler.py` | Python bridge. Loads `odu_ontology.json` at runtime via `_load_ontology(path)` (task 12, 2026-04-16). After task 11 (2026-04-16), `process_turn` raises `NotImplementedError`: the legacy selection path it used was retired, and Option B parity has not been ported to Python. The helper methods (`_build_board_beads`, `_summarize_axes`, `_compute_resonance`, `_build_quality`) are preserved for a future port. |
| `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/scenarios/stochastic_dreams.txt` | Scenario config. Declares `[RELATIONAL_MATRIX]` and `[PLAYER_AUTO_INPUT]` blocks; currently does not wire `{oracle}` through to speaker templates. |
| `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/metaprompt_manager_cultural_narrative.gd` | Hosts `consult_oracle(concept_key, state_key, scenario) -> String`. Reads the relational CSV at lookup time. |
| `synesyn/synesyn_client/ScenSyn/scripts/core/player_auto_input.gd` | The only caller of `consult_oracle`. Hosts `_resolve_oracle(flat)` and the `{oracle}` template substitution hook. |

### 2.3 Visual and poster assets

| Path | Role |
| --- | --- |
| `UtopianWheelOfProgress.png` | Wheel rendering, cleaner text legibility. Primary reference for visual audit. |
| `UWP_with_icons_5.png` | Wheel rendering with decorative icons at quadrant centers. Same structural ordering as above. |
| `artwrorks/*.svg` | Poster assets referencing Odu by name. Already use canonical `EJI OGBE` spelling. |

## 3. Canonical Orderings

These orderings are the core structural commitments of the design. Every downstream artifact (ontology, matrix, wheel image, auto-input config) must conform.

### 3.1 UWP Quadrant Order (clockwise)

1. `Fount` — Tech, Culture & Philosophy (Making)
2. `Ethos` — Social Equity & Justice (Belonging)
3. `Cycle` — Environmental Sustainability (Life)
4. `Will` — Governance

Rationale:

- Reads clockwise on the UWP image (confirmed; see Section 6).
- Reads as a civic-cosmic cycle: creative origination → collective good → ecological renewal → governance that binds the order → back to Fount.

### 3.2 UWP 16-Binding Order (clockwise traversal)

Derived directly from `Utopian_Wheel_16_Bindings.csv` row order, with quadrants sequenced per Section 3.1:

| # | Quadrant | Binding | Domain |
| --- | --- | --- | --- |
| 1 | Fount | Heaven & Earth | Idealism vs. Realism |
| 2 | Fount | Fire & Forge | STEM Innovation |
| 3 | Fount | Memory & Myth | Culture Production |
| 4 | Fount | Self & Kin | Social Responsibility |
| 5 | Ethos | Well & Water | Resource Access |
| 6 | Ethos | Hearth & Haven | Poverty Elimination |
| 7 | Ethos | Law & Mercy | Fair Justice |
| 8 | Ethos | Thread & Loom | Equity Advocacy |
| 9 | Cycle | Leaf & Wire | Nature & Tech Harmony |
| 10 | Cycle | Seed & Spark | Sustainable Innovation |
| 11 | Cycle | Flow & Keep | Resource Efficiency |
| 12 | Cycle | Soot & Sap | Low Eco-Impact |
| 13 | Will | Many & One | Participatory Democracy |
| 14 | Will | Center & Edge | Decentralized Power |
| 15 | Will | Light & Glass | Transparent Rule |
| 16 | Will | Face & Mirror | Inclusive Leadership |

This ordering is authoritative. The 16-row axis of the relational matrix, the `uwp_bindings` lattice (Section 8.2), and the wheel image must all conform.

### 3.3 Ifa Odu Order (column axis, 16)

The Odu axis preserves the canonical Ifa order already in use in `Utopian_Wheel_x_Ifa_Odu_Relational_Matrix.csv.txt`:

`EJI OGBE, OYEKU MEJI, IWORI MEJI, ODI MEJI, IROSUN MEJI, OWONRIN MEJI, OBARA MEJI, OKANRAN MEJI, OGUNDA MEJI, OSA MEJI, IKA MEJI, OTURUPON MEJI, OTURA MEJI, IRETE MEJI, OSE MEJI, OFUN MEJI`

Naming decision (2026-04-16): the canonical name for the first Odu is `EJI OGBE`, not `OGBE MEJI`. Rationale:

- `EJI OGBE` is the authentic traditional Ifa name. The first Odu is unique in not following the `*_MEJI` pattern.
- The relational CSV and the SVG poster assets already use `EJI OGBE`.
- The pre-design `odu_ontology.json` and its Python mirror used `OGBE MEJI`, which has been corrected.
- No alias table is introduced. Lookups use direct (case-insensitive) string compare.

## 4. Semantic Principle

The relational matrix is NOT a self-symmetric Ifa-Odu table. It is a cross-system action table.

- Rows (`UWP bindings`) represent social-structural ideals and their internal tensions.
- Columns (`Ifa Odu`) represent modal operative tendencies or impulses that can act upon those structures.
- Cells describe what happens when that Odu-mode acts upon that binding: activation, distortion, reversal, revelation, binding, healing, etc.

"Elemental energies" is reframed as modal forces acting on civic-cosmic ideals. This framing justifies having UWP bindings keep their structural order and Odu keep their canonical order — they are two independent axes, not two views of the same system.

## 5. Pre-Design Runtime: Current State

This section captures the state the code base was in at the start of the design conversation, so a cold-start executor knows what to change from.

### 5.1 Ontology Structure (`odu_ontology.json`)

The pre-design ontology opens with:

```json
"sector_odu_pool": {
    "Fount": ["OGBE MEJI", "OKANRAN MEJI", "OGUNDA MEJI", "IWORI MEJI"],
    "Ethos": ["OWONRIN MEJI", "OBARA MEJI", "OSE MEJI", "ODI MEJI"],
    "Will":  ["OSA MEJI", "IKA MEJI", "OTURA MEJI", "IROSUN MEJI"],
    "Cycle": ["OYEKU MEJI", "OTURUPON MEJI", "IRETE MEJI", "OFUN MEJI"]
},
"bead_sub_index": { "Fount": 0, "Ethos": 1, "Will": 2, "Cycle": 3, "Seed": 0 },
"odu": [ /* 16 entries, each with odu_name, concept_name, predicament_family, province_or_site, narrative cues */ ]
```

Despite appearances, this is not a 16-binding system. It is a 4x4 quadrant modulation system:

1. `dominant_sector` from the pendulum picks one of four quadrant pools (4 options).
2. `secondary_bead` is mapped through `bead_sub_index` to an index (0-3) inside that pool.
3. The chosen Odu's full entry drives the turn packet.

The 16 ontology entries layer 16 bespoke scenario concepts (`Foundation & Origin`, `Signal & Threshold`, etc.) on top of the 16 Odu. These concept names form a third lattice that is not directly anchored in either UWP bindings or canonical Odu meanings.

### 5.2 Odu Selection Logic (`turn_packet_assembler.gd`)

The pre-design selection is a single call:

```gdscript
func _select_odu(dominant_sector: String, secondary_bead: String) -> Dictionary:
    var pool: Array = _sector_pool.get(dominant_sector, _sector_pool.get("Will", []))
    if pool.is_empty() and not _odu_list.is_empty():
        return _odu_list[0]
    var idx: int = int(_bead_sub_index.get(secondary_bead, 0)) % maxi(1, pool.size())
    var odu_name: String = str(pool[idx])
    return _odu_by_name.get(odu_name, _odu_list[0] if not _odu_list.is_empty() else {})
```

### 5.3 Relational CSV Wiring

The scenario declares the relational matrix in `stochastic_dreams.txt`:

```
[RELATIONAL_MATRIX]
file: Utopian_Wheel_x_Ifa_Odu_Relational_Matrix.csv.txt
type: lookup_table
row_key: Concept
col_key: Odu
```

The lookup is implemented in `metaprompt_manager_cultural_narrative.gd`:

```gdscript
func consult_oracle(concept_key: String, state_key: String, scenario: Dictionary) -> String:
    # Opens the CSV, finds the column for state_key (an Odu), scans rows for concept_key,
    # returns the matched cell or "" on miss.
```

The only caller is `player_auto_input.gd`:

```gdscript
func _resolve_oracle(flat: Dictionary) -> String:
    var concept_field: String = _config.get("concept_field", "")
    var state_field: String  = _config.get("state_field", "")
    if concept_field == "" or state_field == "": return ""
    var concept_value: String = flat.get(concept_field, "")
    var state_value:   String = flat.get(state_field, "")
    if concept_value == "" or state_value == "": return ""
    var manager = Global.get_metaprompt_manager()
    var scenario = Global.get_game_flow_manager().get_current_scenario() if Global.get_game_flow_manager() else {}
    if manager and manager.has_method("consult_oracle"):
        return manager.consult_oracle(concept_value, state_value, scenario)
    return ""

# Invoked inside the template-processing path:
# if template.find("{oracle}") != -1:
#     template = template.replace("{oracle}", _resolve_oracle(flat))
```

The pre-design `[PLAYER_AUTO_INPUT]` block does NOT supply `concept_field`, `state_field`, or `{oracle}` tokens:

```
[PLAYER_AUTO_INPUT]
enabled_by_default: true
character_mode: dynamic
submission_mode: direct_ai
trigger_sender: External Divination
template: {turn_packet.shared.province_or_site}: {turn_packet.shared.predicament_family}.
template_narrator: {turn_packet.shared.province_or_site}: {turn_packet.shared.predicament_family}. {turn_packet.narrator.next_question}
template_seeker: I set {beads.primary_concept} toward {beads.axis_position}. {turn_packet.seeker.visible_world_effect}
template_diviner: At {turn_packet.shared.province_or_site}, {turn_packet.diviner.diviner_operation_cue} Its shadow: {turn_packet.diviner.shadow_tendency}. Resonance {resonance}.
template_echo: At {turn_packet.shared.province_or_site}, the omen is this: {turn_packet.echo.echo_omen_cue} The risk is {turn_packet.echo.failure_state_risk}.
min_interval: 1.5
```

Consequence: the relational CSV is loaded but never consulted at runtime.

### 5.4 Observed Drifts

- `bead_sub_index` places `Will` before `Cycle` (`Fount:0, Ethos:1, Will:2, Cycle:3`), violating the canonical `Fount > Ethos > Cycle > Will` order.
- Quadrant pools are coherent at the quadrant level but not position-coherent against the four UWP bindings in each quadrant. `Will` is weakest: `IROSUN MEJI` reads as memory/archive/return, not governance.
- Scenario concept names in the ontology form a third lattice, unaligned with UWP bindings or canonical Odu meanings.
- `{oracle}` is wired in code but unused by configuration — the CSV sits dormant.
- The ontology uses `OGBE MEJI` while the relational CSV and SVG assets use the canonical `EJI OGBE`.

## 6. Visual Audit of the UWP Wheel (2026-04-16)

Performed against `UtopianWheelOfProgress.png` for text legibility; `UWP_with_icons_5.png` shares the same structural layout.

### 6.1 Quadrant Layout

Visual positioning:

```
        TOP
   Fount | Ethos
   ------+------
   Will  | Cycle
        BOTTOM
```

Reading clockwise from top-left: **Fount → Ethos → Cycle → Will**. Consistent with Section 3.1. ✓

### 6.2 Middle Ring Label → Binding Map

The wheel's middle ring uses domain labels, not binding names. The mapping (from `Utopian_Wheel_16_Bindings.csv`):

| Wheel label (Domain) | Binding |
| --- | --- |
| Idealism vs. Realism | Heaven & Earth |
| STEM Innovation | Fire & Forge |
| Culture Production | Memory & Myth |
| Social Responsibility | Self & Kin |
| Resource Access | Well & Water |
| Poverty Elimination | Hearth & Haven |
| Fair Justice | Law & Mercy |
| Equity Advocacy | Thread & Loom |
| Nature & Tech Harmony | Leaf & Wire |
| Sustainable Innovation | Seed & Spark |
| Resource Efficiency | Flow & Keep |
| Low Eco-Impact | Soot & Sap |
| Participatory Democracy | Many & One |
| Decentralized Power | Center & Edge |
| Transparent Rule | Light & Glass |
| Inclusive Leadership | Face & Mirror |

### 6.3 Intra-Quadrant Order Comparison

Reading the wheel CLOCKWISE within each quadrant (from leading boundary to trailing boundary), compared to the CSV Section 3.2 canonical order:

**Fount** (Will-boundary → Ethos-boundary):

| Position | Wheel order | CSV canonical |
| --- | --- | --- |
| 1st | Fire & Forge | Heaven & Earth |
| 2nd | Memory & Myth | Fire & Forge |
| 3rd | Heaven & Earth | Memory & Myth |
| 4th | Self & Kin | Self & Kin |

**Ethos** (Fount-boundary → Cycle-boundary):

| Position | Wheel order | CSV canonical |
| --- | --- | --- |
| 1st | Well & Water | Well & Water |
| 2nd | Thread & Loom | Hearth & Haven |
| 3rd | Law & Mercy | Law & Mercy |
| 4th | Hearth & Haven | Thread & Loom |

**Cycle** (Ethos-boundary → Will-boundary):

| Position | Wheel order | CSV canonical |
| --- | --- | --- |
| 1st | Seed & Spark | Leaf & Wire |
| 2nd | Flow & Keep | Seed & Spark |
| 3rd | Soot & Sap | Flow & Keep |
| 4th | Leaf & Wire | Soot & Sap |

**Will** (Cycle-boundary → Fount-boundary):

| Position | Wheel order | CSV canonical |
| --- | --- | --- |
| 1st | Many & One | Many & One |
| 2nd | Face & Mirror | Center & Edge |
| 3rd | Light & Glass | Light & Glass |
| 4th | Center & Edge | Face & Mirror |

### 6.4 Findings

1. Quadrant order (Fount → Ethos → Cycle → Will) is consistent between wheel and CSV.
2. Intra-quadrant order disagrees in all four quadrants. The wheel orders by criteria that appear to be visual/chromatic or early-draft; the CSV orders by semantic progression within each domain.

### 6.5 Resolution

Decision: CSV order (Section 3.2) is canonical. Wheel image is to be regenerated to match.

Rationale:

- The CSV is the authorial definitional source for the bindings (name, domain, tension, thesis). Its row order carries authorial intent about progression.
- The CSV order reads as a cleaner semantic progression. Fount exemplifies: cosmological foundation (Heaven & Earth) → tool-making (Fire & Forge) → culture (Memory & Myth) → social responsibility (Self & Kin).
- Re-rendering a visual asset is a smaller cost than keeping the runtime misaligned from the textual source of truth.

### 6.6 Inter-Quadrant Transition Quality (Canonical Order)

With the canonical CSV order, the quadrant-boundary transitions read:

- Fount → Ethos: `Self & Kin` (social responsibility) → `Well & Water` (resource access). Strong: individual/familial responsibility opens into collective material provision.
- Ethos → Cycle: `Thread & Loom` (equity advocacy) → `Leaf & Wire` (nature-tech harmony). Acceptable: social equity opens into planetary coherence.
- Cycle → Will: `Soot & Sap` (low eco-impact) → `Many & One` (participatory democracy). Acceptable: ecological restraint opens into collective decision-making.
- Will → Fount (cycle closure): `Face & Mirror` (inclusive leadership) → `Heaven & Earth` (idealism vs. realism). Strong: representation closes into vision-grounding.

Two strong, two acceptable. Ethos→Cycle and Cycle→Will are candidates for future refinement but are not blocking.

## 7. Architectural Fork

Two viable paths were considered:

- **Option A** — Keep the quadrant-modulation architecture. Tighten pool membership. Fix the `bead_sub_index` order. Treat the CSV as an optional overlay.
- **Option B** — Refactor the ontology to be truly coherent with the 16 UWP bindings and the 16 Odu. CSV and ontology share a single lattice.

Decision (2026-04-16): pursue **Option B**. It yields a single coherent structural model across the relational matrix, the ontology, and the runtime selection logic.

## 8. Option B: Target Architecture

### 8.1 Core Idea

Replace the `4 quadrants x 4 secondary bead modulations` selection model with two orthogonal 16-lattices:

- 16 canonical UWP bindings as the primary scenario lattice.
- 16 Ifa Odu as orthogonal modal forces.
- Per turn: select a binding (UWP side) + select an Odu modality (Ifa side) → consult their cell.

The ontology describes bindings, Odu, and optional cross-cell enrichments. The relational CSV remains the canonical reference for 16x16 interaction content.

### 8.2 Proposed Data Model

Three separate lattices, connected by explicit references:

1. `uwp_bindings` — 16 entries, one per binding. Keys: `id` (1-16, per Section 3.2), `binding_name`, `quadrant`, `domain`, `tension`, `thesis`, `tapestry_region_primary`, `province_or_site`, `world_domain_focus`.
2. `ifa_odu` — 16 entries, one per Odu. Keys: `odu_name` (canonical per Section 3.3), `odu_bits`, `canonical_index` (1-16), `modal_essence` (short phrase such as "pure beginnings" or "fertile dissolution").
3. `binding_x_odu` — optional cell overrides. Most cells derive from the CSV; the JSON stores scenario-specific enrichments only for intersections the scenario chooses to dramatize.

Turn packet construction:

- Pendulum/beads select a `binding_id` (1-16).
- Pendulum modal character (chaos/stability/resonance) selects an `odu_id` (1-16).
- Runtime merges `uwp_bindings[binding_id]` + `ifa_odu[odu_id]` + (optional) `binding_x_odu[binding_id][odu_id]` + CSV lookup for that cell.

### 8.3 Runtime Selection Change

Replace `_select_odu(dominant_sector, secondary_bead)` in `turn_packet_assembler.gd` with:

```gdscript
var binding_id: int = _select_binding(beads, traversal)
var odu_id: int     = _select_odu_mode(pendulum_metrics, resonance)
var preset: Dictionary = _compose_preset(binding_id, odu_id)
```

- `_select_binding` uses pendulum dominant sector + bead configuration to pick one of 16 bindings. The quadrant narrows the choice to 4; a secondary signal (e.g. a finer bead reading or axis position) picks one of the 4 within the quadrant, using the canonical intra-quadrant order from Section 3.2.
- `_select_odu_mode` uses pendulum modal character (chaos, stability, resonance) to pick one of 16 Odu. The exact metric choice is an open question (Section 10).
- `_compose_preset` assembles the merged view.

### 8.4 Relational CSV Integration

- Naming already unified on `EJI OGBE` (step 1 executed 2026-04-16). Direct string compare works in `consult_oracle()`.
- Wire auto-input `{oracle}` end-to-end by extending `[PLAYER_AUTO_INPUT]` in `stochastic_dreams.txt`:
  - Add `concept_field: <flat-key resolving to binding_name>`
  - Add `state_field: <flat-key resolving to odu_name>`
  - Reintroduce `{oracle}` into the speaker templates that should consult it.
- Over time, refactor CSV cells from templated paraphrases toward genuine interaction statements.

### 8.5 Backward Compatibility / Migration

> **Status (2026-04-16, post task 11): all four steps below are complete.** Kept as a record of how the migration was staged; a cold-start replicator following §12 in order will reproduce these stages automatically (tasks 5 and 8 land step 1 and step 2, tasks 9 and 10 land step 3, task 11 lands step 4). A replicator who wants only the end state can read §14 instead.

Staged:

1. Introduce the three lattices alongside the current ontology structure. Keep `sector_odu_pool` / `bead_sub_index` usable as a fallback. *(Landed tasks 5 + 8, 2026-04-16.)*
2. Add an `ontology_mode` feature flag: `legacy_quadrant` or `uwp_16x16`. *(Landed task 8, 2026-04-16.)*
3. Run both paths in parallel during validation; diff the resulting turn packets. *(Landed task 10, 2026-04-16; report at `docs_for_update_on_bindings_odu_matrix_refinement/validation_report_selection_paths.md`.)*
4. Once `uwp_16x16` is stable, deprecate the legacy path and remove `sector_odu_pool` / `bead_sub_index`. *(Landed task 11, 2026-04-16. The `ontology_mode` flag itself was also retired in the same task, since the choice collapsed to a single mode.)*

### 8.6 Provisional v1 Selection Rules (task 9)

Selection under `ontology_mode=uwp_16x16`. Intentionally simple and deterministic. Each rule is marked v1 and open to refinement under Section 10 open questions.

#### 8.6.1 `_select_binding(beads, traversal)` → `binding_id ∈ [1, 16]`

1. Quadrant = `traversal.dominant_sector`. If it is `Seed` or missing, default to `Will`.
2. Within-quadrant index = `_bead_sub_index[secondary_bead]`, clamped to 0..3. (`secondary_bead` is already the second-most-eccentric non-Seed bead, computed identically to the legacy path.)
3. Quadrant offset table (from Section 3.2):

   ```
   Fount: 0   Ethos: 4   Cycle: 8   Will: 12
   ```

4. `binding_id = quadrant_offset[quadrant] + within_quadrant_index + 1`.

Properties:

- Quadrant-coherent: all four bindings reachable from a dominant sector sit within that sector's CSV row range.
- Uses the same two pendulum signals the legacy path already exposed (`dominant_sector`, `secondary_bead`), so pendulum traces from the legacy era replay meaningfully under the new path.
- Decoupled from Odu selection — the Odu axis is now driven by different pendulum metrics (§8.6.2), giving Option B its orthogonality.

#### 8.6.2 `_select_odu_mode(pendulum_metrics)` → `odu_id ∈ [1, 16]`

Two continuous pendulum qualities are each quantized into 4 bins, forming a 4×4 grid over the 16 canonical Odu positions.

1. `stability_bin = clamp(floor(pendulum_metrics.stability * 4), 0, 3)`.
2. `inverse_entropy_bin = clamp(floor((1.0 - pendulum_metrics.entropy) * 4), 0, 3)`.
3. `odu_id = stability_bin * 4 + inverse_entropy_bin + 1` (1..16, addressing `ifa_odu[canonical_index=odu_id]`).

Rationale:

- `stability` and `entropy` are the two most decision-relevant pendulum metrics already computed by `SDUWPTraversalAnalyzer`.
- Using `1 - entropy` for the secondary bin makes both axes monotonic ("higher signal → later position"), keeping interpretation consistent.
- The mapping is uniform (no bias toward particular Odu), deterministic, and cheap.

Caveats (v1, open for future refinement under task 6):

- Does not use `crossings` or `resonance`.
- Does not use `Seed` bead perturbation, despite Seed explicitly modelling chaos. Section 10 open question: "Should `Seed` influence Odu-mode selection?" — candidate for v2.
- A 4×4 rectangular quantization may under-represent extreme-edge modes (`EJI OGBE`, `OFUN MEJI`) when pendulum signals are noisy. Acceptable for v1.

#### 8.6.3 `_compose_preset(binding_id, odu_id)` → `Dictionary`

Merge order (later sources overwrite earlier when keys collide):

1. `legacy_odu` — `_odu_by_name.get(ifa_odu[odu_id].odu_name)`. Provides all scenario narrative cue fields (predicament_family, diviner/echo/seeker/narrator cues, complementary_odu, etc.) that the three-lattice proposal does not yet own. This is the fallback carrier.
2. `uwp_bindings[binding_id]` fields — `concept_id` ← binding.id; `concept_name` ← binding.binding_name; `utopian_domain` ← binding.domain. When binding's `tapestry_region_primary`/`province_or_site`/`world_domain_focus` are non-empty they take precedence over the legacy values (currently empty pending Open Question 4, so legacy carries these).
3. `ifa_odu[odu_id]` fields — `odu_name`, `odu_bits`.
4. `binding_x_odu["<binding_id>.<odu_id>"]` — sparse per-cell overrides. Any key present here replaces the value set by previous steps. Empty in v1.

The returned preset must expose every key the legacy `assemble()` block reads off `preset[...]`, plus two new keys:

- `binding_id: int`
- `binding_name: String`

> **Failure-mode update (2026-04-16, post task 11):** if `_compose_preset` returns `{}` (or the three-lattice JSON failed to load so `_uwp_16x16_loaded` is false), `assemble()` now pushes a warning and returns `{}` — the whole turn is skipped rather than falling back to the legacy path. The legacy `_select_odu` helper and its `_sector_pool` / `_bead_sub_index` state no longer exist on the assembler. The original draft sentence "...the caller falls back to `_select_odu` (legacy path) with a single warning" described the task 9 → task 10 intermediate state; task 11 removed the fallback.

## 9. Side Concern: Python Ontology Mirror — Resolved (2026-04-16)

Historically, `synesyn/synesyn_client/pendulum_bridge/turn_processing/turn_packet_assembler.py` contained an inline Python copy of large portions of `odu_ontology.json` (all 16 Odu entries, `sector_odu_pool`, `bead_sub_index`). That was a single-source-of-truth violation: every ontology change had to be applied in two languages, in two folders, with no automatic consistency check.

Resolved as task 12 on 2026-04-16:

- The embedded `_ODU_ONTOLOGY`, `_ODU_BY_NAME`, `_SECTOR_ODU_POOL`, `_BEAD_SUB_INDEX` module-level constants and the module-level `_select_odu()` function were all removed from `turn_packet_assembler.py`.
- A new module-level `_load_ontology(path)` function reads `odu_ontology.json` at runtime and returns the lookup tables the assembler needs.
- `_DEFAULT_ONTOLOGY_PATH` is computed from `__file__`, pointing at the Godot-side canonical JSON. It can be overridden via `config["ontology_path"]` when constructing `TurnPacketAssembler`.
- `TurnPacketAssembler.__init__` now loads the ontology and stores `_odu_list`, `_odu_by_name`, `_sector_pool`, `_bead_sub_index` as per-instance state. Missing or malformed JSON raises at construction time (fail fast, not silent).
- `_select_odu(dominant_sector, secondary_bead)` became an instance method. Selection results verified against the validation report on 2026-04-16 (e.g. `(Fount, Fount) → EJI OGBE / Foundation & Origin`).
- File shrank from ~837 to ~412 lines.

The Python bridge is now a single-source-of-truth consumer of `odu_ontology.json`, mirroring the Godot assembler's loader pattern. Any future ontology edit needs to touch only the JSON; both runtimes pick it up at their next init.

Update (task 11, 2026-04-16): the legacy quadrant path has since been removed from the Godot assembler and from `odu_ontology.json`. The Python bridge had no Option B parity, so under task 11 its `process_turn` was converted to raise `NotImplementedError` rather than silently emit stale packets. If full Python Option B is ever needed (current deployment flow does not require it — Godot is the primary runtime), mirror `_load_uwp_16x16_ontology`, `_select_binding`, `_select_odu_mode`, and `_compose_preset` from `turn_packet_assembler.gd`. The board/axes/resonance helper methods are still in place and will be reusable by that port.

### 9.1 Extended resolution — udp test harness (2026-04-16, task 12b)

Investigating whether the Python bridge was powering the udp test harness surfaced two more ontology copies outside both runtimes:

- `input_test_sim/stochastic_udp_test.py` — standalone simulator that cycles through all 16 Odu by index and ships pre-built turn packets to Godot's `ExternalInputListener` on UDP 5001 (or to Synesyn Hub on 5000). Does NOT import from `pendulum_bridge/`; it's independent of the Python bridge.
- `pendulum_hardware_dev/updated_files_to_use/stochastic_udp_test.py` — sibling copy that additionally replicates the hardware bridge's `_select_odu(dominant_sector, secondary_bead)` logic (sector pool × bead sub-index).

Both copies embedded their own 430-line `_ODU_ONTOLOGY` block, both pre-dating the `OGBE MEJI → EJI OGBE` rename. The hardware-like copy also carried a stale `_BEAD_SUB_INDEX = {Fount:0, Ethos:1, Will:2, Cycle:3, Seed:0}` that contradicted the canonical `Fount > Ethos > Cycle > Will` order in Section 3.

Resolved as task 12b on 2026-04-16:

- Both harness copies now load `odu_ontology.json` at runtime via a `_load_odu_ontology()` helper (same pattern as `turn_packet_assembler.py` from task 12). `_REPO_ROOT` is computed from `__file__` per copy so each knows its own depth (input_test_sim is one level below the repo root; pendulum_hardware_dev/updated_files_to_use is two levels below).
- The rename propagates automatically; `EJI OGBE` now appears in every harness-generated packet.
- In the hardware-like copy, `_SECTOR_ODU_POOL["Fount"][0]` was updated `"OGBE MEJI" → "EJI OGBE"` (otherwise its `_ODU_BY_NAME.get()` lookup would silently fall through to index 0), and `_BEAD_SUB_INDEX` was reordered to canonical `{Fount:0, Ethos:1, Cycle:2, Will:3, Seed:0}`.
- `_SECTOR_ODU_POOL` and `_BEAD_SUB_INDEX` remain **inline** in the hardware-like copy by design: these fields are scheduled for removal from `odu_ontology.json` in task 11, and sourcing them from JSON would break the harness the moment task 11 lands. Keeping them inline decouples the harness's selection-simulation from the live runtime's legacy scaffolding. They are now small (≤10 lines) and easy to maintain.
- Both copies kept at user request (2026-04-16). Intended distinction: `input_test_sim/` is the narrative sweep (one of every Odu per run); `pendulum_hardware_dev/updated_files_to_use/` is the hardware-selection mimic. User may deduplicate at any later point.
- Verified by a transient smoke test that imported both modules, asserted 16 Odu loaded with `EJI OGBE` present and `OGBE MEJI` absent, built a sample packet from each, and spot-checked four `_select_odu` cells: `(Fount,Fount) → EJI OGBE`, `(Ethos,Cycle) → OSE MEJI`, `(Cycle,Will) → OFUN MEJI`, `(Will,Will) → IROSUN MEJI` — all match canonical ordering.
- File sizes: `input_test_sim` 850 → 416 lines; `pendulum_hardware_dev/updated_files_to_use` 878 → 444 lines.

Known future risk: if `odu_ontology.json` is relocated, both harness copies' `_REPO_ROOT`-relative paths need updating alongside `_DEFAULT_ONTOLOGY_PATH` in `turn_packet_assembler.py`. Grep for `odu_ontology.json` to catch all four consumers (plus the Godot `turn_packet_assembler.gd` which uses a `res://` path).

## 10. Open Questions

- Which pendulum metrics drive Odu-mode selection in Option B — resonance alone, stability, entropy, or a compound signal?
- Should `Seed` (chaos bead) influence Odu-mode selection rather than binding selection? Currently it modulates perturbation.
- Intra-quadrant binding selection in Option B: which secondary signal (bead axis position, finer bead reading, pendulum sub-sector) picks among the four bindings within a quadrant?
- How should the scenario-specific predicament families (`The Entropy Bargain`, `Threshold Overreach`, etc.) be re-anchored? As overlays on `binding_x_odu` cells, or as a separate narrative layer?
- Ethos→Cycle and Cycle→Will inter-quadrant transitions (Section 6.6) are only acceptable, not strong. Worth revisiting via intra-quadrant reordering in a future refinement pass.
- ~~**Open Question 6** (resolved 2026-04-16)~~: decision taken to pursue route 7a-option-b. No legacy concept→binding mapping. `matrix_resolution.binding_name` will be produced by the Option B selection path (task 9) and oracle activates once the `ontology_mode` flag is flipped to `uwp_16x16`. Rationale: route 7a-legacy would weld each Odu to a single binding, contradicting Option B's orthogonality principle and the CSV's 16×16 interaction design; the resulting shim would be throwaway work. Oracle stays dormant under legacy (safe no-op) until tasks 6, 8, 9 land.

## 11. Decision Log

| Date | Decision | Notes |
| --- | --- | --- |
| 2026-04-16 | Canonical quadrant order = `Fount > Ethos > Cycle > Will` | Clockwise on UWP image; civic-cosmic logic. |
| 2026-04-16 | Canonical 16-binding order derives from `Utopian_Wheel_16_Bindings.csv` row order, sequenced by the Section 3.1 quadrant order | Section 3.2 is authoritative. |
| 2026-04-16 | Relational matrix is a cross-system action table, not a self-symmetric Ifa table | Rows keep UWP order; columns keep canonical Ifa order. |
| 2026-04-16 | Architectural choice: Option B (refactor toward 16x16 coherence) | Single coherent structural model across CSV, ontology, runtime. |
| 2026-04-16 | Canonical Odu name for the first Odu is `EJI OGBE`, not `OGBE MEJI`. Rename ontology + Python mirror; no alias table. | Matches traditional Ifa naming. Already used by CSV and SVG assets. Eliminates normalization layer. Executed 2026-04-16. |
| 2026-04-16 | Python ontology mirror in `pendulum_bridge/turn_processing/turn_packet_assembler.py` flagged as single-source-of-truth violation | Tracked in Section 9; follow-up. |
| 2026-04-16 | Visual audit: wheel and CSV agree on quadrant order but disagree on intra-quadrant order in all four quadrants | See Section 6.3. |
| 2026-04-16 | CSV order (Section 3.2) is canonical; wheel image to be regenerated to match | Wheel is a rendering; CSV is the authorial source. |
| 2026-04-16 | `bead_sub_index` normalized to `{ Fount:0, Ethos:1, Cycle:2, Will:3, Seed:0 }` in JSON and Python mirror | Restores canonical Fount>Ethos>Cycle>Will order. Changes which pool element the `Will`/`Cycle` secondary beads select during the legacy quadrant path. Executed 2026-04-16. |
| 2026-04-16 | Option B three-lattice schema drafted as `uwp_16x16_ontology.proposal.json` sibling of `odu_ontology.json` | Contains `uwp_bindings` (CSV-derived, Section 3.2 IDs), `ifa_odu` (canonical Section 3.3 order with modal_essence and canonical_meaning), `binding_x_odu` (empty). Proposal status; not yet wired into runtime. Per-binding region/site/domain fields empty pending Open Question 4 resolution. |
| 2026-04-16 | `{oracle}` config scaffolding added to `stochastic_dreams.txt`: `concept_field: matrix_resolution.binding_name`, `state_field: matrix_resolution.odu_name`, appended `{oracle}` to `template_echo` | `state_field` works today; `concept_field` references a key that `turn_packet_assembler.gd` does not yet emit. Oracle resolves empty under legacy (safe no-op). Full activation blocked on Open Question 6. |
| 2026-04-16 | Route 7a-option-b selected for oracle activation | No legacy concept→binding mapping. `matrix_resolution.binding_name` will be produced by Option B's `_select_binding` (task 9), not by a legacy shim. Avoids welding Odu to binding (which would contradict Option B orthogonality) and avoids throwaway code. Oracle stays dormant under legacy until the flag flips. |
| 2026-04-16 | `ontology_mode` feature flag plumbed through `bridge_config.json` → `StochasticDreamsPendulumBridge` → `SDTurnPacketAssembler` (and Python mirror) | Default `legacy_quadrant`. `uwp_16x16` currently falls back to legacy with a warning until task 9. `matrix_resolution` now emits `binding_name` (empty under legacy) and `ontology_mode` so the flat-key namespace is stable across modes. |
| 2026-04-16 | Option B v1 selection rules specified and implemented (Section 8.6 + `turn_packet_assembler.gd`) | `_select_binding` = quadrant offset + `_bead_sub_index[secondary_bead]`; `_select_odu_mode` = 4×4 quantization of (stability, 1−entropy); `_compose_preset` = legacy_odu → binding → ifa_odu → cell-override merge. Clean legacy fallback if the three-lattice JSON fails to load. Python mirror stays warn-and-fallback pending task 12. |
| 2026-04-16 | Oracle activated under `ontology_mode=uwp_16x16` | `matrix_resolution.binding_name` now populated from `uwp_bindings[id].binding_name`. Flipping the bridge_config flag to `uwp_16x16` makes `{oracle}` resolve live. Under `legacy_quadrant`, binding_name stays empty (safe no-op). |
| 2026-04-16 | Parallel validation executed via exhaustive enumeration (`validate_selection_paths.py`) instead of recorded pendulum traces | Input space is finite and deterministic (5×5×4×4 = 400 combinations); exhaustive enumeration is strictly stronger than trace replay. Status PASS on all three structural checks; intentional divergences (concept-axis shift, Odu-mode decoupling) catalogued. Tool is reusable on future ontology or rule changes. |
| 2026-04-16 | Python ontology mirror resolved — `turn_packet_assembler.py` now loads `odu_ontology.json` at runtime (task 12) | Embedded ontology block removed; `_DEFAULT_ONTOLOGY_PATH` resolves from `__file__` with `config["ontology_path"]` override; selection results verified against the validation report. File halved in size. Option B parity in Python intentionally deferred — Python bridge continues to warn-and-fallback when `ontology_mode=uwp_16x16`. |
| 2026-04-16 | udp test harness copies unified with the canonical JSON (task 12b); both copies kept | User confirmed both `input_test_sim/stochastic_udp_test.py` and `pendulum_hardware_dev/updated_files_to_use/stochastic_udp_test.py` serve distinct purposes (narrative-sweep vs hardware-selection mimic). Both now load `odu_ontology.json` at runtime; the `OGBE MEJI → EJI OGBE` rename propagates automatically. Hardware-like copy's `_BEAD_SUB_INDEX` and `_SECTOR_ODU_POOL["Fount"][0]` also brought in line with canonical ordering. `_SECTOR_ODU_POOL` and `_BEAD_SUB_INDEX` kept inline in the hardware-like copy (small, and task 11 will remove them from the JSON anyway). |
| 2026-04-16 | Task 11 executed: legacy quadrant path retired, Option B is the only selection path | `uwp_16x16_ontology.proposal.json` renamed to `uwp_16x16_ontology.json` (canonical, not proposal). `sector_odu_pool` and `bead_sub_index` removed from `odu_ontology.json`; the canonical within-quadrant order becomes a `const BEAD_SUB_INDEX` on the Godot assembler. `ontology_mode` feature flag removed from `bridge_config.json`, from the Godot assembler (var / match branch / fallback warnings / `_select_odu` / `_sector_pool` / `_bead_sub_index` state / `matrix_resolution.ontology_mode`), and from the Python bridge. Python `process_turn` now raises `NotImplementedError` (no Option B parity) rather than silently emitting stale packets; helper methods preserved for a future port. `validate_selection_paths.py` reworked to an Option-B-only structural validator. Re-ran the validator: **PASS**. UDP test harnesses unaffected (they already owned their own selection scaffolding via task 12b). |

## 12. Actionable Task List

The master ordered to-do list. Items already executed are marked. A cold-start executor can pick up at the first unchecked item.

1. [x] **2026-04-16** — Rename `"OGBE MEJI"` → `"EJI OGBE"` (3 occurrences each) in:
   - `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/odu_ontology.json`
   - `synesyn/synesyn_client/pendulum_bridge/turn_processing/turn_packet_assembler.py`
   Verification: grep of workspace for `OGBE MEJI` returns only design doc hits.
2. [x] **2026-04-16** — Visual audit of `UtopianWheelOfProgress.png` and `UWP_with_icons_5.png` against Section 3.2. Captured in Section 6.
3. [ ] **Regenerate wheel image** so intra-quadrant order matches Section 3.2. Both `UtopianWheelOfProgress.png` and `UWP_with_icons_5.png` should be updated. Inputs: `Utopian_Wheel_16_Bindings.csv`. Deferred by user request 2026-04-16; other work proceeds in parallel.
4. [x] **2026-04-16 — Fix `bead_sub_index` order** in `odu_ontology.json` and its Python mirror so `Cycle` precedes `Will`:
   - Current: `{ "Fount": 0, "Ethos": 1, "Will": 2, "Cycle": 3, "Seed": 0 }` (pre-change)
   - Target:  `{ "Fount": 0, "Ethos": 1, "Cycle": 2, "Will": 3, "Seed": 0 }` (applied)
   Note: this is only meaningful under the legacy quadrant path; pre-empts drift into the 16-lattice design.
5. [x] **2026-04-16 — Drafted the Option B three-lattice schema** as `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/uwp_16x16_ontology.proposal.json`. Sibling of `odu_ontology.json`. Contains `uwp_bindings` (16 entries, CSV-derived, Section 3.2 IDs), `ifa_odu` (16 entries, Section 3.3 canonical order with `odu_bits`, `modal_essence`, `canonical_meaning`), and empty `binding_x_odu`. The per-binding `tapestry_region_primary`, `province_or_site`, `world_domain_focus` fields are empty strings pending Open Question 4 (Section 10).
6. [~] **2026-04-16 — Provisional v1 pendulum → `odu_mode` rule specified** in Section 8.6.2: 4×4 quantization of (`stability`, `1 - entropy`). Still open: whether to incorporate `crossings`, `resonance`, or `Seed` perturbation in a v2 refinement (tracked in Section 10 open questions).
7. [~] **2026-04-16 — Wired `{oracle}` config scaffolding** in `stochastic_dreams.txt`. Executed in two parts:
   - [x] Added `concept_field: matrix_resolution.binding_name` and `state_field: matrix_resolution.odu_name` to `[PLAYER_AUTO_INPUT]`.
   - [x] Appended `{oracle}` to `template_echo` after the risk statement. Chosen because the Echo already speaks omens; oracle text layers naturally on that role.
   - [x] **2026-04-16 — Blocker 7a resolved** via route 7a-option-b (task 9). Under `ontology_mode=uwp_16x16`, `_select_binding` now populates `matrix_resolution.binding_name` from `uwp_bindings[binding_id].binding_name`. Oracle resolves live under `uwp_16x16`. Under `legacy_quadrant` the field stays empty and `{oracle}` substitutes to a safe no-op, as before.
   - [x] **Blocker 7b** — `matrix_resolution.odu_name` IS emitted in both modes (verified). Oracle's `state_field` side is fully operational.

   Oracle activation status: **live under `uwp_16x16`, dormant under `legacy_quadrant`.** Flipping `"ontology_mode": "uwp_16x16"` in `bridge_config.json` is the last runtime switch needed.
8. [x] **2026-04-16 — Added the `ontology_mode` feature flag.** Location: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/bridge_config.json` (passed through `StochasticDreamsPendulumBridge._load_config()` to `SDTurnPacketAssembler._init(config)`). Accepted values: `legacy_quadrant` (default) and `uwp_16x16`. Mirrored in the Python assembler's `TurnPacketAssembler.__init__`. Changes:
   - GDScript: new `_ontology_mode` var, initialized in `_init`, branched in `assemble()` via `match _ontology_mode`. `uwp_16x16` path currently logs a warning and falls back to `_select_odu` (legacy); task 9 fills it in.
   - Python: analogous `self._ontology_mode` field and branch in `process_turn()`.
   - Both assemblers now emit `matrix_resolution.binding_name` (empty string under legacy) and `matrix_resolution.ontology_mode` (the active mode) so the flat-key namespace is stable across modes.
   Unblocks `{oracle}` under the `uwp_16x16` path: once task 9 fills `binding_name`, the oracle activates without further config changes.
9. [x] **2026-04-16 — Implemented Option B selection functions** in `turn_packet_assembler.gd`, behind the `ontology_mode=uwp_16x16` branch:
   - `_select_binding(_beads, traversal, secondary_bead) -> int` — quadrant (from `traversal.dominant_sector`, defaulting to `Will` if `Seed`/missing) + intra-quadrant index (from `_bead_sub_index[secondary_bead]`, clamped 0..3) via the `QUADRANT_OFFSETS` constant (`Fount:0, Ethos:4, Cycle:8, Will:12`). Returns `binding_id ∈ [1, 16]`.
   - `_select_odu_mode(pendulum_metrics) -> int` — 4×4 quantization `stability_bin * 4 + inverse_entropy_bin + 1`. Returns `odu_id ∈ [1, 16]`.
   - `_compose_preset(binding_id, odu_id) -> Dictionary` — merges `legacy_odu` (narrative cues) → `uwp_bindings[binding_id]` (concept_id/name/domain, plus region/site/world when non-empty) → `ifa_odu[odu_id]` (odu_name/bits) → `binding_x_odu["<bid>.<oid>"]` cell override. Returns `{}` (triggering legacy fallback) if any lattice lookup fails.
   - Lattice loader `_load_uwp_16x16_ontology()` added; called from `_load_ontology()` only when the flag is `uwp_16x16`. Validates 16/16 sizes before marking `_uwp_16x16_loaded`.
   - `assemble()` under `uwp_16x16`: selects binding+odu, composes preset, falls back to `_select_odu` (legacy) with a single one-shot warning if composition fails. `matrix_resolution` now emits `binding_id` and non-empty `binding_name` in this mode.
   - Legacy path (`_select_odu`) preserved unchanged. Selection rules specified in Section 8.6.
   - Python bridge (`pendulum_bridge/turn_processing/turn_packet_assembler.py`) still warn-and-falls-back on `uwp_16x16`; full Python Option-B selection parity remains deferred (task 12 only unified the ontology loader, not the selection logic).
10. [x] **2026-04-16 — Validated in parallel**. Exhaustive enumeration rather than recorded traces, because both selection paths are deterministic and their combined input domain is finite (5 × 5 × 4 × 4 = 400 combinations). Tool: `synesyn/synesyn_client/pendulum_bridge/turn_processing/validate_selection_paths.py`. Report: `docs_for_update_on_bindings_odu_matrix_refinement/validation_report_selection_paths.md`.
    Overall status: **PASS**.
    - Structural checks all green:
      - Quadrant coherence of `_select_binding`: 25/25 (dominant, secondary) combinations stay within the expected quadrant.
      - Canonical-Odu surjectivity of `_select_odu_mode`: all 16 `canonical_index` values reachable by the 4×4 quantization.
      - Preset completeness of `_compose_preset`: all 400 compositions produce non-empty presets containing every key `assemble()` reads.
    - Intentional divergences catalogued:
      - `concept_name` axis shift — legacy exposes scenario concepts (`Foundation & Origin`, `Signal & Threshold`, …), Option B exposes UWP bindings (`Heaven & Earth`, `Fire & Forge`, …). This is why the oracle activates only under `uwp_16x16`: the CSV is binding-keyed.
      - Odu overlap — Option B's selected Odu matches legacy's for exactly one pendulum bin per (dominant, secondary) cell (16 coincidences across 400 combinations). Expected: the two paths decouple Odu selection from the `_bead_sub_index` signal, so beyond the single coincidental bin they diverge.
    - Incidental finding worth flagging for task 11: the legacy ontology's `concept_name` field reuses some UWP binding names (`Face & Mirror`, `Memory & Myth`) for Odu that Option B would NOT map to those bindings — evidence that the legacy scenario-concept lattice was never cleanly separated from the UWP-binding lattice. Option B cleanly separates them.
    - Re-run on ontology or rule changes: `python synesyn/synesyn_client/pendulum_bridge/turn_processing/validate_selection_paths.py`. Exit code is non-zero on structural failure.
11. [x] **2026-04-16 — Deprecated the legacy quadrant path** (Option A of the task-11 trade-off options). All runtime switches between "legacy" and "Option B" are gone; Option B is the only selection path. Changes landed in a single pass:
    - `uwp_16x16_ontology.proposal.json` renamed to `uwp_16x16_ontology.json` (now the canonical production asset, not a proposal).
    - `sector_odu_pool` and `bead_sub_index` removed from `odu_ontology.json`. The within-quadrant canonical order (`Fount:0, Ethos:1, Cycle:2, Will:3, Seed:0`) now lives as a `const BEAD_SUB_INDEX` in `turn_packet_assembler.gd` because it is a design decision owned by the assembler, not the narrative ontology.
    - `ontology_mode` feature flag deleted from `bridge_config.json` (replaced by a `_ontology_mode_comment` explaining the retirement so any stale references in the wider codebase will still lead a reader to the rationale). Godot side: the `var _ontology_mode`, the `_init` ingestion, the `match _ontology_mode` branch in `assemble()`, the `_select_odu` legacy helper, the per-instance `_sector_pool` / `_bead_sub_index` state, the `_uwp_16x16_fallback_warned` flag, and the `ontology_mode` field in `matrix_resolution` are all gone. If the Option B JSON fails to load, `assemble()` pushes a warning and returns `{}` — no silent fallback, turns simply pause until the file is restored.
    - Python bridge: `TurnPacketAssembler._select_odu` and `_sector_pool` / `_bead_sub_index` state removed. `process_turn` now raises `NotImplementedError` with a pointer to `turn_packet_assembler.gd` and this section of the design doc. The helper methods (`_build_board_beads`, `_summarize_axes`, `_compute_resonance`, `_build_quality`, etc.) are intentionally kept for a future Option B port. `time` and `uwp_traversal_analyzer` imports were removed (unused post-stub) with a comment noting the port will re-add them.
    - `validate_selection_paths.py` reworked to an Option-B-only structural validator. Reads `odu_ontology.json` (odu only) and `uwp_16x16_ontology.json`; no longer loads `sector_odu_pool` / `bead_sub_index`; `BEAD_SUB_INDEX` mirrored as a module constant so the validator stays standalone. The legacy-vs-Option-B diff tables (concept shift, Odu overlap) were dropped as they no longer describe live behaviour. The report is now a structural checker + reference-tables document.
    - Re-ran the validator after the changes. Result: **PASS**. 16 narrative Odu, 16 bindings, 16 ifa_odu, 0 cell overrides loaded; quadrant coherence OK on all 25 (dominant, secondary) cells; 4×4 canonical-index surjectivity OK; all 400 preset compositions produced non-empty presets with every required key.
    - Hardware-mimic UDP test harness (`pendulum_hardware_dev/updated_files_to_use/stochastic_udp_test.py`) is unaffected — its `_SECTOR_ODU_POOL` / `_BEAD_SUB_INDEX` are already decoupled from `odu_ontology.json` (task 12b). `input_test_sim/stochastic_udp_test.py` (narrative sweep) is also unaffected — it reads the `odu` array only.
12. [x] **2026-04-16 — Unified the Python ontology mirror.** `pendulum_bridge/turn_processing/turn_packet_assembler.py` now loads `odu_ontology.json` at runtime via a new `_load_ontology(path)` function; the 450-line inline `_ODU_ONTOLOGY` + `_SECTOR_ODU_POOL` + `_BEAD_SUB_INDEX` + `_ODU_BY_NAME` block has been deleted. `TurnPacketAssembler.__init__` resolves `config["ontology_path"]` (defaulting to the Godot-side canonical JSON, computed from `__file__`), loads it, and stores the lookup tables per-instance. `_select_odu` is now an instance method. Verified by constructing the assembler on the real JSON and confirming selection results match the validation report cells. File size halved (~837 → ~412 lines). Option B selection parity in Python is NOT included (warn-and-fallback preserved); see Section 9 for the rationale and the pointer to what Python Option B would require.
12b. [x] **2026-04-16 — Unified the udp-test-harness ontology copies.** While investigating whether the Python bridge powers the udp test harness, I discovered that `input_test_sim/stochastic_udp_test.py` and `pendulum_hardware_dev/updated_files_to_use/stochastic_udp_test.py` each embedded their own stale 430-line copy of `_ODU_ONTOLOGY` (both still using `OGBE MEJI`, pre-rename) — a third and fourth single-source-of-truth violation, not just the Python bridge. Both copies now load `odu_ontology.json` at runtime via the same `_load_odu_ontology()` pattern used in task 12, with a `_REPO_ROOT`-relative `_ONTOLOGY_PATH` and the same fail-loud-on-missing-file / 16-entries-expected checks. Distinct purposes preserved: `input_test_sim/` cycles through all 16 Odu by index for narrative-content sweeps, while `pendulum_hardware_dev/updated_files_to_use/` replicates the hardware bridge's `_select_odu(dominant_sector, secondary_bead)` logic for production-shape packet testing. Two inline fixes landed in the hardware-like copy: `_SECTOR_ODU_POOL["Fount"][0]` `OGBE MEJI → EJI OGBE`, and `_BEAD_SUB_INDEX` reordered from stale `{Fount:0, Ethos:1, Will:2, Cycle:3, Seed:0}` to canonical `{Fount:0, Ethos:1, Cycle:2, Will:3, Seed:0}` (matching Section 3 and `odu_ontology.json`). `_SECTOR_ODU_POOL` and `_BEAD_SUB_INDEX` remain inline in that copy by design — those fields will be *removed* from `odu_ontology.json` in task 11, so the harness cannot source them from JSON without also owning the Option B selection logic. Verified via a transient smoke-test that loaded both modules, confirmed 16 Odu, confirmed `EJI OGBE` present and `OGBE MEJI` absent, built a sample packet from each, and spot-checked four `_select_odu` cells against canonical ordering — all passed. Both copies kept at user request; the user may deduplicate later. File size: input_test_sim 850 → 416 lines; pendulum_hardware_dev 878 → 444 lines.

## 13. File & Code Reference Index

For a cold-start executor, the key entry points:

- **Binding definitions**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/scenarios/Utopian_Wheel_16_Bindings.csv` — read row order as canonical.
- **Cross-system cells**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/scenarios/Utopian_Wheel_x_Ifa_Odu_Relational_Matrix.csv.txt` — 16 bindings × 16 Odu interpretive phrases.
- **Narrative ontology**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/odu_ontology.json` — edit here for narrative Odu changes. Post task 11 (2026-04-16) contains only the `odu` array; legacy `sector_odu_pool` / `bead_sub_index` are gone.
- **Option B ontology**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/uwp_16x16_ontology.json` — canonical three-lattice schema (`uwp_bindings`, `ifa_odu`, `binding_x_odu`). Was `uwp_16x16_ontology.proposal.json` until task 11.
- **Python bridge (task-11 stub)**: `synesyn/synesyn_client/pendulum_bridge/turn_processing/turn_packet_assembler.py` — `_load_ontology(path)` loader near the top of the file and `_DEFAULT_ONTOLOGY_PATH` constant. `TurnPacketAssembler.process_turn` raises `NotImplementedError` after task 11 (legacy path retired; Option B port deferred). Board/axes/resonance helpers preserved for the port.
- **Turn selection (live)**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/turn_packet_assembler.gd` — Option-B-only after task 11. Entry points: `_load_ontology()` (narrative), `_load_uwp_16x16_ontology()` (three lattices), `_select_binding()`, `_select_odu_mode()`, `_compose_preset()`. The within-quadrant canonical order lives as `const BEAD_SUB_INDEX` on this file.
- **Selection-path validator**: `synesyn/synesyn_client/pendulum_bridge/turn_processing/validate_selection_paths.py` — Option-B-only structural checker (after task 11). Exhaustively enumerates the 5×5 (dominant, secondary) and 4×4 pendulum grids, verifies quadrant coherence, canonical-index surjectivity, and preset completeness, and writes `docs_for_update_on_bindings_odu_matrix_refinement/validation_report_selection_paths.md`. Exit code non-zero on structural failure. Re-run after any ontology or rule change.
- **Validation report (latest)**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/docs_for_update_on_bindings_odu_matrix_refinement/validation_report_selection_paths.md` — canonical structural-validation snapshot for Option B.
- **Scenario config**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/scenarios/stochastic_dreams.txt` — `[RELATIONAL_MATRIX]`, `[PLAYER_AUTO_INPUT]` (now includes `concept_field`, `state_field`, `{oracle}` in `template_echo`).
- **Bridge runtime config**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/bridge_config.json` — consumed by `pendulum_bridge.gd::_load_config()` and forwarded into `SDTurnPacketAssembler._init()`. Post task 11 contains no `ontology_mode` flag; a `_ontology_mode_comment` explains the retirement for anyone grepping for old references.
- **Oracle lookup**: `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/metaprompt_manager_cultural_narrative.gd` — `consult_oracle(concept_key, state_key, scenario)`.
- **Oracle caller**: `synesyn/synesyn_client/ScenSyn/scripts/core/player_auto_input.gd` — `_resolve_oracle()` and the `{oracle}` template substitution.
- **Wheel images**: `UtopianWheelOfProgress.png`, `UWP_with_icons_5.png` at the workspace root.
- **udp test harness (narrative sweep)**: `input_test_sim/stochastic_udp_test.py` — standalone simulator. Loads `odu_ontology.json` at runtime; cycles through all 16 Odu by index. Ships packets direct to Godot UDP 5001 or to Synesyn Hub UDP 5000. Does NOT depend on the Python bridge.
- **udp test harness (hardware mimic)**: `pendulum_hardware_dev/updated_files_to_use/stochastic_udp_test.py` — as above, plus replicates `_select_odu(dominant_sector, secondary_bead)` with inline `_SECTOR_ODU_POOL` / `_BEAD_SUB_INDEX` matching the canonical ordering. Use this copy when you want the simulator to produce the same Odu a real pendulum+board turn would.
- **How-to for the udp harness**: `input_test_sim/how-to-use-the-udp-test.txt` — tuning guide for `SEND_AS_SEQUENCE`, `TARGET_MODE`, `DELAY_SECONDS`, etc.

## 14. Replication Guide (post-task-11 end state)

Added 2026-04-16. This appendix exists so a cold-start agent or human on a different machine, starting from a clone of the same codebase in its pre-task-1 state, can reproduce every change recorded in this document without additional conversation.

### 14.1 Two replication paths

You can replay the full design trajectory or fast-forward to the end state.

- **Incremental replay.** Execute §12 tasks 1 through 12b in numerical order. Each task entry lists the files touched and the exact transformations. Task 11 intentionally retires the `ontology_mode` scaffolding added in tasks 5, 8, 9 — that is not redundancy; it reflects that validation (task 10) satisfied the condition under which the legacy path could be deleted. If you want to understand the reasoning, this is the path to take.
- **Fast-forward.** Apply the task 11 end state directly to the pre-task-1 files: use §14.2 below as the file-state checklist. You still need the §12 task 5 payload content — the 16 `uwp_bindings` and 16 `ifa_odu` entries — which is anchored by §3.2 and §3.3 and physically lives in the existing `uwp_16x16_ontology.proposal.json` file in the repo (rename it as step 1). You can then skip the intermediate `ontology_mode` plumbing entirely.

Either way, the acceptance test is the same: the validator in §14.3 must print `Overall status: PASS`.

### 14.2 Post-task-11 file-state checklist

The canonical end state across the five modified runtime artifacts.

**(a) `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/odu_ontology.json`**

- Top-level keys: exactly `{ "odu": [...] }`. No `sector_odu_pool`. No `bead_sub_index`.
- The `odu` array has exactly 16 entries, each with the keys listed in §5.1 (unchanged from pre-design: `odu_name`, `odu_bits`, `concept_id`, `concept_name`, `utopian_domain`, `predicament_family_id`, `predicament_family`, `complementary_odu`, `tapestry_region_primary`, `tapestry_region_secondary`, `province_or_site`, `world_domain_focus`, `failure_state_risk`, `flourishing_state_potential`, and the diviner/echo/seeker/narrator cue blocks).
- `odu_name` values use canonical spellings (`EJI OGBE`, not `OGBE MEJI`) per §3.3 / task 6.

**(b) `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/uwp_16x16_ontology.json`**

- Filename ends in `.json`, not `.proposal.json`.
- Top-level keys: `{ "uwp_bindings": [...], "ifa_odu": [...], "binding_x_odu": {...} }`.
- `uwp_bindings` has 16 entries per the spec in §8.2 and the ordering in §3.2. Keys per entry: `id` (1..16), `binding_name`, `quadrant` (one of `Fount`/`Ethos`/`Cycle`/`Will`), `domain`, `tension`, `thesis`, `tapestry_region_primary`, `province_or_site`, `world_domain_focus` (the last three may be empty strings pending Open Question 4).
- `ifa_odu` has 16 entries per §8.2 and §3.3. Keys: `odu_name`, `odu_bits`, `canonical_index` (1..16), `modal_essence`, `canonical_meaning`.
- `binding_x_odu` is present and may be empty (`{}`) in v1; keys follow the format `"<binding_id>.<odu_id>"`.

**(c) `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/turn_packet_assembler.gd`**

- Module constants present: `CLASS_TO_BEAD`, `QUADRANT_OFFSETS` (Fount:0, Ethos:4, Cycle:8, Will:12), `BEAD_SUB_INDEX` (Fount:0, Ethos:1, Cycle:2, Will:3, Seed:0).
- State vars present: `_board_w`, `_board_h`, `_sector_anchors`, `_odu_list`, `_odu_by_name`, and the Option B lattice fields `_uwp_bindings`, `_ifa_odu`, `_binding_x_odu`, `_binding_by_id`, `_odu_by_canonical_index`, `_uwp_16x16_loaded`.
- State vars absent (all removed by task 11): `_sector_pool`, `_bead_sub_index`, `_ontology_mode`, `_uwp_16x16_fallback_warned`.
- Functions present: `_init`, `_load_ontology`, `_load_uwp_16x16_ontology`, `assemble`, `_select_binding`, `_select_odu_mode`, `_compose_preset`, and the pure board/axes/quality/resonance helpers. The selection helpers must implement §8.6 exactly.
- Functions absent: `_select_odu` (the legacy single-step selector).
- `assemble()` has no `match _ontology_mode` block; if `_uwp_16x16_loaded` is false it warns and returns `{}`, and if `_compose_preset` returns `{}` it does the same — no legacy fallback.
- `matrix_resolution` emitted by `assemble()` includes `binding_id` and `binding_name`, and does NOT include `ontology_mode`.
- `_load_uwp_16x16_ontology()` reads `res://ScenSyn/session_types/story_catalyst/cultural_narratives/stochastic_dreams/uwp_16x16_ontology.json` (no `.proposal` suffix).

**(d) `synesyn/synesyn_client/ScenSyn/scenario_themes/cultural_narratives/stochastic_dreams/bridge_config.json`**

- Does NOT contain an `"ontology_mode"` key. May contain a `"_ontology_mode_comment"` explaining the retirement (present in the current workspace); this comment is advisory and can be omitted if desired.
- The rest of the file (osc ports, pendulum frame dims, sector anchors) is unchanged from pre-design.

**(e) `synesyn/synesyn_client/pendulum_bridge/turn_processing/turn_packet_assembler.py`**

- Module-level: imports `json`, `logging`, `math`, `socket`, `Path` from `pathlib`, and `Any`, `Dict`, `List`, `Optional`, `Tuple` from `typing`. Does NOT import `time` or `uwp_traversal_analyzer` (removed under task 11; comment in the file notes the future Option B port will re-add them).
- Module-level: `_THIS_DIR`, `_DEFAULT_ONTOLOGY_PATH`, and `_load_ontology(path)` present. `_load_ontology` returns a dict with exactly two keys: `"odu_list"` and `"odu_by_name"` (no sector_pool, no bead_sub_index).
- Module-level: no `_ODU_ONTOLOGY`, no `_SECTOR_ODU_POOL`, no `_BEAD_SUB_INDEX`, no `_ODU_BY_NAME` constants, no module-level `_select_odu`.
- `TurnPacketAssembler.__init__` stores only `_odu_list` and `_odu_by_name` (plus UDP/socket/target state). No `_sector_pool`, `_bead_sub_index`, or `_ontology_mode` instance fields.
- `TurnPacketAssembler.process_turn` raises `NotImplementedError` with a message pointing to `turn_packet_assembler.gd` and §9 / §11 of this doc. The class does NOT contain a `_select_odu` method.
- Helper methods (`_build_board_beads`, `_pick_primary_secondary`, `_summarize_axes`, `_compute_perturbation_factor`, `_compute_resonance`, `_build_quality`, `_send_packet`, `close`) and the module-level `_clamp01`, `_axis_x_label`, `_axis_y_label` helpers are all retained unchanged — they are pure and will be reused by the future Option B port.

**(f) `synesyn/synesyn_client/pendulum_bridge/turn_processing/validate_selection_paths.py`**

- Structure: Option-B-only structural validator. Loads `odu_ontology.json` (odu only) and `uwp_16x16_ontology.json`. Mirrors `BEAD_SUB_INDEX` and `QUADRANT_OFFSETS` as module constants so the validator is standalone.
- Checks performed: `quadrant_coherence_check`, `odu_surjectivity_check`, `odu_preset_completeness_check` (per §12 task 10 and §8.6.1-3). The 400-combination preset enumeration must pass.
- Absent: any `legacy_select_odu`, `load_legacy_ontology`, `quadrant_of_odu`, `build_concept_name_shift`, `odu_overlap_analysis` — task 11 removed these since there is nothing to diff against.
- Output: writes `docs_for_update_on_bindings_odu_matrix_refinement/validation_report_selection_paths.md` and returns exit code 0 on pass, non-zero on structural failure.

**(g) UDP test harnesses** (already landed under task 12b; task 11 does NOT change them)

- `input_test_sim/stochastic_udp_test.py`: loads `odu_ontology.json` at runtime via `_load_odu_ontology()`. Cycles through all 16 Odu by index. No selection logic.
- `pendulum_hardware_dev/updated_files_to_use/stochastic_udp_test.py`: loads `odu_ontology.json` at runtime via `_load_odu_ontology()`; additionally holds inline `_SECTOR_ODU_POOL` and `_BEAD_SUB_INDEX` (canonical order) to replicate the historical hardware-bridge selection logic for production-shape packet generation. These remain inline by design — their removal from `odu_ontology.json` in task 11 is exactly why this harness cannot source them from JSON.

### 14.3 Acceptance test

From the workspace root on a clean shell:

```bash
python synesyn/synesyn_client/pendulum_bridge/turn_processing/validate_selection_paths.py
```

Expected tail of output:

```
Report written to .../docs_for_update_on_bindings_odu_matrix_refinement/validation_report_selection_paths.md
Overall status: PASS
```

The command returns exit code 0 on pass. The generated report should show:

- Quadrant coherence: 25/25 `(dominant, secondary)` combinations stay within expected quadrant.
- Canonical-index surjectivity: all 16 canonical indices reachable by the 4x4 pendulum quantization.
- Preset completeness: 400/400 preset compositions produce non-empty presets with every required key.

If any of these fail, the report lists the specific failing combinations and the script exits non-zero.

### 14.4 Deliberately out of scope

The following were noted during the work but are not part of the replication scope:

- **Task 3** (wheel image regeneration for `UtopianWheelOfProgress.png` and `UWP_with_icons_5.png` to match §3.2 intra-quadrant order) was deferred by user request on 2026-04-16. A replicator reproducing this trajectory can leave the current PNGs as-is; no runtime consumer reads them.
- **Python Option B parity** is not implemented. The Godot assembler is the live production path. If the Python bridge is ever needed to emit packets again, port `_load_uwp_16x16_ontology`, `_select_binding`, `_select_odu_mode`, and `_compose_preset` from the Godot file; §9 flags this explicitly.
- **Open Question 4** (populating per-binding `tapestry_region_primary` / `province_or_site` / `world_domain_focus` on `uwp_16x16_ontology.json`) is still open. The fields currently hold empty strings; the validator accepts that (legacy fields on the narrative Odu carry through via the preset merge order in §8.6.3).
