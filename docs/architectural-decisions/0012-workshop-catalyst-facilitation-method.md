# 0012 — Workshop Catalyst facilitation method: four lenses, six cross-checks

- **Status:** Accepted
- **Date:** 2026-08-01
- **Area:** ScenSyn / Workshop Catalyst
- **Relates to:** ADR 0009 (four stable Specialist Functions, hidden synthesis)

## Context

Workshop Catalyst had facilitation *mechanics* — stages, timers, propose/commit
lineage, closure commands — but no named facilitation *method*. Two consequences
followed.

First, the method that did exist was invisible and unportable. Authored
Scenarios carry a four-part per-stage contract in `[STAGE_GUIDANCE]`
(facilitator goal, AI goal, required output before advancing, decision-forcing
question). Nothing named that structure, so Scenario authors had to infer it by
imitating `weight_of_decision_glp1_policy_triage`.

> Note (2026-09-18): `weight_of_decision_glp1_policy_triage` was authored for a
> specific client pilot and is no longer distributed with the project. It is
> named here because the record describes the situation at the time of the
> decision; the shipped Workshop Catalyst default is now
> `karlsruhe_library_future_design`.

Second, and worse, it did not travel. `create_custom()` supplied a default
agenda but never supplied `stage_guidance`, and
`_get_current_stage_guidance()` returns empty when that dictionary is empty. A
facilitator-authored local draft therefore ran an entire session on generic core
rules, with stage names and timers but no stage contract.

Separately, the project's own methodological framework — the Four Cosmic
Instruments (role play, hypothetical framing, iterative refinement, abductive
hypothesis generation) — was implemented in ReadyMade but absent from Workshop
Catalyst, and it was unclear whether importing it would help or would add a
second competing structure.

## Options considered

1. Leave the method implicit. Cheapest, but custom Scenarios keep degrading
   silently and authored guidance stays a house style rather than a contract.
2. Adopt the Four Cosmic Instruments as a parallel framework, with
   instrument selection exposed the way ReadyMade exposes it. Rejected: it adds
   operator load to a surface already dense for a live facilitator, and it
   pulls Workshop Catalyst toward exploratory Found Concepts play rather than
   closure.
3. Extend the instruments with a fifth adversarial instrument, because the four
   appeared to leave the Risk & Feasibility beat unrepresented. Rejected once
   the relational reading below showed the gap was an artifact of reading only
   vertices.
4. Name the method Workshop Catalyst already implies, using the instruments as
   the reasoning method *of each existing lens*, and add the pairwise checks
   between lenses. No new roles, no new UI, no new schema.

## Decision

Adopt option 4.

**Four vertices.** The four Specialist Functions from ADR 0009 remain the only
lenses. Each now carries the reasoning method its brief already implied:

| Lens | Method |
|---|---|
| Systems & Consequences | Abductive inference |
| Stakeholder & Communication | Perspective adoption |
| Risk & Feasibility | Iterative narrowing |
| Options & Innovation | Counterfactual framing |

This is descriptive, not additive. "Identify root causes, dependencies, and
second-order effects" was already an abductive instruction; naming it makes it
instructable and testable.

**Perspective adoption is backstage only.** Each lens adopts the domain
expertise the current subject matter requires and reasons from inside it. It
must never name, announce, or perform the adopted expertise, never attribute
output to it, and never introduce it as a participant. Adopted expertise does
not raise the evidential standing of a claim: anything a participant did not
state and retrieved evidence does not support remains `ai_inferred`. Workshop
Catalyst still has no simulated cast and still speaks one Session Record voice.

**Six edges.** Four lenses yield six pairings, held in `CROSS_CHECKS`. The
synthesis step must work the pairings the current stage's required output
depends on, and prefer a check no lens raised alone over restating agreement
between lenses. The pairings are not invented: authored stage guidance already
demands them. "Harm displacement" is Systems × Stakeholder. "Which restrictions
would predictably backfire" is Risk × Options. "One named risk with a
cost-bearer" is Stakeholder × Risk. "One structural constraint that limits what
regulation can realistically achieve" is Systems × Risk.

