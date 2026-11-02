# 0020 — Thinking Map and Closure Map boundary: the audit is a stage, not an ontology

- **Status:** Accepted
- **Date:** 2026-09-05
- **Area:** scensyn / conceptual instrument
- **Relates to:** ADR 0008 (product-owned adapters, no shared ontology), ADR 0009
  (Workshop Catalyst session model), ADR 0012 (four lenses, six cross-checks),
  ADR 0015 (Closure Map sited in SynAxes), ADR 0016 (admissibility kept orthogonal
  to A–D), ADR 0019 (Thinking Map human authorship),
  [Closure Map](../concepts/closure-map.md),
  [PRD-WORKSHOP-CATALYST-CLOSURE-AUDIT](../product-requirements/PRD-WORKSHOP-CATALYST-CLOSURE-AUDIT.md)

> Amendment note (2026-09-19, ADR 0026): where this ADR says the card's
> `ClosureButton` emits a `ui.closure` artifact, session captures are now written
> as `ui.workshop_closure`. `ui.closure` denotes a SynAxes slice only. The
> reasoning below is unaffected — the audit remains a stage rather than an
> ontology, and A–D tagging remains sited in SynAxes — but the two kinds of
> closure record are no longer stored under one artifact type.

## Context

The Workshop Catalyst Thinking Map sorts claims into Causes, Effects, and
Opportunities. The question arose whether that surface is really a Closure Map
interface, and whether it should adopt Closure Mapping as established in
`Closure_Map_Improved_Exposition.docx` and `Closure_Mapping_Operational_Manual.docx`.

Reading the triad against the Closure Map's two axes exposed a structural gap.
Cause covers **A Distal Past**; Effect and Opportunity cover **B Distal Future**.
Nothing covers **C Deep Past** (assumption, habit, incentive, incorporated
pattern) or **D Deep Future** (latent capability, tendency, formation already
under way). The map has the horizontal axis and no depth axis, which is exactly
the pathology the Operational Manual singles out: "both distal quadrants rich,
both deep quadrants thin … not understood in its incorporated dimension."

The gap is not only cosmetic. ADR 0012's four lenses do surface Deep Past
material — staff fear, tacit incentives, institutional capacity — but specialist
extraction only admits `cause|effect|opportunity` across the command seam, so
"management assumes efficiency is the primary value" must be filed as a *cause*
and becomes indistinguishable from "the 2019 regulation requires X." The manual
insists that distinction is the whole point.

Second gap: the three symbolic checks (contradictions, causal chains, evidence
gaps) all read what is **present**. Closure Mapping's two primary diagnostics
read **shape** — the empty quadrant and the concentrated quadrant — and its
apparatus (five meanings of emptiness, consequence × confidence triage, closure
debt) is machinery for reasoning about absence. Workshop Catalyst can report a
contradiction but cannot report "you have not examined what you already
incorporated." That risk is acute here specifically because AI specialists will
readily fill three columns with plausible distal material and leave the room
feeling thorough.

The naming is also a tell. The manual lists SWOT's "Opportunities and threats" as
the row Closure Mapping replaces, so a column named Opportunities signals a
strategic inventory rather than a closure audit — and there is no threat/risk
column, so the triad is not even a complete SWOT.

The sharpest statement of the problem: propose → review → preview → commit
already **is** closure in Lawson's sense — ADR 0012 says so, and the card's
`ClosureButton` emits a `ui.closure` artifact. Workshop Catalyst performs closure
without auditing its own closure. That, not the column names, is the deficiency.

## Options considered

1. **Replace the columns with quadrants A–D.** Rejected. It breaks the hub
   schema, the specialist extraction contract, ADR 0012's method, the facilitator
   manual, the harness specs, and every committed artifact. It also destroys the
   causal reasoning layer: `causes` edges and causal-chain detection depend on
   cause/effect semantics, which quadrants do not carry. And it conflates two
   instruments of different scope into one.
2. **Retag every node with an orientation facet, continuously.** Rejected as the
   primary mechanism. Four extra tags on every card during live facilitation is
   operator load on a surface already dense, and it converts a bounded ritual
   into ambient bookkeeping.
3. **Change nothing; the boundary is already correct.** Rejected. The boundary
   *is* correct, but the absence of any premature-closure check is a real
   deficiency against the product's own claim to produce well-formed decisions.
4. **Adopt only the absence diagnostics over the existing three columns.**
   Attractive and cheap, and retained — but as the first phase of option 5 rather
   than the whole answer, because concentration over three distal columns cannot
   detect a missing deep half it has no vocabulary for.
5. **A bounded Closure Audit stage that reads the Thinking Map.** Chosen.

## Decision

1. **The Thinking Map keeps Causes / Effects / Opportunities.** It is a causal
   reasoning surface and remains one. It is not converted to a Closure Map, and
   `ui.workshop_thinking_map` node kinds and relations are unchanged.

2. **The Closure Map stays sited in SynAxes.** ADR 0015 is untouched: the Closure
   Map remains the orientation and coverage instrument over committed
   `ui.closure` artifacts, operating at corpus scale. Workshop Catalyst imports
   the Closure *Audit* — the facilitation method of the Operational Manual — not
   the orientation instrument. Two surfaces, one shared vocabulary.

