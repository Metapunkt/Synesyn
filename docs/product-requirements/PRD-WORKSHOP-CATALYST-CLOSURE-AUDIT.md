---
id: PRD-WORKSHOP-CATALYST-CLOSURE-AUDIT
title: Workshop Catalyst Closure Audit stage
status: implementing
version: "0.1"
owner: Workshop Catalyst product owner
last_reviewed: 2026-09-05
primary_users: [facilitator, workshop participant]
supersedes: null
---

# Workshop Catalyst Closure Audit stage

## Problem and outcome

Workshop Catalyst moves a room toward closure. Its whole pipeline — propose,
review, preview, commit — is closure in Lawson's sense, and ADR 0012 already names
it that way. What it cannot do is tell a facilitator that the closure arrived too
early.

The Thinking Map sorts claims into Causes, Effects, and Opportunities. Placed on
the Closure Map's axes, that triad occupies only the distal half: Cause is
A Distal Past, Effect and Opportunity are B Distal Future. Nothing represents
C Deep Past (assumption, habit, incentive, incorporated pattern) or D Deep Future
(latent capability, tendency, formation already under way). The three symbolic
checks compound this by reading only what is present, whereas Closure Mapping's
primary diagnostics read shape — the empty quadrant and the concentrated one.

The practical risk is specific to an AI-assisted tool: four specialist lenses will
readily fill three distal columns with plausible material, and the room will feel
thorough while never asking what it has already incorporated.

**Outcome:** A facilitator can run a bounded Closure Audit inside a Workshop
Catalyst session, see where the group's thinking is concentrated and what is
absent, classify each absence rather than filling it for symmetry, and leave with
a Closure-to-Action Sheet whose reopening actions carry an owner, a date, and a
statement of what evidence would change the decision.

Canonical theory: [`../concepts/closure-map.md`](../concepts/closure-map.md),
`Closure_Map_Improved_Exposition.docx`, `Closure_Mapping_Operational_Manual.docx`.
Architecture: [ADR 0020](../architectural-decisions/0020-thinking-map-closure-map-boundary.md).

## Users and jobs

- **Facilitator:** Before committing a decision, they need to know which mode of
  situatedness the room has mistaken for the whole situation, so that they can
  reopen the weakest quadrant rather than ratify a confident narrative.
- **Participant:** During the audit they need a prompt that asks for something
  their own experience can answer — habits, incentives, what is already forming —
  so that deep material enters the record instead of being filed as a cause.
- **Decision owner (post-session):** They need a one-page sheet naming what was
  not examined and what would change the decision, so that the closure is
  auditable after the room has dispersed.

## Success measures

- A facilitator can complete an audit in 20–30 minutes without leaving the
  session, matching the Operational Manual's timing.
- Every weak or empty quadrant carries an explicit classification; none is left
  blank and none is filled with speculative material for symmetry.
- Closure debt is recorded only where the manual's four conditions hold.
- The sheet exports with at least one reopening action carrying owner, date, and
  falsifier.
- Coverage and concentration are derived read-only; no audit finding mutates the
  Thinking Map document.
- Skipping the audit changes nothing: an untagged session remains fully valid.

## Scope

The work is phased so that each phase is independently useful and shippable.
Phase 1 makes the depth axis representable and the shape readable; phase 2 adds
the ritual; phase 3 adds the artifact.

### Phase 1 — orientation facet and shape reading (in scope)

- Optional `orientation` annotation on Thinking Map nodes, reusing the SynAxes
  quadrant vocabulary verbatim.
- A shared vocabulary module holding the quadrants, their machine and display
  labels, the map version, the quadrant characterisations and prompts, and the six
  tetrahedral edges — so the card control, the rules, and the phase 2 surface
  cannot drift from each other or from SynAxes.
  - It lives in `addons/synesyn_core/scripts/closure_orientation.gd`, not under
    `synesyn_client/ScenSyn/session_types/workshop_catalyst/`, and SynAxes reads the same file. Held under
    ScenSyn it could not have been shared at all, since an addon may not depend on
    host code (ADR 0017 rule 1), and "shared" would have meant a second copy kept in
    step by hand — which failed the first time the glosses were revised. See ADR 0020,
    amended 2026-09-06.
  - It also carries the plain glosses, temporal roles and axis readings transcribed
    from the Improved Exposition's "Terminology: Canonical Terms and Plain Glosses"
    table (Inherited History, Projected Future, Embedded Culture, Emergent
    Potential). These are defined upstream, not authored here, so they are
    transcribed verbatim and covered by a headless test that fails if any cell
    drifts.
  - Scoping rule, following the Exposition: a gloss never replaces a canonical term
    in the map itself, in a closure profile, or in any reference to a tetrahedral
    edge. The gloss therefore leads only in the per-card picker, where speed of
    recognition is the whole point; every reading that names a quadrant *as a
    coordinate* uses `get_canonical_with_gloss()`, which renders "C Deep Past
    (Embedded Culture)".
