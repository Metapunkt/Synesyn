# 0006 — Self-validating JSON harness specs

- **Status:** Accepted
- **Date:** 2026-07-09
- **Area:** tooling

## Context

ScenSyn run specs described actions, while acceptance checks lived in CLI flags.
Repeated interaction blocks were copied between specs. Formal Gherkin/Cucumber
would add another language, runtime, and Godot adapter beside the existing JSON
harness.

## Options considered

1. **Adopt Cucumber/Gherkin** — stakeholder-readable, but duplicates the harness
   and requires a custom Godot bridge and step-definition layer.
2. **Extend JSON run specs** — preserves the current runner while making behavior,
   reusable actions, and acceptance criteria travel together.
3. **Keep CLI-only assertions** — no implementation cost, but specs remain
   incomplete and multi-spec runs cannot express distinct expectations.

## Decision

Keep JSON as the executable-spec format. Add embedded `assertions`, reusable
parameterized `action_sequences`, external `action_libraries`, preflight
validation, and automatic failure on unsuccessful dispatched actions. Python
expands named actions before Godot receives the pending spec. CLI assertion flags
remain as backward-compatible, ad-hoc overrides.

## Consequences

- Positive: specs are self-validating, less repetitive, and easier for agents and
  humans to review.
- Positive: no Cucumber dependency or second execution model is introduced.
- Trade-off: editor-driven runs must use the Python runner's `--write-only` path
  when a spec contains named actions.
- Follow-up: add new assertions only when backed by stable structured artifacts;
  do not turn the harness into a second UI automation layer.