3. **The audit is a bounded stage, not a continuous overlay.** The manual
   specifies a 20–30 minute exercise with silent individual entry and a one-page
   output, and warns that longer sessions drift into general discussion. This
   maps onto the existing `[WORKSHOP_AGENDA]` stage plus `[STAGE_GUIDANCE]`
   contract rather than onto a new always-on panel.

4. **Orientation is an optional per-node facet, requested only inside the audit
   stage.** It reuses the SynAxes quadrant vocabulary verbatim (`A`/`distal_past`
   … `D`/`deep_future`, with `map_version`) so the two surfaces stay comparable.
   Absent means untagged; untagged never blocks anything. This mirrors ADR 0016's
   established pattern of keeping A–D an orthogonal tag layer rather than a
   replacement ontology.

5. **Absence is a first-class finding.** Every weak or empty quadrant must be
   classified as not applicable, deliberately excluded, unknown, suppressed, or
   not-yet-formed, and a quadrant is never filled for symmetry. Closure debt is
   recorded only when the manual's four conditions hold: material to the
   decision, unjustified, outcome-changing, and unsafeguarded.

6. **Audit findings are derived, never mutations.** Coverage, concentration, and
   debt readings follow the existing symbolic-rules contract: read-only over the
   document, deterministic, explainable, never written back as nodes or edges.

7. **The output is the Closure-to-Action Sheet, expressed through existing
   Session Record categories wherever they already fit.** Reopening questions are
   `open_questions` — which ADR 0012 already defines as deliberately retained
   openness. Reopening actions are `next_steps` plus `owners`. The revised
   decision is `decisions`. Only the genuinely new elements (quadrant weight and
   status, closure debt, required tetrahedral transition, per-action falsifier and
   review trigger) need new storage.

8. **Orientation is proposed by the system and closed by a human.** *(Revised
   2026-09-06; see the amendment note below.)* No quadrant is ever written without a
   person acting, and no orientation arrives as a side effect of ordinary
   facilitation: the specialist pass still emits only
   `cause|effect|opportunity`. But within an audit the facilitator may ask for a
   suggested quadrant per claim and accept or change it, exactly as they accept or
   edit an AI-proposed claim under ADR 0019. A suggestion is not a tag; only the
   human action writes it, and coverage counts only what was written.

## Consequences

- Positive: the product gains a premature-closure check it did not have, without
  disturbing the causal reasoning layer, the hub schema, or the SynAxes boundary.
  The two instruments become comparable through shared quadrant vocabulary while
  keeping distinct scope: within-session claims versus corpus-scale closures.
- Positive: the deep half becomes representable, so Deep Past material surfaced
  by the Stakeholder and Risk lenses stops collapsing into "cause" at the
  extraction seam.
- Positive: three existing but dormant capabilities get activated rather than
  rebuilt — the `decision`/`risk`/`owner`/`next_step` node kinds already in the
  adapter and hub schema, the `get_routable_outcome` path into Session Record
  categories, and the `ClosureButton` that today only appears for outcome kinds
  the UI never creates.
- Positive: ADR 0019's `authorship_kind` and `source_class` already implement the
  manual's "treat authorship as data — does the map reflect reality or the room?"
  The provenance layer was closer to Closure Mapping than the category layer was.
- Trade-off: this narrows ADR 0012's out-of-scope statement, which excluded
  "coverage auditing over committed artifacts" and any "tetrahedral
  visualisation." ADR 0012 remains accepted; its claim was that the *method* must
  not intrude into the Talk → Map → Review interface, and a distinct bounded
  stage does not violate that. The tetrahedral edge is admitted as a one-line
  textual transition, not a diagram.
- Trade-off: a quadrant facet on nodes means a claim can be well-formed on one
  axis and untagged on the other, so coverage readings will be partial in any
  session where the facilitator skips the audit. Accepted: a partial reading is
  more honest than a mandatory tag nobody thinks about.
- Trade-off: two vocabularies now coexist on one surface (category and
  orientation). The mitigation is that they are orthogonal by construction —
  category answers "what kind of claim," orientation answers "which mode of
  situatedness" — and only one is ever solicited at a time.
## Amendment, 2026-09-06 — assisted orientation

Decision 8 originally barred model-side quadrant inference outright. That was wrong
on two counts and is revised above.

It was inconsistent with the project's own principle. ADR 0019 and the Human Agency
UX contract establish that the system proposes and the human closes, and orientation
was given an exception it did not earn. The exception rested on a distinction between
proposing *content* and producing a *measurement* — that a suggested claim can be
judged on its merits whereas a suggested tag mostly gets confirmed by inertia. That
concern is real but it is a matter of degree, not a reason to invert the house
pattern, and it is addressed by REQ-CA-004b's provenance instead.

It also rested on an assumption asserted as fact: that a classifier would populate
all four quadrants and so destroy the empty-quadrant reading. That only holds if the
model is forced to choose. Making "none of these applies" a first-class answer
removes the pressure, and REQ-CA-004a now requires it.

The operational argument for assistance is stronger than the argument against.
Orienting from a blank page against four abstract quadrants is the real cost of this
instrument; unassisted, a room will either stall or tag carelessly, and a careless
tag is worse than an absent one because it silently corrupts the reading the audit
exists to produce. The suggestion is deliberately a single concrete proposal the
facilitator accepts or changes, not a ranked shortlist with reasons per option:
adjudicating an argument for each candidate on every card is more load than judging
one proposal.