- A per-card orientation control, surfaced only while the audit is active.
- An audit toggle in the map footer, beside the coverage reading it governs. Phase
  1 needs one because "while the audit is active" has no meaning until phase 2
  builds the surface, and a control that can never appear cannot be shipped or
  judged. The toggle is what phase 2's surface later opens; it is not a second way
  in.
  - Not the toolbar. The toolbar is the widest row in the map and therefore sets
    the Workshop shell's whole horizontal floor: at the medium breakpoint the
    shell's minimum was already within 30px of the viewport, so one more
    `CheckButton` there overflowed the shell and pinned every split dragger at its
    minimum. The footer holds autowrapping status labels and carries roughly 450px
    of slack before it binds anything. Treat the map toolbar as closed to new
    controls unless something leaves it.
- A new read-only rules module deriving coverage (per-quadrant counts plus
  untagged) and concentration (dominant quadrant, weak and empty quadrants).
- Extension of the existing symbolic-checks status line with the closure reading.
- Harness snapshot fields for the derived counts.

### Phase 2 — the audit ritual (in scope)

- A bounded Closure Audit surface running the manual's sequence: decision stated
  at the centre as Here-and-Now, four quadrant prompts, silent individual entry,
  then the three diagnostics in order.
- Assisted orientation: an on-demand pass that suggests one quadrant per claim, or
  "none of these applies", which the facilitator accepts or changes card by card.
  This is the same propose-then-close shape as accepting an AI claim or a path
  proposal, and it exists because orienting from a blank page is where the real
  cognitive load sits — four abstract quadrants against every claim will otherwise
  either stall the session or produce careless tags, and a careless tag is worse
  than no tag. Suggestions are single and concrete rather than a ranked shortlist
  with per-option justification: reading an argument for each candidate on every
  card is more work than judging one proposal, not less.
- **REQ-CA-017 — the facilitator closes orientation, and disagreement is recorded.**
  Silent individual entry from the manual has no home in a single shared map, and its
  anti-anchoring purpose was already served upstream by the conversation that produced
  the claims (ADR 0020, amended 2026-09-06). So the facilitator orients alone, and a
  claim may be marked **contested** when the room did not converge.
  - Contested is not a vote. `VoteTally` is binary yes/no for closure formation and
    cannot express a five-way categorical choice; and a majority orientation would be a
    careless tag with democratic cover.
  - It applies with or without a quadrant, is orthogonal to review and commit, and is
    stored as a sibling annotation (`orientation_contested`) rather than inside
    `orientation`, so the persisted `ui.closure` schema v2 shape is untouched.
  - The count is reported ungated, unlike dominant/weak/empty: those need a sample,
    whereas one contested claim is already true. Contested claims are candidates for
    Session Record `open_questions` when the audit routes its output.
  - **This is contested placement, which REQ-CA-010 does not cover.** REQ-CA-010's
    register addresses contested material *within* a quadrant — agreement on where a claim
    sits, disagreement on whether it holds. Contested placement is disagreement about the
    quadrant itself. Neither subsumes the other, but the register's four fields fit both,
    so it should carry a dimension (`placement` or `substance`) rather than be duplicated.
    The boolean is the degenerate placement case and leaves REQ-CA-010 unmet.
  - Marking a contested claim with a quadrant is not averaging it into a consensus
    statement: the tag is where it sits for the map's reading, and the register survives
    alongside it.
- **REQ-CA-018 — participant orientation views are placement positions.** A participant's
  view of where a claim sits is stored as a position on the register's `placement`
  dimension, not in a store of its own, because a view and a placement position are the
  same fact: a named holder, a quadrant, and the evidence behind it. Three consequences
  follow, and they are why the unification is worth having.
  - **Contestation is derived, not asserted.** Two or more distinct views on a claim make
    it contested with nobody having to judge that it is. The asserted flag remains for the
    ordinary case where the room split out loud and no views were entered, and the two are
    counted apart: a facilitator's mark is a judgement about a conversation, divergent
    recorded views are the disagreement itself.
  - **REQ-CA-011's source labelling comes free**, since every position names its holder.
  - **One holder holds one view.** Re-recording replaces, so a participant who changes
    their mind does not appear twice and inflate the spread.
  - Views reuse propose → review → commit rather than adding a second authority model: a
    participant's view arrives `unreviewed`, the facilitator reviews it, and reviewing
    means *acknowledged*, not adopted — it does not alter the view and does not touch the
    facilitator's own tag, which stays the only canonical orientation.
  - Views are **attributed, not anonymised**. REQ-CA-010 asks who holds each view, and
    "what test would discriminate between these readings?" is unanswerable without knowing
    whose readings they are and what evidence each rests on.
  - An emptied register is pruned from the node, so a claim whose positions were all
    withdrawn is indistinguishable from one that never had any and no empty register
    reaches an export.
