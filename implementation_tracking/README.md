# Implementation tracking

Working material, not documentation. These are the checklists and delivery plans
the project is actually built against, kept in the repository so that the people
and agents doing the work read the same file that records it, and so the record
keeps its version history.

**If you are trying to understand Synesyn, this is the wrong directory.** Start at
[`docs/`](../docs/README.md). Nothing here is authoritative: a checkbox states
what someone intended at a moment, not what the system guarantees. Where a
tracker and a contract disagree, the contract in
[`docs/implementation_docs/`](../docs/implementation_docs/README.md) wins, and the
tracker is simply out of date.

For that reason this directory is excluded from the generated documentation site.
It is versioned and public, but it is not presented as an explanation of anything.
ADR 0025 records why.

## Layout

- [`active/`](active/README.md) — living per-component checklists. Expect open
  boxes, superseded lines, and entries that reality has overtaken.
- `completed/` — frozen history: finished plans, and plans whose direction was
  withdrawn. Immutable; if work resumes, open a new checklist in `active/` and
  link back rather than editing the record.

## Conventions

- One component owns one active checklist. Do not open a second tracker for work
  an existing one can carry.
- Link to the normative contract; never restate it here as a second specification.
  A tracker that specifies behaviour has become a contract in the wrong place.
- When a plan is finished or abandoned, move it to `completed/` and say which it
  was. A finished plan left in `active/` reads as abandoned work.
- Paths in old entries may predate renames. `synesyn_dec2025/` is now
  `synesyn_client/`, and `scripts/` and `tools/` are now `utilities/harness/` and
  `utilities/checks/`. Historical entries are not rewritten to match.
