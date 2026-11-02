# Utilities

Developer tooling for this repository. Nothing here ships with the client or the
hub; it exists to run and police the code that does.

- [`harness/`](harness/README.md) — the self-validating harness that executes the
  JSON behaviour specs in [`../docs/technical-review/run_specs/`](../docs/technical-review/run_specs/README.md).
  See ADR 0006 for why verification is spec-driven.
- [`checks/`](checks/README.md) — policy checks, chiefly the line-limit ratchet
  (ADR 0004) and the addon autoload guard.
- [`docs/`](docs/README.md) — the MkDocs toolchain that builds a browsable site
  from `../docs/`, and the strict build that fails on a broken cross-reference or
  an unplaced document.
- [`assets/`](assets/README.md) — builds and installs the optional content packs
  for assets too large to commit, currently the Story Stage sprite library.
- [`spikes/`](spikes/story_stage_motion/README.md) — throwaway experiments that
  answer one question before a design commits to it. `story_stage_motion/` tests
  generated talking-head clips for Story Stage (ADR 0030).

They expect to be run from the repository root, and each resolves that root from
its own location, so they will need updating if this directory moves.
