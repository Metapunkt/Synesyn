# 0028 — Internal calls get a low reasoning budget; the model stays the participant's choice

- **Status:** Accepted
- **Date:** 2026-09-20

- **Area:** scensyn

## Context

A Story Catalyst turn is model calls in sequence: one director call that writes a cue per
speaker, one actor call per speaker, and a repair call for any line over its word ceiling.
The wait a participant feels is their sum. On *Ireti Okan* with `grok-4.5` selected, a
single-speaker turn took 15.6s and a repaired one 27s. A staged scene is paced by how fast
a character answers, and at that length a pause reads as breakage rather than as waiting.

Per-call instrumentation (`[budget]` for each call, `[turn]` for each turn) placed the time
inside the HTTP round trip rather than in client overhead, and timing the provider directly
from outside Godot returned the same figures — 7.1s and 7.6s for a director-sized call. The
token accounting said what they bought: **879 prompt tokens, 86 answer tokens, 308
reasoning tokens.** Four fifths of every wait was deliberation nobody reads. The repair
call was worse, spending 647 reasoning tokens and 10.3s restating a line more briefly than
the 3.0s the line itself had cost to write.

So the wait was not the words, the prompts, the network or our code. It was a reasoning
model thinking about work that mostly does not reward thinking.

## Options considered

1. **Shorten what is written** — a tighter word ceiling. Rejected: it costs the dialogue
   itself, and a tight ceiling raises the reprompt rate, which *adds* a call.
2. **Fewer calls per turn** — skip the director for single-speaker turns, cap the cast.
   Removes direction and stage presence to buy seconds; the cue is what keeps a speaker
   answering the participant rather than the room.
3. **Spend less thinking where thinking is not the point** — `reasoning_effort` on the
   internal calls. Cheap, reversible, leaves the writing alone: cue batch 7.4s → 4.2s with
   a valid plan in 3 of 3 runs, repair 10.3s → 3.0s for an equally clean line.
4. **A model that does not reason at all** — same cue, an answer in about a second. The
   fastest option by far, and the one that is not ours to impose (see below).

## Decision

**Option 3 is the default**, chosen per call type, because the calls differ in kind:

| Call | What it is | Reasoning budget |
| --- | --- | --- |
| Director cue batch | Internal direction, never shown to anyone | Low by default (`DirectorAgent.CUE_REASONING_EFFORT`) |
| Actor first take | The writing | The provider's own, unless the scenario overrides |
| Repair | Mechanical: the same line, shorter | Low by default (`ActorAgent.REPAIR_REASONING_EFFORT`) |

**Option 4 is published as guidance, not applied as a pin.** Which model answers is the
participant's choice, made in Settings, and no bundled scenario overrides it. The
`director_model` / `actor_model` keys remain available to anyone authoring their own
scenario, and *Ireti Okan* briefly used them before this was reconsidered: a scenario that
names a model silently overrides the selection, and the session transcript then records a
model the participant never chose — a session is not reproducible if the file quietly
decides what wrote it. The measurements below are the reason to *choose* a fast model for a
staged session, on one actor cue:

| Model | Seconds | Reasoning tokens |
| --- | --- | --- |
| `grok-4.20-0309-non-reasoning` | 1.0–1.2 | 0 |
| `grok-4.3` | 4.4 | 524 |
| `grok-4.5`, low budget | 4.2–5.4 | 119–231 |
| `grok-4.5`, provider default | 7.1–10.0 | 231–308 |
| `grok-4.6` | 24.2 | 1634 |

Ireti Okan's turns across live two-turn runs: **15.6s → 8.7–12.2s** with low budgets on the
internal calls, and **3.3–8.5s** when a non-reasoning model is selected for the session.

Two rules follow, both about not assuming what a provider offers:

- **A reasoning budget is sent only to a model that takes one.** The non-reasoning model
  rejects the parameter with a 400, which would silence any session running on it. The
  client skips the parameter for a model whose name says it cannot reason, remembers any
  model that refuses it, and retries that call once without it. The key reaches only the
  provider that defines it (xAI); nobody else is sent a parameter they do not understand.
- **A provider's model list is a routing table, not documentation.** A session can only use
  a listed model; an unlisted id is taken for a local Ollama model, fails in 0.0s, and the
  turn falls through to its fallback line without saying so. `xai_model.gd` listed three
  models while the key served twelve, which made the first routing attempt look like a
  setting that did nothing.

## Consequences

- Positive: the internal calls stop charging for deliberation nobody reads, which is 3–7s a
  turn on a reasoning model, without touching a single line of dialogue.
- Positive: the choice of model stays where a participant can see and change it, and the
  transcript's recorded model is the one they picked.
- Positive: the trade is legible per call type, so an author can buy speed for their cues and
  keep a reasoning model for their cast, or the reverse.
- Negative: a fast model reads more literally. Figurative speakers held their register
  (Gogo kept Esu and the ancestral ground), but Didi once explained the Tree Hive in
  procedural terms — close to the "debug framing" that scenario's own `[ABOUT]` warns
  against. Worth knowing before choosing speed for a scenario built on argued positions.
- Negative: a slow model still makes a staged scene wait, and this decision does not stop
  it. Pace is now something a participant chooses rather than something a scenario enforces.
- Negative: model lists are hand-maintained per provider and go stale silently. Querying
  the provider's own `/v1/models` at startup would remove the class of failure entirely and
  is a separate decision; xAI already exposes it, and the loaders do not use it.
- Follow-up: in Story Stage a line is spoken before the next is shown, so line length still
  paces the stage even when the model answers instantly. That cost is TTS, measured
  separately from anything here.
- Nothing in this decision crosses the client↔hub seam.