What survives unchanged: nothing writes a quadrant except a human action; suggestion
is on request only, never ambient; and specialist extraction still cannot emit
orientation, so an unaudited session records none.

## Amendment, 2026-09-06 — the facilitator closes orientation; disagreement is recorded

The Operational Manual's sequence includes **silent individual entry**: each person
privately answers the four quadrant prompts before the group moves to diagnostics. That
step has no home in the current model, where the Thinking Map is one shared surface,
participants propose, and the facilitator commits (ADR 0019). Two shapes were weighed:
facilitator-only orientation with the room's input arriving through discussion, or
private per-participant entry resolved by a vote.

**Decision: the facilitator orients, alone.** Participants influence orientation by
talking, and the facilitator records the result.

The reason is not convenience. In the manual, silent entry sits at the *generation*
step — its purpose is to take independent samples before the first speaker anchors
everyone. In our siting, the claims already exist: they came out of the conversation and
specialist extraction across the whole session, from many voices, over an hour or more.
The Thinking Map *is* the collective sample, and the anti-anchoring protection was
banked upstream rather than compressed into a five-minute writing round. Our audit
begins at orientation and diagnosis, which is the step *after* the one silent entry
protects.

Three supporting reasons. The manual budgets 20–30 minutes and warns that overrunning
drifts into general discussion; a private-then-vote round across 15–30 claims is an
hour. Voting on a *reading* is also unlike voting on a commitment: a 51% orientation is
not truer than a 49% one, and majority-tagging manufactures precisely the careless tags
that REQ-CA-004a's "none of these applies" exists to prevent, with democratic cover. And
the existing `VoteTally` could not have served anyway — it is binary yes/no with a
majority threshold, built for closure formation, whereas orientation is a five-way
categorical choice.

**What this loses, and the mitigation.** Not anchoring, but *divergence as evidence*. A
room split over whether something is inherited from outside or already embedded in how
it works is reporting that it does not share a reading of its own situation — a finding
about the group, and exactly what a closure audit should catch. Facilitator-only closing
flattens it, and so would a vote, which yields a winner and discards the distribution.

So a claim's orientation may be marked **contested**, recording that the room did not
converge. It is deliberately not a vote: one checkbox, set by the facilitator, orthogonal
to the tag.

**Two distinct contestations, one register shape.** REQ-CA-010 addresses contested
material *within* a quadrant: people who agree where a claim sits but disagree whether it
holds. This flag addresses contested *placement*: people who disagree which quadrant a
claim belongs to at all. They are different disagreements and neither subsumes the other —
a room can be unanimous that a claim is true and split on whether it is inherited or
embedded, or unanimous on placement and split on the evidence.

But the register REQ-CA-010 specifies — who holds each view, the supporting evidence,
which decision would differ, what test discriminates — fits both without modification, and
the "never averaged into a consensus statement" rule applies equally to both. So the
register should carry a dimension distinguishing *placement* from *substance* rather than
being duplicated, and this boolean is the degenerate placement case: it records *that* a
room split, where the register records *what the split is* and what would settle it.
Shipping the flag first is deliberate, being what the facilitator-closes model needs in
order not to lose the signal, but REQ-CA-010 remains unmet by it. It applies with or without a quadrant — a room that
argued and settled on C and a room that could not agree at all are both contested — and
it never affects review or commit. It is stored as a *sibling* of `orientation` rather
than a field inside it, because `orientation` is the persisted `ui.closure` schema v2
shape and contestedness is a fact about the deliberation, not a coordinate on the map;
marking a claim contested must not be able to change how any stored closure reads. The
count is reported ungated, unlike the dominant/weak/empty readings: those are
statistical and need a sample, whereas one contested claim is already true.

**Residual risk, accepted.** The facilitator becomes a single interpretive bottleneck,
and in a room with a dominant facilitator the tags will reflect one person's reading
wearing the group's clothes. The contested marker mitigates it, the orientation
provenance makes the pattern auditable after the fact, and the audit's output still
lands in the Session Record where the room can see it — but it is not eliminated.

**A canonical tag is required, and per-participant views are required too.** These are
not alternatives, and neither is a matter of preference. The tag is needed because the
diagnostics read the map as a *single distribution*: concentration classification asks
whether a pattern is legitimate focus, expertise bias, fixation, suppression, or
premature closure, which is a statement about one map. Five private maps yield five
readings and no basis for choosing between them — and the pathology the instrument exists
to catch is a property of the group's *shared* reading, which per-participant views never
form on their own. The tag also feeds the Closure-to-Action Sheet and routes reopening
actions with owners and dates into the Session Record, all of which need one input.

Per-participant views are then required by REQ-CA-010 and REQ-CA-011 rather than by this
amendment: the contestation register names who holds each view, and the single-source
diagnostic needs entries labelled by source. Views are therefore **attributed, not
anonymised** — the register's job is to make a disagreement actionable, and "what test
discriminates between these readings?" is unanswerable without knowing whose readings
they are and what evidence each rests on.

The two layers compose: views are formative input that let the room see where it is
converging, the facilitator's tag is the canonical reading the diagnostics consume, and
a contested claim carries its register alongside the tag rather than being flattened into
it. That is what "never averaged into a consensus statement" requires — tagging a
contested claim records where it sits for the map's reading without erasing the split.