**No fifth instrument.** The apparent gaps — an adversarial move and a closure
move — exist as edges rather than vertices. Counterfactual framing combined
with abductive inference is a pre-mortem: what will have explained this failure
if it fails. Perspective adoption combined with iterative narrowing is expert
redrafting toward committable wording. Both are edges of the same four-lens
structure, so the fourfold is sufficient and needs no extension.

**All six edges rank equally.** Arranging four lenses on a 2×2 grid makes two
of the six pairings look like privileged "diagonals," but which two depends on
the axes chosen, so the distinction is an artifact of the projection. The
requirement is that all six are available and that the stage's required output
selects among them. Which pairings a real room actually neglects is an
empirical question for manual acceptance, not a structural claim.

**The default agenda gains a Stakeholder beat.** `DEFAULT_AGENDA` gave a stage
to Systems, Options, and Risk, bracketed by framing and synthesis, and none to
Stakeholder. `weight_of_decision_glp1_policy_triage` compensated by hand with a
dedicated equity/exclusion stress stage. "Weigh Who Is Affected" makes that
coverage structural rather than per-Scenario.

**Default stage contracts ship with the default agenda.**
`WorkshopScenarioContract.default_stage_guidance()` supplies the four-part
contract for all six default stages, interpolating the Scenario objective into
the framing stage. Authored guidance always wins; the default only fills an
empty `stage_guidance`.

**Closure vocabulary.** Committed decisions are closures; `open_questions` is
deliberately retained openness; propose → preview → commit is closure with
provenance; the do-nothing path is refusal of premature closure. This names
behavior Workshop Catalyst already had and gives the product a vocabulary
consistent with the wider research framework. It changes no runtime behavior.

## Consequences

- The specialist prompt gains method lines, domain-adoption rules, and the six
  cross-checks. No schema, contract, or route changes; the output envelope,
  role ids, and one-visible-sender guarantee are untouched.
- Custom Scenarios now run with a real stage contract for the whole session.
- `DEFAULT_AGENDA` has six stages rather than five. Scalable timing still
  scales the agenda to the chosen session duration.
- `test_workshop_scenario_and_map_corrections.gd` asserts six cross-checks, a
  method per lens, the never-surface and evidential guards, a complete
  four-part contract for every default stage, the Stakeholder beat, objective
  interpolation, and that authored guidance is not overwritten.
- Scenario authors have a documented stage-contract convention instead of a
  house style inferred from one template.
- Deliberately out of scope: facilitator-facing instrument controls, coverage
  auditing over committed artifacts, and any spatial or tetrahedral
  visualisation. The method disciplines Talk → Map → Review from behind; it
  does not appear in the interface.
- The claim that these prompt changes improve live facilitation quality is not
  yet evidenced. Focused regressions prove the structure is present and the
  guards hold; only manual acceptance on real workshop material can judge
  whether the cross-checks make the assistant more useful to a facilitator.
- Mid-tier local models often fail the full envelope (four roles + maps +
  synthesis) in one shot. Workshop Catalyst does **not** pin a specialist model.
  Instead it softens packaging while keeping coverage hard:
  1. Ollama output budget is 2048 tokens (was 768), reducing truncation.
  2. Missing `assistant_response` with four valid roles uses deterministic
     synthesis from those roles (`synthesis_source: deterministic`).
  3. When the single full-envelope call fails to parse, recovery retries with
     two smaller calls: roles only, then synthesis + maps + cross-checks over
     the fixed summaries (`recovery_path: two_phase`). If phase 2 fails after
     phase 1 succeeded, the four roles are kept with deterministic synthesis
     and empty maps (`recovery_path: two_phase_roles_only`, status degraded).
  Provider/network failure on the first request does not enter two-phase.
- Harness assertions that only check log count and sender still pass on the
  honest fallback sentence; content-quality claims still need a model that can
  complete at least the roles phase.
