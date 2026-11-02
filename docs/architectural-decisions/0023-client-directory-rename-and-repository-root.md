# 0023 — Client directory renamed to `synesyn_client`, and `synesyn/` is the repository root

- **Status:** Accepted
- **Date:** 2026-09-18
- **Area:** client | tooling

> Amendment note (2026-09-18, same day): the root-level `scripts/` and `tools/`
> referred to below were subsequently grouped as `utilities/harness/` and
> `utilities/checks/`, and `Technical_Implementation_Documents/` moved to
> `docs/implementation_docs/`. The decision recorded here — the client name and the
> repository boundary — is unaffected.

## Context
The Godot client lived in `synesyn/synesyn_dec2025/`, a name that recorded when
the project was started rather than what the directory is. That was tolerable
while the tree was private working material. Preparing the project for a public
repository forced the question, because the name would become the first thing a
contributor reads, and because the repository boundary had to be fixed anyway:
the surrounding `StochasticDreams` workspace holds unrelated projects, archives,
and ~60 GB of build output that must not be versioned.

The client also sat beside `synesyn/services/synesyn_hub/`, so the pair read as
`synesyn_dec2025` and `synesyn_hub` — an asymmetry that obscured the fact that
these are the two halves of one system.

## Options considered
1. **Leave the name; document it** — zero risk, but the date-stamped name keeps
   misleading readers indefinitely, and every path in the docs carries it.
2. **Rename to `client/`** — symmetrical with a hypothetical `hub/`, but too
   generic once the directory is the root of a public repository, and it loses
   the product name that makes `res://` paths self-describing.
3. **Rename to `synesyn_client/`, with `synesyn/` as the repository root** —
   mirrors `synesyn_hub`, keeps both halves meaningful inside `synesyn/`, and
   states the boundary explicitly.

## Decision
The client directory is `synesyn/synesyn_client/`, and `synesyn/` is the root of
the Git repository. The `services/` parent is retained as-is rather than
flattened, because `logging_setup.py` resolves paths relative to it.

The rename touched 222 references across 43 files, including `.tscn` and `.tres`
resources, harness run specs, and tooling under `scripts/` and `tools/`. Godot
must not be running during such a rename: the editor holds open handles on
`.godot/` and writes back stale paths on exit.

## Consequences
- Positive: the client and hub now read as one system, and no path in the tree
  records an obsolete start date.
- Positive: the repository boundary is explicit, which is what makes it possible
  to exclude `ExportedPackage/`, `Exports/`, and `synesyn_ARCHIVED/` by
  construction rather than by `.gitignore` alone.
- Trade-off: ADRs 0004 and 0018 quote the old path in their historical analysis.
  They carry dated amendment notes rather than being rewritten, since editing
  the record would falsify what was true at the time.
- Follow-up: `AGENTS.md` and `.cursor/rules/` moved into the repository during
  the same preparation, with paths rewritten to be repo-relative rather than
  workspace-relative.