**A view and a placement position are the same fact**, so there is one structure and not
two: a named holder, a quadrant, and the evidence behind it. Participant views are
therefore stored as positions on the register's `placement` dimension, which makes
contestation *derived* — two distinct views make a claim contested with nobody judging
that it is — and hands REQ-CA-011 its source labelling for free. The asserted flag stays
for the case where the room split out loud and no views were entered, and the two are
counted apart, because a facilitator's mark is a judgement about a conversation while
divergent recorded views are the disagreement itself.

**Views are closed until revealed, and the reveal is one-way.** This is where silent
individual entry actually belongs in our siting — at orientation rather than generation —
and it holds for the facilitator too, not only for participants: a facilitator who can see
that three people said C is no longer tagging independently. Before reveal the surfaces
report participation and never content. Reveal cannot be undone, because re-hiding views
the room has already discussed would record a retraction that did not happen. The flag is
session state on the map rather than an annotation on any claim, since reveal is a
facilitation moment and not a property of a claim; putting it in the document would push it
into the committed artifact and every export that reads one.

Reading the register lives in `ClosureOrientation` in `synesyn_core`; editing it lives in
`workshop_contestation_register.gd` in ScenSyn. A stored register must be legible to
anything that reads a Closure Map, SynAxes included, without that reader inheriting the
workshop's rules about who may record a position and when a view counts as reviewed. The
split also avoids a preload cycle: the contested predicate has to consult positions, so
keeping both in the one core module means the vocabulary never has to depend on the
workshop's editing module.

## Amendment, 2026-09-06 — the vocabulary lives in `synesyn_core`

Decision 2 said "two surfaces, one shared vocabulary" and decision 4 said the audit
"reuses the SynAxes quadrant vocabulary verbatim". Both were satisfied in the first
slice by a module under `ScenSyn/session_types/workshop_catalyst/` whose docstring
asked the two surfaces to stay in lockstep by hand. That was not a shared vocabulary;
it was a second transcription with a comment attached, and it failed on its first
test.

When the plain glosses were revised on 2026-09-06, the revision reached the ScenSyn
module and none of the other four transcriptions of the same table — the constants in
`synaxes_closure_controller.gd` and three places in `synaxes_main.tscn`. For a period
the same vertex was "Embedded Culture — norms, incentives, power relations" in the
Workshop and "Deep Past (sediment / active memory)" in SynAxes. Two vocabularies on
one instrument is precisely what decision 2 exists to prevent.

The placement was also the *cause*, not merely the occasion: an addon cannot depend on
host ScenSyn code (ADR 0017), so while the definition sat under ScenSyn, SynAxes could
not have read it even in principle. Duplication was structurally forced.

The vocabulary therefore moves to `addons/synesyn_core/scripts/closure_orientation.gd`
as `ClosureOrientation`, and both surfaces read it. `synesyn_core` is the designated
shared library and SynAxes already depends on it.

The boundary between what is shared and what is not:

- **Shared (in core):** what a quadrant *is* — ids, canonical terms, plain glosses,
  temporal roles, axis hints, characterisations, the four prompts, the six tetrahedral
  edges, `MAP_VERSION`, the picker-row and help-text renderings, and the
  read/write helpers for the stored `orientation` shape. That shape belongs beside
  `graph_workspace_document.gd`, which owns the document it is written into.
- **Not shared (with each consumer):** what a surface *does* with a quadrant — the
  Workshop's audit rules, suggestion prompt and card presentation; SynAxes' corpus
  coverage counting and commit path.

Two consequences worth stating. Nothing about the Closure Map may be authored in a
`.tscn`: scene text cannot preload, so SynAxes' baked picker rows were removed and are
populated at mount, and its remaining tooltips point at the code-driven help rather
than restating it. And because a revision to the upstream Terminology table now has
exactly one landing site, the class of drift described above is no longer possible
rather than merely discouraged.

- Follow-ups: `PRD-WORKSHOP-CATALYST-CLOSURE-AUDIT` carries the phased scope.
  Nothing in phase 1 crosses the client↔hub seam; the sheet artifact in a later
  phase would add one constant and one branch to
  `validate_workshop_artifact()` in `app/substrate/workshop_artifacts.py`. Any
  exported sheet must resolve its path through `RuntimeConfig` under
  `Documents/Synesyn` per ADR 0014. The facilitator manual needs a Closure Audit
  section when next revised.

## Amendment, 2026-09-06 — the diagnostics classify nothing on the room's behalf

Phase 2 completed the audit ritual: the three diagnostics, the closure debt register, the
required transition, reopening actions, Session Record routing, the `Outcomes` column, and
the audit surface. One decision inside it is load-bearing enough to record.

**The audit computes geometry and refuses to interpret it.** `workshop_closure_audit_rules.gd`
derives which quadrants are empty, weak, dominant, or resting on a single voice.
`workshop_closure_audit_diagnostics.gd` holds the vocabularies the room applies to that
geometry — the five kinds of absence, the five readings of a concentration, the triage
matrix, the four debt conditions — and contains no function that takes a document and
returns a classification.

