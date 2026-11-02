# 0025 — `docs/` publishes explanation; work tracking moves to `implementation_tracking/`

- **Status:** Accepted
- **Date:** 2026-09-19
- **Area:** documentation / tooling
- **Amends:** ADR 0007 (documentation governance and product requirements)
- **Relates to:** ADR 0001 (ADRs), ADR 0023 (repository root)

## Context
`docs/implementation_docs/` held three different kinds of writing under one roof:
normative contracts, live delivery checklists, and frozen engineering history.
ADR 0007 gave that directory ownership of all three, which was sound while every
reader was the author or an agent working in the tree.

Publishing the repository changed who reads it, and a documentation audit put
numbers on the cost. The twelve files in `to-do lists/` carried roughly 178 open
checkboxes against 556 ticked ones, one file running to 934 lines. Several
contradicted shipped reality: `10_Session_Types_and_Society_of_Minds.md` listed
as unstarted work that `11_Workshop_Catalyst_Build_Staging.md` recorded as
complete. A newcomer cannot tell a stale checkbox from a real gap, so the tracking
material reads as an abandoned project and drowns the contracts a reader actually
needs. The same files also carry pre-rename paths (`synesyn_dec2025/`), which is
harmless as history and misleading as instruction.

Deleting them was not an option worth having. They are live working memory for
the agent workflow described in ADR 0003, and their git history is the project's
only record of how delivery actually proceeded.

## Options considered
1. **Leave everything in `docs/`.** No work, and the published documentation keeps
   presenting sprint boards as explanation.
2. **Withhold the trackers from the repository**, as the audit recommended. Fixes
   the public surface, but breaks the agent workflow that reads those files and
   discards the delivery history.
3. **Keep them in `docs/` but exclude the subfolders from the site build.** Cheap,
   and leaves anyone browsing the repository on GitHub landing in the middle of
   them, since `docs/` is where a reader is told to look.
4. **Migrate open items to GitHub Issues and archive the files.** Most idiomatic
   for open source, and it moves work tracking out of reach of local agents, which
   is the one place it is used daily.
5. **Split by kind: `docs/` for explanation, a sibling directory for working
   material.** Keeps history and the agent workflow, and makes the published tree
   readable.

## Decision
Adopt option 5.

`docs/` holds writing whose purpose is to explain the system: guides, concepts,
product requirements, decisions, normative contracts, and run specs. Everything
there is intended to be read by someone who is not us.

`implementation_tracking/` holds writing whose purpose is to organise work:
`active/` for living checklists, `completed/` for frozen and withdrawn plans. It
stays tracked in git, sits outside `docs_dir`, and is therefore absent from the
generated site without needing an exclusion rule.

The operative test is **obligation versus intention**. A document stating what the
system must do is a contract and belongs in `docs/implementation_docs/`. A
document stating what someone means to do next is a tracker and belongs in
`implementation_tracking/active/`. Nothing in `implementation_tracking/` is
authoritative; where it disagrees with a contract, the contract wins.

This amends ADR 0007, which assigned all three kinds to one directory. The
ownership rules in that decision are otherwise unchanged: product intent still
belongs to `docs/product-requirements/`, and design rationale to ADRs.

## Consequences
- Positive: the published documentation can be read as an account of the system.
  The 934-line staging plan and the contradictory checkboxes no longer sit beside
  the contract spine.
- Positive: git history and the agent workflow are preserved, since the files
  moved rather than being withheld, and `git mv` kept their history.
- Positive: documentation CI no longer runs on tracker edits, so routine
  checkbox-ticking stops triggering site builds.
- Negative: contracts and their trackers are now in separate trees, so a
  cross-reference between them is a repository-absolute link rather than a
  relative one. Links from `docs/` into `implementation_tracking/` must be
  absolute `github.com` URLs, because the site contains only `docs/`.
- Negative: the split is a convention, not a mechanism. A plan can still be
  written into `docs/`, and only review will catch it.
- Follow-up: the trackers themselves were not corrected. Their stale paths and
  false-open checkboxes remain, now labelled as unreliable rather than presented
  as documentation. Correcting them is component work, not a documentation task.
