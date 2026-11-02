# 0024 — ReadyMade's Found Concepts vocabulary, and why its source texts are not distributed

- **Status:** Accepted
- **Date:** 2026-09-18
- **Area:** readymade / documentation
- **Relates to:** PRD-READYMADE-EDIT-SESSION

## Context

ReadyMade's data model speaks a vocabulary the repository never defines.
`WorkplanTask` carries `core_idea` and `cosmic_instrument` / `cosmic_instruments`,
and `data/workplan.tres` stores values as bare codes — `"HF"`, `"AH"`, `"IR"` —
while `tasklists/*.json` spell the same things out as
`"Role Play (Dimensional Shifter)"`. A developer reading only the code cannot
tell what an instrument is, which values are valid, or why a content task would
have one.

The vocabulary comes from two texts by the project author that were tracked under
`synesyn_client/readymade/` as authoring reference:

- `kernel_lecture.txt` — "Hacking the Kernel", a performance lecture delivered at
  Art After AI, T.E.K.S., 3 June 2025.
- `FoundConcepts_Draft_00.txt` — an unpublished ~11,800-word scholarly draft,
  "Found Concepts", with a full citation apparatus and attribution statement.

Neither is read at runtime; nothing in the project references either file. They
are source material for the method ReadyMade partially implements. Keeping the
paper in the repository is wrong on two counts: it is pre-publication work, and
the repository's MIT grant describes terms for code that the author does not
intend for scholarly text.

## Options considered

1. **Leave both files tracked.** Costs nothing and keeps the vocabulary
   discoverable, but publishes an unpublished paper inside a code repository and
   under a licence written for code.
2. **Remove both files, record nothing.** Resolves the licensing and IP problem
   and leaves `cosmic_instrument = "AH"` with no way to decipher it, in a module
   still under active development.
3. **Remove both files and record the operative vocabulary here.** Keeps the
   source texts private while leaving the repository self-sufficient for anyone
   extending ReadyMade.

## Decision

Adopt option 3. The source texts are held outside the repository and excluded by
`.gitignore`; what follows is the minimum needed to work on ReadyMade, not a
summary of the method.

**Boosted Inference.** Abductive reasoning — inferring the most plausible
explanation from incomplete observations — combined with Bayesian updating as new
evidence arrives. This is the reasoning stance the module is built around, and
the reason generation is treated as revisable rather than one-shot.

**The four cosmic instruments.** Techniques for shifting what a model or an
institution treats as sayable. These are the valid values of `cosmic_instrument`:

| Code | Name | What it does |
| --- | --- | --- |
| `RP` | Role Play (Dimensional Shifter) | Adopt a persona so its frame of reference pulls exploration toward otherwise unreachable material |
| `HF` | Hypothetical Framings (Reality Benders) | "What if" constructions that suspend current constraints and allow speculative safety |
| `IR` | Iterative Refinement (Gravitational Drift) | Successive approximations, each built on the last, shifting the centre gradually |
| `AH` | Abductive Hypothesis Generation (Quantum Reasoning) | Request explanations for incomplete phenomena, forcing novel construction rather than recall |

**The nine-phase process**, in order: Cosmic Reconnaissance, Archaeological
Identification, Abductive Extraction, Semiotic Isolation, Window-Shifting
Transformation, Stochastic Affordance Composition, Utopian Recontextualization,
Recursive Validation, Inference Architecture.

**What ReadyMade actually implements is a slice of this, not the whole.**
`ProcessFoundConceptTask` takes a task's `core_idea`, generates content through
the LLM with retry handling, and writes markdown to `output/`. The instruments are
metadata carried on a task, not distinct code paths, and the phase sequence is not
implemented end to end. Future work should treat the phase list as a roadmap
rather than a description of current behaviour.

## Consequences

- Positive: the vocabulary in the data model is decipherable from the repository
  alone, and the author's unpublished work stays unpublished.
- Positive: the gap between the method and the implementation is now stated, so
  the phase names in the code are not mistaken for finished features.
- Negative: this records vocabulary and lineage only. Substantive extension of the
  method — the mathematical framework behind the instruments, the historical
  argument — needs the source texts, which a contributor outside the project will
  not have. Such work should go through the author.
- Follow-up: the bare codes are terse and undocumented at the point of use. If the
  workplan format is revised, prefer the explicit names already used in
  `tasklists/*.json` and treat the codes as legacy.