This was tempting to do otherwise. The model could plausibly guess that a quadrant is empty
because the topic is irrelevant, and offering that guess would make the ritual faster. But
the manual's central claim is that geometry must not be diagnosed before how the geometry
was produced is understood, and the difference between "unknown", "suppressed", and "not yet
formed" is not in the map — it is in the room. A tool that guessed would commit exactly the
error the instrument exists to catch, and it would do so persuasively. So the stage guidance
tells the AI to report the shape and stop, and the completion gate refuses to close an audit
over a thin quadrant nobody has explained.

Two smaller decisions that follow from the same reasoning:

- **Triage is unavailable until the absence is classified.** How much a gap costs cannot be
  judged before the room has said what kind of gap it is, so the record refuses the verdict
  and the surface does not draw the control.
- **Reclassifying an absence discards its verdict.** "Monitor" was decided about a quadrant
  the room believed was merely unknown; it does not carry over to one it now believes is
  being suppressed.

**Debt gates rather than scores.** All four conditions must hold, and a refusal reports which
failed. Most absences are not debt, and a register that accumulated every gap would be
ignored within one session — so "this is not debt" is itself a finding the facilitator can
read back, not a silent rejection.

**Routing proposes; it never commits.** The audit's questions and actions enter the Session
Record through `propose`, arriving as `suggested` for facilitator review like any specialist
claim. Writing them into the reviewed record would give a derived reading more authority
than a human claim, inverting ADR 0019. Routing is idempotent through the audit's own
routed refs, so a proposal the facilitator *rejected* does not return on the next pass —
the room decided.

**The audit's state rides in the map's state**, not the workshop's, because it is only
meaningful against this map: restoring an audit beside a different document would attach
classifications to quadrants whose contents had changed underneath them.

Phase 2 also removed a testability hazard that had been hiding real defects. Bare autoload
identifiers (`Network`, `StoryState`, `ThemeManager`) make a file fail to compile under
`godot --headless --script`, which caused three Workshop Catalyst suites to print "all
passed" while verifying nothing. Resolving them at call time through `workshop_autoloads.gd`
made all three run; each then surfaced a genuine defect. Details in the PRD's implementation
notes. **Prefer tree-resolved autoloads over bare identifiers in any file a headless test
loads.**

## Amendment, 2026-09-06 — the completion gate needs the reading, not just the gaps

First use of the audit surface produced a screenshot of it announcing "Audit complete: every
thin quadrant is accounted for" over a map on which nothing had been oriented at all. The
gate was reading `empty_quadrants` and `weak_quadrants` from the rules module, and that module
correctly withholds both until `MIN_TAGGED_FOR_READING` claims are oriented, because below
that threshold there is no concentration to measure against. So an unexamined map yielded no
thin quadrants, no thin quadrants meant nothing to classify, and the audit closed.

**The gate now takes `has_reading` as well, and an unreadable map is itself an outstanding
step.** The lesson generalises past this one gate: *a derived reading's absence of findings
means "no findings" only when the reading was possible.* Any consumer of the rules module that
treats an empty result as a clean result will reproduce this bug, and it fails in the most
damaging direction — the instrument built to catch premature closure was itself certifying it,
in the tool's own confident voice. The absence-step body text now distinguishes the two cases
for the same reason: "no quadrant is empty or weak" and "too few claims are oriented to know"
are opposite findings, and one message for both is how they get confused.

**Layout note, from the same screenshots.** Two defects reached the eye that headless
assertions should have caught, and both are now asserted in Stage 8:

- The Thinking Map's responsive layout pinned `MapColumns.columns` to a literal `3`, so the
  Outcomes column added in Phase 2 wrapped onto a second row even though the scene declared
  four. The runtime value silently won over the scene, and the Stage 4 assertion said `== 3`,
  so it passed. Both now derive the count from the actual children, which is what the file's
  own "columns shrink rather than stack" contract always meant.
- Inside the audit panel, an `OptionButton` reports a minimum width set by its longest item
  regardless of `clip_text`. Three quadrant pickers carrying the full `get_option_text()`
  demanded 335px inside a map column, which squeezed the neighbouring label in its
  `HBoxContainer` down to a single character per line. Fixed with a shared
  `get_compact_option_text()` in `synesyn_core` rather than a locally shortened string, for
  the reason already recorded on `get_option_text()`: a narrow surface that invents its own
  abbreviation is how two pickers start naming the same quadrant differently.

Stage 8 now asserts that nothing in the audit panel demands more width than one map column,
which is a cheaper guard than reviewing each new row by eye.

## Amendment, 2026-09-06 (later) — vacuous truths read as findings

A pass over every Closure-Map string in the UI found the gate bug above was not one bug but
the third instance of one pattern. **A statement that is vacuously true of an empty set reads,
in a UI, as a substantive finding.** Three cases, all now fixed:

| Message | Vacuously true when | Read as |
| --- | --- | --- |
| "Every claim is already oriented, so there is nothing to suggest" | the map holds no claims | orientation is finished |
| "No single quadrant dominates, so there is no concentration to explain" | too few oriented to read | the map is balanced |
| "Audit complete: every empty or weak quadrant is accounted for" | too few oriented to read | the audit passed |

The first was the sharpest, because it rendered in the map footer *directly beside* "Closure:
no claims oriented yet" — two labels contradicting each other in one row, each correct by its
own logic. Both derived from an empty collection: one counted oriented claims, the other
counted claims awaiting orientation, and an empty map satisfies both.

