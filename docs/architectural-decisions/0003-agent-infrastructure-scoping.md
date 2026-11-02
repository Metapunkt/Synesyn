# 0003 — Scoping of agent infrastructure (rules, skills, sub-agents)

- **Status:** Accepted
- **Date:** 2026-07-09
- **Area:** tooling

## Context
We added AI dev infrastructure (rules, skills, sub-agents) and had to decide where each lives so it activates appropriately. The workspace is large and multi-root (`StochasticDreams`, `ForwardRemembrance_Thesis`, `Open_Closure`), and `StochasticDreams` contains far more than Synesyn (Metapunkt_artVenture, FRIPRO, FlusserianInference). Always-on infra would leak into unrelated work.

## Options considered
1. **Everything global** (`~/.cursor/`) — reusable everywhere, but Synesyn-specific rules would fire during thesis/grant work.
2. **Everything project-root, always-on** (legacy `.cursorrules` style) — scoped to StochasticDreams, but still active across all its non-Synesyn subtrees.
3. **Mixed, scoped by activation semantics** — glob-scoped rules, description-gated project skills, global generic skills, sub-agents as role-prompt skills.

## Decision
Option 3:
- **Rules** are glob-scoped `.mdc` (`synesyn/**` for invariants, `synesyn/services/synesyn_hub/**` for hub standards) so they auto-attach only within Synesyn.
- **Synesyn-specific skills** (`run-hub-tests`, `run-scensyn-harness`, `godot-headless-eval`, `record-decision`, the two sub-agents) live in `StochasticDreams/.cursor/skills/`, description-gated.
- **Generic utility skills** (`preview-pdf`, `document-conversion`) promoted to `~/.cursor/skills/` for all projects.
- **Sub-agents** (`synesyn-reviewer`, `synesyn-design-explorer`) provisioned as role-prompt skills launched via the `Task` tool, because its base subagent types are fixed.

## Consequences
- Positive: Synesyn rules stay silent during thesis/FRIPRO/`Open_Closure` work; generic skills reusable everywhere.
- Negative / trade-offs: sub-agents are invoked by name rather than auto-triggering.
- Note: the `synesyn_ARCHIVED/` tree duplicates these paths; scope tooling to the live `synesyn/` tree.