- **REQ-CA-019 — views stay closed until revealed, and the reveal is one-way.** Nobody
  sees anyone else's view before the facilitator reveals them, *including the facilitator*:
  a participant who can see that three others said C is no longer recording an independent
  reading, and a facilitator who can see it is no longer tagging independently either.
  This is where the manual's silent individual entry actually belongs in our siting — at
  orientation, not generation. Before reveal the surfaces report participation only ("5
  claim(s) have views", "3 view(s) entered") and never which quadrant. Reveal cannot be
  undone, because re-hiding views the room has already discussed would record a retraction
  that did not happen. The flag is session state on the map rather than an annotation, so
  it survives a reload and reaches peers without entering the committed artifact.
- **REQ-CA-020 — two surfaces, two questions.** A compact badge on each card answers "is
  this one disputed"; a divergence-ordered panel answers "which claims did the room turn
  out not to share", which no single card can. The panel orders by distinct views and then
  by how many people weighed in, so a three-way split outranks a two-way one and a
  two-way split among six outranks the same split among two. Claims whose views *agree*
  stay listed below the divided ones — "we all read this the same way" is also a finding,
  and a list showing only disagreements would make a well-aligned room look idle. Claims
  marked contested with no views recorded sort with the divided ones, since the absence of
  views is not evidence of agreement. The panel is read-only apart from Reveal and so is
  not gated on the facilitator claim.
- **REQ-CA-021 — the audit may be drafted, never decided** (added 2026-09-07). A
  facilitator can ask the model to draft answers to the audit's steps from the claims on the
  map: the decision under audit, why each near-empty quadrant is empty and what that gap
  could cost, what the pile-up in the busiest quadrant means, the one move that would fix the
  worst gap, and up to three reopening actions with the result that would settle each. Drafts
  are held outside `WorkshopClosureAuditRecord`, so the completion gate cannot be satisfied by
  them; each renders as a labelled "Suggested:" strip carrying the model's reason, with Accept
  and Dismiss; and drafts expire when the audit closes. A value that fails validation against
  the vocabularies is dropped rather than coerced to the nearest match.

  Two things are outside the pass. **Closure debt is never drafted** — its four conditions ask
  what the room did, which a model reading the map cannot know, and a plausible answer would
  forge a record of the room's own conduct. **An action's owner and date are never drafted**,
  so a drafted action offers *Fill in* rather than *Accept*: it populates the fields and leaves
  the commitment blank. This supersedes the earlier position that nothing in the audit may be
  model-drafted; see ADR 0020's 2026-09-07 amendment for why refusing to draft produced no
  audit rather than a more careful one.
- Empty-quadrant classification: not applicable, deliberately excluded, unknown,
  suppressed, not-yet-formed.
- Consequence × confidence triage producing accept / cheap check / monitor /
  reopen.
- Concentration classification: legitimate focus, expertise bias, fixation,
  suppression, premature closure.
- Closure debt register gated on the manual's four conditions.
- Required transition captured as one line naming a tetrahedral edge.
- Reopening questions proposed into Session Record `open_questions`; reopening
  actions into `next_steps` and `owners`.
- An `Outcomes` column on the Thinking Map so `decision`, `risk`, `owner`, and
  `next_step` nodes render where they belong (see the defect note below).

### Phase 3 — the sheet artifact (in scope)

- `ui.workshop_closure_audit` artifact with hub validation.
- Markdown export of the Closure-to-Action Sheet.
- Optional promotion of the audit to a default agenda stage after manual
  acceptance.

### Out of scope

- Replacing Causes / Effects / Opportunities with quadrants A–D.
- Autonomous orientation. The model may suggest a quadrant per claim on demand and
  the human accepts or changes it, as with every other proposal in the product; what
  is excluded is a tag taking effect without a person closing it, and any ambient
  tagging that runs without being asked.
- Plotting the Thinking Map graph on Closure Map axes, or any 2×2 / tetrahedral
  diagram. The tetrahedral edge appears as one line of text.
- Proxistance as a navigation mode. The overview/close-up move is a facilitator
  prompt in phase 2, not a UI behaviour.
- Continuous ambient orientation tagging outside the audit.
- Changing what specialist extraction may propose (`cause|effect|opportunity`
  stays as it is).
- Importing Thinking Map graphs into SynAxes, or vice versa. ADR 0008's
  no-silent-conversion rule holds.

## Critical journey

1. The facilitator reaches the Closure Audit stage. The agenda timer starts; the
   stage contract states the required output before advancing.
2. The decision under audit is stated in one sentence as Here-and-Now. The
   facilitator confirms the wording with the room.
3. The audit surface presents the four prompts. Participants enter silently,
   before discussion, and entries are labelled by source — authorship is data.
4. Entries are posted; duplicates grouped; contested items marked. Existing
   Thinking Map claims can be pulled in and oriented rather than re-typed.
5. The facilitator reads the geometry: dominant closure, then weak or empty
   quadrants.
6. Each anomaly is diagnosed before any conclusion is drawn. Empty quadrants are
   classified and triaged; concentration is classified.
7. The required transition is named as one edge, in the form
   `dominant → neglected (edge XY) by <action>`.
8. Reopening questions and actions are proposed, reviewed, and committed through
   the existing Session Record path.
9. The sheet is previewed and committed. The closing question is not whether the
   map looks balanced but: given the closure debt, what changes in the proposal.

## Facilitation contract for the stage

The stage uses the existing four-part `[STAGE_GUIDANCE]` contract, keyed by the
exact stage name. The draft below is here because it is the design; once the stage
ships, the facilitator manual owns this text and this section links to it.

```text
--- Closure Audit: what have we already closed? ---
Facilitator goal: establish where the room's thinking is concentrated and what it
has not examined, and convert each material absence into a named reopening action
with an owner.
AI goal: hold the distinction between the two pasts and the two futures. Distal
Past is what happened out there; Deep Past is what that past has become inside
the organisation. Never let "Deep" be heard as how people feel. Ask for evidence
that can be checked, cited, witnessed, or observed, and label beliefs as beliefs.
Required output before advancing: a classification for every weak or empty
quadrant, one named required transition, and at least one reopening action with an
owner and a statement of what evidence would change the decision.
Decision-forcing question: "Given what we have not examined, what changes in the
proposal — the brief, the metric, the timing, or the decision itself?"
```

Two behaviours must be prompted explicitly because the manual identifies both as
the common failure modes:

- **Deep is not retreat.** Depth means institutional habit, embodied practice,
  language, inherited constraint, and latent capability — not privacy or
  sentiment. A room that hears otherwise produces a thin lower half.
- **Do not fill for symmetry.** An empty quadrant is an uncertainty
  classification problem, not a weakness.

Where a group stalls on placement, the facilitator asks for the same item twice,
at overview scale and close-up scale. An entry that survives both readings is
usually evidence; an entry that exists at only one scale marks where attention has
been fixed.

## UI sketch (phase 2 audit surface)

```text
┌─ Closure Audit ────────────────────────────── 18:42 remaining ─┐
│ Decision under audit (Here-and-Now):                           │
│  [ Adopt the shared assessment platform in September ________ ] │
│                                                                │
│              PAST                    FUTURE                    │
│  DISTAL  ┌──────────────────┬──────────────────┐               │
│          │ A  4 entries     │ B  9 entries     │  ← dominant   │
│          │ precedent,       │ projection,      │               │
│          │ regulation, …    │ forecast, …      │               │
│  ────────┼──────────────────┼──────────────────┤               │
│  DEEP    │ C  0 entries     │ D  1 entry       │               │
│          │ [classify ▾]     │ [classify ▾]     │               │
│          └──────────────────┴──────────────────┘               │
│                                                                │
│ Concentration: B — [ premature closure          ▾ ]            │
│ C is empty:    [ unknown ▾ ]  consequence [high ▾]             │
│                               confidence irrelevant [low ▾]    │
│                               → Reopen before committing       │
│                                                                │
│ Required transition:  B → C  (edge B–C)                        │
│  Test the projected future against habits, resistance, capacity │
│                                                                │
│ [ Propose reopening questions ]  [ Preview sheet ]             │
└────────────────────────────────────────────────────────────────┘
```

Per project convention the layout is authored in the `.tscn`, not built in
GDScript; only entry rows populated from data at runtime are created in code.

The per-card orientation control in phase 1 is an `OptionButton` with five values
(untagged, A, B, C, D), short labels and richer tooltips, matching the existing
SynAxes control so the vocabulary reads identically on both surfaces.

## Schema sketch

### Node orientation (phase 1)

Carried in the existing node `annotations`, so `graph_schema_version` and
`graph_kind` are unchanged and no relation or node kind is added.

```json
{
  "id": "tmn_…",
  "kind": "cause",
  "label": "…",
  "annotations": {
    "source_class": "participant_said",
    "orientation": {
      "quadrant": "C",
      "label": "deep_past",
      "map_version": "closure-map-2026-08"
    }
  }
}
```

| `quadrant` | `label` |
| --- | --- |
| `A` | `distal_past` |
| `B` | `distal_future` |
| `C` | `deep_past` |
| `D` | `deep_future` |

Omit `orientation` entirely when untagged. `map_version` is copied from the
SynAxes constant rather than redefined, so a future map revision invalidates both
surfaces together.

`validate_workshop_thinking_map()` checks that `annotations` is an object with a
valid `source_class` and does not enumerate permitted keys, so **phase 1 needs no
hub change**. Commits from an older client without the field remain valid, and
commits carrying it validate against the current hub.

### Derived findings (phase 1, never persisted as graph records)

```json
{
  "coverage": { "A": 4, "B": 9, "C": 0, "D": 1, "untagged": 3 },
  "tagged_count": 14,
  "untagged_count": 3,
  "axis_totals": { "distal": 13, "deep": 1, "past": 4, "future": 10 },
  "has_reading": true,
  "min_tagged_for_reading": 4,
  "dominant_quadrant": "B",
  "dominant_quadrants": ["B"],
  "weak_quadrants": ["D"],
  "empty_quadrants": ["C"]
}
```

Weak is defined relative to the dominant count rather than by an absolute floor,
so the reading scales with session size. The threshold is a named constant, not a
magic number, and the status line reports the rule it applied.

Three cases have to be distinguished from a genuine concentration, because each
would otherwise be reported as one:

- **Too little material.** Below `min_tagged_for_reading`, "dominant" and "empty"
  describe the sample rather than the room, so `has_reading` is false and no
  dominant, weak, or empty quadrant is named at all. The status line states the
  rule it applied, so a blank reading is never read as a balanced map.
- **A tie.** `dominant_quadrant` is empty and `dominant_quadrants` holds both, so
  a two-way tie does not get reported as a single closure — and §8.3's "two
  opposite quadrants dominate" stays computable from the same field.
- **A flat distribution.** All four level is coverage, not concentration, so
  nothing is named dominant.

`axis_totals` is not decoration: distal against deep is the direct reading of the
pathology this instrument exists to catch, and it is the one line a facilitator can
act on without learning the quadrant letters.

### Closure-to-Action Sheet (phase 3)

Seven elements, mapped onto existing Session Record structure wherever one fits:

| Sheet element | Storage |
| --- | --- |
| Decision under audit | `decisions`, or the audited `decision` node |
| Closure profile — weight, status, note per quadrant | new |
| Closure debt | new |
| Reopening questions | `open_questions` |
| Reopening actions — owner, date, falsifier | `next_steps` + `owners`, plus new fields |
| Revised decision | `decisions` |
| Required transition, review trigger | new |

Adding `ui.workshop_closure_audit` requires one constant and one branch in
`validate_workshop_artifact()` in `app/substrate/workshop_artifacts.py`, which is
the single dispatch point for artifact validators, plus a client persistence
coordinator mirroring the summary one. Any export resolves its path through
`RuntimeConfig` under `Documents/Synesyn` per ADR 0014.

## Known defect this work must fix

The Thinking Map renders three columns, and `refresh()` falls back to the
Opportunities column for any unrecognised node kind. The adapter and the hub
schema both already accept `decision`, `risk`, `owner`, and `next_step`, and
`get_routable_outcome()` routes them into Session Record categories — but nothing
in the default UI creates them, so the fallback is currently unreachable. The
moment the audit produces outcome nodes, those items would silently pile into
Opportunities. Phase 2 must add the `Outcomes` column before, or in the same
change as, the first path that creates an outcome node.

This also explains why the card's `ClosureButton` ("Create approved closure") is
effectively dormant today: it appears only for outcome kinds, which the UI never
creates. The audit activates a seam that is already wired end to end through
`ClosureBus` to `ui.workshop_closure` (ADR 0026).

## Requirements

- **REQ-CA-001:** A Thinking Map node may carry an optional `orientation` with
  quadrant A–D; absent means untagged, and untagged never blocks review, commit,
  or advance.
- **REQ-CA-002:** The orientation control appears only while the audit is active,
  and never during ordinary Talk / Map / Review facilitation.
- **REQ-CA-003:** Coverage and concentration are derived read-only, deterministic,
  and explainable, and never written back as nodes or edges.
- **REQ-CA-004:** A model may *suggest* a quadrant per claim, on explicit request
  during an audit, and the facilitator accepts or changes it. A suggestion is not a
  tag: only a human action writes `annotations.orientation`, and an unactioned
  suggestion counts as untagged everywhere, including in coverage and concentration.
- **REQ-CA-004a:** The suggestion vocabulary must include "none of these applies",
  and that answer must be as available to the model as the four quadrants. Without
  it, a classifier pressed to choose would populate every quadrant and the
  empty-quadrant reading — the audit's most useful diagnostic — would measure the
  model's willingness to guess rather than the room's attention.
- **REQ-CA-004b:** Provenance distinguishes a tag the facilitator set unaided, one
  they accepted as suggested, and one they changed from a suggestion, recording the
  suggested quadrant in the last case. This is what makes assisted orientation
  auditable rather than merely convenient: a session with near-total agreement
  between suggestion and outcome is evidence of rubber-stamping, and cannot be
  detected without it.
- **REQ-CA-004c:** Specialist batch extraction is unchanged. Its output remains
  `cause|effect|opportunity` with no orientation field, so orientation cannot arrive
  as a side effect of ordinary facilitation.
- **REQ-CA-005:** Every weak or empty quadrant must be classifiable as not
  applicable, deliberately excluded, unknown, suppressed, or not-yet-formed, and
  the audit cannot be marked complete while one is unclassified.
- **REQ-CA-005a** (added 2026-09-06): the audit also cannot be marked complete while the map
  holds too few oriented claims for the rules module to draw a reading, or while a dominant
  quadrant has no concentration classification. Both extend REQ-CA-005's principle to the
  other two diagnostics: the original wording gated the second diagnostic only, which let an
  audit close over a map nobody had oriented, and let one close with the concentration — the
  reading the manual is most insistent is ambiguous — untouched.
- **REQ-CA-006:** Triage records consequence-if-omitted against
  confidence-it-is-irrelevant, and yields accept, cheap check, monitor, or reopen.
- **REQ-CA-006a** (added 2026-09-07): the two bands are accepted independently. The record
  stores an incomplete pair and withholds the verdict until both are present, clearing it if
  one is removed. Stated because the original implementation rejected any call with an empty
  band, which — since the surface sends one band per selection — made the verdict unreachable
  and REQ-CA-006 unmet in full.
- **REQ-CA-007:** Closure debt is recorded only when the absence is material,
  unjustified, outcome-changing, and unsafeguarded.
- **REQ-CA-008:** A reopening action carries an owner, a date, and a statement of
  what evidence would change the decision.
- **REQ-CA-009:** The required transition is recorded as one tetrahedral edge with
  a direction, in the form `dominant → neglected (edge XY) by <action>`.
- **REQ-CA-010:** Contested material within a quadrant is recorded as a
  contestation register — who holds each view, the supporting evidence, which
  decision would differ, and what test discriminates — and is never averaged into
  a consensus statement.
- **REQ-CA-011:** Entries are labelled by source, and the audit reports whether
  one participant supplied one quadrant.
- **REQ-CA-012:** The `Outcomes` column exists before any path creates a
  `decision`, `risk`, `owner`, or `next_step` node.
- **REQ-CA-013:** Reopening questions and actions enter the Session Record through
  the existing propose → review → commit path, under facilitator authority.
- **REQ-CA-014:** A session that never opens the audit behaves exactly as it does
  today.
- **REQ-CA-015:** Orienting a claim is not a review decision. It leaves the
  claim's status, review status, and the decision ledger untouched, so orienting a
  suggested claim never promotes it past the facilitator. It is also not gated on
  the claim being uncommitted, unlike revise and withdraw: an audit run after a map
  commit is the expected case, and re-orienting shows up in the next preview diff
  like any other correction.
- **REQ-CA-016:** An unrecognised quadrant is rejected rather than normalised to
  untagged, so a caller's mistake cannot read as a deliberate clear.

## Acceptance

| ID | Method | Note |
| --- | --- | --- |
| REQ-CA-001, 003, 004 | Headless assertions | Adapter and rules module in isolation |
| REQ-CA-002 | Manual | Needs a real room to judge |
| REQ-CA-005–009 | Headless assertions | Record and diagnostics in isolation, plus the surface mounted in the live map. The *judgements* still need a room; that they are demanded, gated, and stored correctly does not |
| REQ-CA-010, 011 | Manual | Live session |
| REQ-CA-012 | Headless assertions | Outcome node renders in `Outcomes`, not `Opportunities` |
| REQ-CA-013 | Headless assertions | Router proposes into `open_questions` / `next_steps` / `owners`, all arriving `suggested`; a second pass proposes nothing |
| REQ-CA-014 | Harness | Existing smoke and multi-turn specs pass unchanged |
| REQ-CA-015, 016 | Headless assertions | Adapter in isolation |

Phase 2 landed 2026-09-06 with 126 headless assertions across three suites: the
diagnostics, record, and router in isolation (71); the audit surface mounted standalone
(55); and the audit mounted inside a live Thinking Map, covering reveal, persistence
round-trip, routing idempotence, and the `Outcomes` column (37, in the third suite).

What is deliberately **not** asserted: whether a room's classification of an absence is
*right*. Nothing here infers a classification from a document, so there is nothing to
assert. That is the instrument's premise, not a gap in its tests.

**Follow-up, same day, from first use of the surface.** Two defects survived those
assertions and were caught by eye instead. Both now have permanent coverage in Stage 8, and
both are worth recording because the assertions that missed them looked adequate:

1. **The audit certified an unexamined map.** With nothing oriented, the rules module
   correctly reports no empty or weak quadrants — it withholds the reading below
   `MIN_TAGGED_FOR_READING` — so the completion gate found nothing outstanding and printed
   "Audit complete". The gate now also takes `has_reading`, and an unreadable map is itself an
   outstanding step. The isolation assertions missed this because they fed the gate a thin
   quadrant list directly, never the empty list a real unoriented map produces. See ADR 0020's
   second amendment for the generalisable form: an empty derived result means "no findings"
   only when the reading was possible.
2. **The Outcomes column wrapped onto a second row**, and an audit row squeezed its label to
   one character wide. Details in ADR 0020. Note that REQ-CA-012's assertion was passing
   throughout: it checked which column a node *renders into*, which was correct, while the
   column sat on the wrong row because the responsive layout overrode the scene's column
   count at runtime. A correct assertion about the wrong property.

Stage 8 now also asserts that no control in the audit panel demands more width than a single
map column, since the panel's narrowest home is a column and new rows will keep arriving.

The Workshop Catalyst harness cannot exercise a stage that must be selected
before the session starts, so the audit *ritual as a room would run it* stays manual —
consistent with the known harness limitations. What the harness holds is the regression
guarantee in REQ-CA-014 and the derived counts. What phase 2 showed is that the
mechanism does not need the harness: mounting the map controller with a fake hub gives
the audit surface, the reveal gate, the persistence round-trip, and the routing path
under ordinary headless assertions. Reserve manual testing for judgement, not wiring.

One harness note from phase 2. The multi-turn spec's three 120s waits exceeded the
harness's own 250s process budget, so it reported `Godot process timed out` regardless
of product health — the per-turn waits had been raised without the process budget.
Specs now carry their own `harness_timeout_sec`, and `test_harness.py` also derives a
floor from the waits a spec asks for, so the two cannot drift apart again.

Phase 1 adds closure fields to `_workshop_snapshot()` in `dev_harness_hooks.gd`
so `snapshot_field` assertions can read coverage without a story-log assertion.
Workshop specs must continue to avoid `min_story_log`.

Those fields are `thinking_map.oriented_count`, `unoriented_count`,
`orientation_counts`, `contested_count`, `view_position_count`, and
`claims_with_views`. They are raw document totals with no status filter, unlike
the product's own reading, which drops rejected claims: the hook counts
structurally and leaves the thresholds where they belong. (It *could* now import
`ClosureOrientation`, which lives in `synesyn_core` rather than the host — reading the
stored shape directly is simply preferred, since that is what lets the harness verify
the shape rather than agree with whatever the product currently writes.)
`orientation_counts` holds only the quadrants actually present, so assert on
`oriented_count` rather than on a quadrant key that may be absent. `contested_count`
reports the asserted flag *or* divergent views, matching the product; the finer
asserted/derived split is a product-side reading and is not exposed to the harness.

REQ-CA-004b needs one change to phase 1's data path, in phase 2: `set_node_orientation()`
in `thinking_map_adapter.gd` currently records `oriented_by` and `oriented_at` only,
which cannot tell an unaided tag from an accepted suggestion. It needs the suggested
quadrant passed in alongside the chosen one, so provenance can hold both and the
agreement rate becomes measurable. The stored `annotations.orientation` shape does not
change, so no map-version bump and no Hub change.

REQ-CA-014 is carried by the smoke spec asserting
`thinking_map.oriented_count == 0`: the audit is opt-in, so a session that never
opens it must record no tags and behave exactly as it did before.

The controller cannot be instantiated in a `--script` run — it reads the `Network`
and `ThemeManager` autoloads bare, which do not resolve outside the game (ADR 0017
rule 6). So the adapter, vocabulary, and rules modules are covered by headless
assertions, the scene structure by loading the `.tscn` files, and the controller's
mounting by the smoke harness. Live toggling and tagging need manual testing, as
with the rest of Workshop Catalyst's in-session behaviour.

## Implementation notes

| Piece | Location | Phase |
| --- | --- | --- |
| Quadrant vocabulary, prompts, tetrahedral edges | `addons/synesyn_core/scripts/closure_orientation.gd` (shared with SynAxes) | 1 |
| `orientation` annotation, set/clear command, suggestion provenance | `thinking_map_adapter.gd` | 1 |
| Coverage / concentration rules | new `workshop_closure_audit_rules.gd` | 1 |
| Status line extension, per-card binding, audit gate | `workshop_thinking_map_controller.gd` | 1 |
| Orientation picker and suggestion display | new `workshop_orientation_presenter.gd` | 1 |
| Per-card orientation control | `workshop_thinking_map_card.tscn` | 1 |
| Audit toggle, coverage label, suggest button | `workshop_thinking_map.tscn` | 1 |
| Snapshot fields | `dev_harness_hooks.gd` | 1 |
| Assisted orientation prompt, parsing, decline handling | new `workshop_orientation_suggester.gd` | 2 |
| Contestation register reading (positions, dimensions, derived contested) | `addons/synesyn_core/scripts/closure_orientation.gd` | 2 |
| Contestation register editing and validation | new `workshop_contestation_register.gd` | 2 |
| Register entry points (thin delegation) | `thinking_map_adapter.gd` | 2 |
| Reading text for the coverage tooltip | `workshop_closure_audit_rules.gd` | 2 |
| Card spread badge | `workshop_orientation_presenter.gd` + card `.tscn` | 2 |
| Divergence-ordered review panel, reveal row | new `workshop_views_review_presenter.gd` + `workshop_thinking_map.tscn` | 2 |
| Reveal state (session state, not document) | `thinking_map_adapter.gd` | 2 |
| Suggestion request plumbing (owns the conversation manager) | `workshop_catalyst_controller.gd` | 2 |
| Absence / triage / concentration vocabularies, triage matrix, debt gate | new `workshop_closure_audit_diagnostics.gd` | 2 |
| Audit judgements, completion gate, reopening actions, transition | new `workshop_closure_audit_record.gd` | 2 |
| Session Record routing (propose only) | new `workshop_closure_audit_router.gd` | 2 |
| Audit surface | new `workshop_closure_audit_panel.tscn` + `workshop_closure_audit_controller.gd` | 2 |
| Mount point, visibility, routing glue | new `workshop_closure_audit_host.gd` | 2 |
| `Outcomes` column | `workshop_thinking_map.tscn` + controller | 2 |
| Stage guidance defaults | `WorkshopScenarioContract` | 2 |
| Autoload resolution (testability, see below) | new `workshop_autoloads.gd` | 2 |
| Audit drafting prompt, parsing, validation (REQ-CA-021) | new `workshop_closure_audit_suggester.gd` | 2 |
| Draft strips, accept / dismiss widgets, shared label and band-picker factories | new `workshop_closure_audit_suggestion_presenter.gd` | 2 |
| Both on-demand model passes, kept out of the 900-line session controller | new `workshop_assist_passes.gd` | 2 |
| Claims-with-orientation collector for the drafting pass | `workshop_closure_audit_rules.gd` | 2 |
| Audit split sizing, so the panel collapses to nothing and hands height back; claim-column sizing and styling | `workshop_map_layout_utils.gd` | 2 |
| Custom drawer's Claim columns / Closure audit panel switches, kept out of both controllers | new `workshop_map_panel_toggles.gd` | 2 |
| Sheet artifact + validator | `workshop_artifacts.py`, new coordinator | 3 |
| Markdown export | `workshop_catalyst_export_utils.gd` | 3 |

The audit is **opt-in in phases 1 and 2**: it ships as an authored stage with a
documented `[STAGE_GUIDANCE]` template, and `DEFAULT_AGENDA` keeps its six stages.
Promoting it to a seventh default stage would change what ADR 0012 asserts and
what `test_workshop_scenario_and_map_corrections.gd` verifies, so that decision
waits for manual acceptance evidence in phase 3.

New logic goes in theme-scoped modules rather than growing shared controllers. As of
2026-09-06 two files sit in the soft warning band with no hard violation:
`thinking_map_adapter.gd` at 1006 and `workshop_thinking_map_controller.gd` at 1076. Both
are why the register's rules went into their own module, why the reading text moved into
`workshop_closure_audit_rules.gd`, and why the audit's five phase-2 modules are separate
files with the map controller keeping only a mount call, a findings forward, and a state
relay. The pure-function pieces belong outside the adapter and controller anyway, and
putting them there is also what keeps those two off the hard limit. Run the line-limit
ratchet after each phase and assume neither file has room.

### Phase 2 also fixed the tests that were reporting green while verifying nothing

Three Workshop Catalyst suites were passing vacuously. `godot --headless --script` does
not register project autoloads, so any file naming a bare `Network`, `StoryState`, or
`ThemeManager` fails to **compile** under it. The preloaded script then came back empty,
`new()` returned null, the test's `_run` abandoned before reaching an assertion, and
`_finish` printed "all passed" over an empty failure list. `test_workshop_catalyst_stage11b.gd`
had a comment describing this as intermittent flakiness; it was neither intermittent nor
harmless.

Resolving those autoloads through the tree in `workshop_autoloads.gd` (call time instead
of compile time — identical behaviour once they exist) made all three run, and each then
surfaced a real defect it had been hiding:

- **stage11b** — its specialist-candidate fixture used `kind`/`text`, which the ingest
  path rejects as `invalid_map_category`; production emits `category`/`proposition`.
- **stage7** — a genuine ratchet violation: `workshop_catalyst_controller.gd` stood at
  923 lines against the 900 the test asserts. Two pure helpers moved to
  `workshop_catalyst_controller_utils.gd`, one of which (`export_workshop_summary`)
  restores the symmetry with `export_decision_record_only`, which was already there.
- **stage11** — no defect of its own; it had been failing to load on a dependency.

All five workshop suites now pass on their own merits. Treat "all passed" with a preceding
`Compile Error` line as a failure, not a pass.

## Links

- ADR: [`../architectural-decisions/0020-thinking-map-closure-map-boundary.md`](../architectural-decisions/0020-thinking-map-closure-map-boundary.md)
- ADR: [`../architectural-decisions/0012-workshop-catalyst-facilitation-method.md`](../architectural-decisions/0012-workshop-catalyst-facilitation-method.md)
- ADR: [`../architectural-decisions/0015-synaxes-v2-closure-map-orientation.md`](../architectural-decisions/0015-synaxes-v2-closure-map-orientation.md)
- ADR: [`../architectural-decisions/0019-thinking-map-human-authorship.md`](../architectural-decisions/0019-thinking-map-human-authorship.md)
- Concepts: [`../concepts/closure-map.md`](../concepts/closure-map.md)
- PRD: [`PRD-SCENSYN-WORKSHOP-CATALYST.md`](PRD-SCENSYN-WORKSHOP-CATALYST.md)
- PRD: [`PRD-SYNAXES-CLOSURE-MAP-ORIENTATION.md`](PRD-SYNAXES-CLOSURE-MAP-ORIENTATION.md)
- Manual: [`../user-guide/workshop-catalyst-facilitator-manual.md`](../user-guide/workshop-catalyst-facilitator-manual.md)