The guard is a habit rather than a mechanism: **before writing "no X", ask whether the code can
distinguish "no X" from "X not yet knowable", and if it cannot, say the second.** The empty
case usually needs its own sentence, and that sentence is usually the more useful one, because
it can name what to do next.

Two consequences worth keeping:

- `describe_completion_gaps()` takes the oriented count and the threshold rather than a
  `has_reading` bool, so the gate can say "orient at least 4 claims so the coverage can be
  read (2 so far)". A facilitator told to "orient enough claims" cannot tell whether that means
  one more or twenty, and the numbers were already in the findings.
- The threshold falls back to `WorkshopClosureAuditRules.MIN_TAGGED_FOR_READING`, never to 0.
  A missing key defaulting to 0 makes the gate permissive exactly when its input is
  incomplete — the same shape as the original defect. Caught by Stage 8 within a minute of the
  change, which is the argument for the assertion existing.

Three further changes followed from the same review, decided with the user:

**Quadrants are named, not lettered, in compact readings.** The footer read `Closure: A:3 B:0
C:1 D:2 · dominant A`, which asks a facilitator mid-session to hold a four-way mapping in their
head before the line tells them anything. It now reads `Closure: Distal Past 3, Distal Future
0, Deep Past 1, Deep Future 2 · dominant Distal Past`. Canonical terms rather than the plain
glosses, because `closure_orientation.gd` records the upstream rule that a gloss never replaces
a canonical term where a quadrant is named *as a coordinate*, and a coverage reading is exactly
that position — the glosses stay in the tooltip, which already spelled out all four via
`get_canonical_with_gloss()`. Two new shared helpers, `get_canonical_term()` and
`join_canonical_terms()`, so the abbreviation is defined once. Worth noting SynAxes never had
this defect: its coverage summary already led with the canonical term, so the ScenSyn footer
was the surface that had drifted, and the fix closed a gap between them rather than opening
one.

**A step 0 for orientation.** The panel presented six numbered steps as a checklist while its
actual precondition — orienting claims — happened outside the panel entirely, through a footer
button and the claim cards. Steps 2 through 6 were inert until that was done, and nothing in
the panel said so or offered a way to start. Step 0 now reports progress against the threshold
("2 of 4 claims oriented") and names both affordances. It is numbered zero to mark it as a
precondition rather than part of the ritual, and it stays visible once satisfied: a step that
disappears leaves a facilitator wondering whether they missed it, and once satisfied it usefully
reports how many claims remain untagged, which is what the reading below is silent about.

**The concentration now gates completion** (REQ-CA-005a). Previously an audit could close with
step 3 untouched. A dominant quadrant is the finding most likely to be taken as
self-explanatory — the map "obviously" shows where the room's attention went — and it is
precisely the one the manual holds to be ambiguous between sensible focus and having stopped
looking. Gating it costs a room one deliberate answer and removes the cheapest way to skip the
reading least safe to skip.

**The map body is a split, not a stack.** Giving the audit host a vertical expand flag and a
320px minimum — an earlier attempt to stop its rows being cramped — took the whole pane. The
claim columns had a zero vertical minimum, so they flattened to a strip of headings, and because
`ThinkingMapPanel` and `ThinkingMapBox` both clip with no ancestor `ScrollContainer`, there was
nothing to scroll back to and no handle to drag. The map's own cards were simply gone while the
audit was open.

`MapColumns` and the footer-plus-audit region now sit in a `VSplitContainer` as `MapBodyPane`
and `MapLowerPane`, in that order so the visible arrangement is unchanged, and the columns carry
a `COLUMN_MIN_HEIGHT` floor applied in `workshop_map_layout_utils.gd` — in the layout utils
rather than the scene, because that function reapplies the minimum on every responsive pass and
would otherwise overwrite a scene-set value. That is the third time this file's runtime
assignments have silently overridden the scene; **treat `apply_responsive_map_columns()` as the
authority on column sizing and change it there.**

Two notes for anyone restructuring this scene again:

- A flat `VBoxContainer` cannot host two regions that both want height when the container
  clips and nothing scrolls. Whichever child has an expand flag and the larger minimum wins,
  and the loser collapses silently rather than erroring.
- `_MAP_COLUMN_PATHS` addressed the columns as `MapColumns/CausesColumn` from the panel root, so
  re-parenting the grid would have made `get_node_or_null()` return null and skip the theme
  restyle with no failure — invisible until someone noticed the columns had stopped following
  the theme. It now resolves under the `%MapColumns` unique name. **Prefer unique names over
  root-relative paths for anything a layout change might move.**

**Vocabulary.** "Thin quadrant" is gone from the interface. It appeared in a step heading and
in the gate line without ever being defined on screen, and it bought nothing over "empty or
weak", which is self-explanatory and already the term the tooltips used. The word survives in
code and in this ADR, where the reader has the context. The step-2 body now also names the
affordance — set a quadrant on the claim's card, or press Suggest — because "orient the claims
first" describes a state, not an action, and the Suggest button sits in a different region of
the screen from the instruction to use it.

## Amendment, 2026-09-07 — the audit may be drafted; it may not be decided

This supersedes the 2026-09-06 amendment above on one point, at the user's insistence, twice
stated. That amendment concluded that because the audit's classifications must not be *inferred*,
nothing may be *drafted*. Those are different claims, and the second does not follow.

The rest of this system already draws the line where it belongs. A specialist's claim arrives
with status `suggested` and waits for review (ADR 0019). An orientation suggestion is explicitly
not a tag, and an unactioned one counts as untagged everywhere including in coverage. Both are
model output that changes nothing until a human acts. The audit was the only surface built on the
stronger rule, and the stronger rule does not produce more human judgement — it produces a blank
six-step panel at the end of a session, which a facilitator skips. That is not a more careful
audit; it is no audit, arrived at by the same reasoning that says a careless tag is worse than an
absent one.

So `workshop_closure_audit_suggester.gd` drafts answers on demand (REQ-CA-021). What keeps it
honest is structural rather than editorial:

- Drafts are held in the audit controller, never in `WorkshopClosureAuditRecord`. The completion
  gate reads the record, so no quantity of drafts can complete an audit. Stage 8 asserts this
  directly.
- Each draft renders as a labelled "Suggested:" strip carrying the model's reason, with Accept
  and Dismiss. The label and the reason both matter: without the label an accepted draft becomes
  indistinguishable from a judgement the room reached, and without the reason there is nothing to
  review, so Accept degrades into a way to clear the panel.
- Drafts expire when the audit closes, as orientation suggestions do.
- A value that fails validation against the vocabularies is dropped, never coerced to the nearest
  match. A facilitator who accepts on trust has to be accepting what the strip says.

**Two things are still not drafted, and this is the part of the earlier reasoning that survives.**

*Closure debt* is a declaration that the room knowingly left something unresolved, and its four
conditions ask what the room did — whether the gap was named aloud, whether anyone objected. A
model reading the map has no access to any of that, so a plausible answer would forge a record of
the room's own conduct. The reply schema has no slot for it.

*An action's owner and date* are facts of the same kind: who agreed, and by when. The model drafts
what to do and what would settle it; a drafted action therefore offers **Fill in** rather than
Accept, populating the fields and leaving the commitment blank. This is also why the record's
refusal of an ownerless action is correct and was left alone — a commitment nobody made is the one
part of a reopening action that cannot be corrected later by re-reading it.

### Step-by-step verification found three defects, one of them severe

Walking each step against what its own text promised, rather than against the tests:

**Triage was unreachable.** The surface sends one band per selection; `triage_absence()` rejected
any call with an empty band; the rebuilt row read its state back from the record and found
nothing, so the picker snapped to its placeholder. Neither band could ever be the second one, so
no absence could ever reach a verdict — and the verdict is the whole output of REQ-CA-006. The
controller had a comment claiming it held the half-answer on the record, and code that mutated the
dictionary returned by `get_absence()`, which is a `duplicate(true)`. It wrote to a throwaway. The
record now stores an incomplete pair and withholds the verdict until both bands are present,
clearing it if one is removed. **A comment asserting a behaviour is not evidence of it; this one
had been read past several times.**

**Debt answers leaked between quadrants.** `_debt_conditions` was never cleared, and the
checkboxes were built once at mount. Answering the four questions about one quadrant and then
selecting another recorded the second as debt on evidence gathered about the first. Now cleared on
quadrant change and after a successful record.

**Field errors were written into the completion gate.** A reopening action missing an owner
reported it in `%AuditGateStatus` — the wrong end of the panel, and transient, since
`_sync_gate_status()` rewrites that label from the record on every refresh. Errors about fields
now appear beside the fields, in `%ActionStatus`.

Two smaller mismatches between promise and behaviour: step 5's text says the move runs from the
dominant quadrant into a neglected one, but both pickers opened on whatever they were showing and
nothing checked the direction. The reading now preselects the edge it points at and *notes* — does
not block — a choice that runs elsewhere, because the record is deliberately permissive about
order and choice, and a room may have a reason. And the pickers had no `item_selected` connection
at all, so the "that move means…" preview only updated when some other step changed.

### Layout: the audit closes, and the footer stops growing

The audit host's 180px minimum meant the divider could not be dragged shut. The minimum is gone;
`MapLowerPane` instead takes an expand flag only while the audit is open, via
`apply_audit_split()`. That makes both states correct without offset arithmetic — the pane is at
its minimum when the audit is shut, so the footer does not float mid-panel, and it takes a share
when open, so the toggle visibly does something. The divider then drags to nothing in one
direction and to the columns' floor in the other. The panel also carries its own **Hide** button,
which routes through `set_closure_audit_active(false)` rather than hiding its host, so the footer
toggle cannot be left reading "on" over a closed panel.

The footer row held three wrapping labels and three buttons. The labels wrapped to several lines
because they were competing for width, the row grew to the tallest of them, and the buttons — with
Godot's default vertical fill — stretched to match. The coverage reading moved to its own line
below the row, and the three controls are `SIZE_SHRINK_CENTER`. **A wrapping `Label` and a `Button`
on the same `HBoxContainer` will always trade height for width; give the buttons a shrink flag or
give the label its own row.**

### Tooltip register

The tooltips had drifted into essay voice — aphorisms, em-dash asides, and sentences written to be
correct about the instrument rather than useful to someone holding a workshop. Rewritten toward
what a facilitator can act on. Two rules came out of it worth keeping:

- **`synesyn_core`'s quadrant vocabulary was left alone.** `CHARACTER_BY_QUADRANT` and its
  neighbours are verbatim in substance from the Operational Manual and are shared with SynAxes;
  rewriting them for readability would fork the canonical text against its source. Only text this
  panel owns was changed.
- **One noun for one thing.** An early pass replaced "quadrant" with "position" in some headings
  and not others, which is worse than the domain term used consistently — the term is the manual's,
  it matches SynAxes, and the tooltips define it. Non-domain shorthand went instead: "concentration"
  became "the pile-up in the busiest quadrant", "required transition" became "the one move that
  would fix the worst gap", and "empty or weak" became "near-empty".

## Amendment, 2026-09-07: register again, and the map's two panels get their own switches

### "The room" was the tell, not the tooltips

A second reading found the register had only half moved. Two habits survived the first pass and
account for most of what still read as machine-written:

**"The room" as an actor.** "What the room has not looked at", "the room has not named", "a room
that names five moves has committed to none". It is a real term of art in facilitation, which is
why it slipped through, but in interface copy it puts a metonym where the reader expects either
themselves or the people in front of them. Replaced with "the group", "people", "everyone", or
plain second person, chosen per sentence rather than swapped mechanically. **Comments and prompt
text were left alone** — the model prompt in `workshop_closure_audit_suggester.gd` and the stage
goal in `workshop_scenario_contract.gd` are addressed to a model, not a facilitator, and the
in-file commentary is addressed to whoever reads the code next.

**The epigram.** A statement followed by a colon or an em dash and then a compressed restatement of
the same thing as an aphorism: "A suggestion is not a tag: this claim stays untagged until…", "That
is a complete answer, not a gap — but…", "coverage on the map, one voice underneath it", "the
disagreement is itself a finding — it says the group does not share a reading of its own situation
— so it is recorded". Each was doing rhetorical work rather than telling the reader anything, and
each cost a clause the reader had to parse twice. The rule that came out of it: **say the thing, or
say what to do about it, then stop.** Where a sentence earned its second half it was kept as a
second sentence rather than an aside, which is why several tooltips are now three short sentences
instead of one long one.

Two specific phrases the reviewer named — "what that would cost" and "the room has not named" —
were both symptoms of the same thing rather than isolated slips, which is why the fix was a sweep
of every user-facing string in the map and the audit rather than two edits.

`describe_action()` also had a malformed parenthetical ("(you supply the owner and the date.)")
that had survived since the suggestion presenter was written, which is the sort of thing a sweep
catches and a targeted fix does not.

### The map is two panels, so the Custom drawer needs two switches

The Custom drawer offered one switch for the whole Thinking Map. But since the body/lower split
went in, the map is two stacked regions with independent value: the claim columns (or the Graph
view that replaces them) above, and the Closure audit below. A facilitator working the audit wants
the claims small, not gone; one reading the columns on a projector wants the audit gone entirely.
One switch could only take both away.

`MapClaimsToggle` and `MapClosureToggle` now sit indented under `ThinkingMapToggle`, following the
`ConversationInputToggle` and `InsightsSubPanels` precedent already in that drawer.

Three decisions worth recording:

- **The pairing lives in its own module, `workshop_map_panel_toggles.gd`.** The switches belong to
  the shell scene and the nodes they act on belong to the map scene, so neither controller owns the
  relationship, and unique names do not cross a scene boundary. The module walks to the outermost
  ancestor and searches down, which is what lets both scenes stay ignorant of each other's paths.
  It also kept `workshop_workspace_controller.gd` — which was at 896 lines against a 900 soft
  limit — completely untouched.
- **The Closure switch calls `set_closure_audit_active()` rather than hiding the host.** Opening
  the audit reveals the per-card orientation pickers and closing it expires undecided suggestions.
  A switch that only flipped `visible` would leave the pickers on a closed audit. The map
  controller pushes state back through `sync_sub_toggles()` after any change, so the footer toggle,
  the panel's Hide button and the drawer switch cannot disagree.
- **Neither switch is persisted.** They sit in the same class as the Columns / Graph view buttons
  on the map toolbar. A session that reopened with its claims hidden would read as broken rather
  than remembered.

The handlers close over the map that was current when they were made, and a second session mounts a
fresh map under the same drawer, so `connect_sub_toggles()` clears existing connections before
adding its own. **A drawer that outlives the panel it drives has to be reconnected, not
connect-once-guarded** — the guard version silently left the switches driving a freed node.

`COLUMN_MIN_HEIGHT` came down from 132 to 96. The floor exists to stop the columns collapsing to a
strip of headings *by accident*, which is what the audit opening used to do to them. Hiding them on
purpose is now a separate control, so the floor only has to clear "heading and nothing else" and
the divider can travel considerably further than it could. `MapBodyPane`'s own minimum dropped from
140 to match.

`_apply_map_column_styles()` and the column name and fill constants moved out of
`workshop_thinking_map_controller.gd` into `workshop_map_layout_utils.gd` as
`apply_column_styles()`. Styling keyed to the same four nodes that file already sizes belongs with
the sizing, and the controller had no other reason to know the column names. Net effect on the
controller was 1134 lines down to 1109, so the new wiring cost nothing.
