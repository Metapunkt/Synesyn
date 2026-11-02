# 0019 — Thinking Map human authorship: propose vs commit

- **Status:** Accepted
- **Date:** 2026-09-05
- **Area:** scensyn
- **Relates to:** ADR 0008 (shared Graph Workspace, product-owned adapters), ADR 0009
  (Workshop Catalyst session model), ADR 0013 (facilitator claim),
  `Human_Agency_UX_Contract.md` §4.4.2

## Context

Until now the Workshop Catalyst Thinking Map could only be populated by the
system. Cards arrived either from the specialists' `map_candidates`, or — when the
model returned none — from `workshop_participant_map_extractor.gd` scraping the
facilitator's chat message with marker-word lists. Humans could accept, edit,
reject, or defer what arrived, and could draw typed edges by hand, but could not
state a claim directly.

That inverted the Human Agency contract on this surface. The contract's premise is
"the system proposes; the human closes," yet here only the system could propose. A
facilitator who saw a missing cause had to phrase it into chat and hope a keyword
matcher classified it into the right column. Two further signals suggested a gap
rather than a considered restriction: `SOURCE_CLASSES` already reserved
`participant_said` for human-origin items, and manual *edges* were already
supported (`manual_edge_command`, `authorship_kind: "facilitator_manual"`) while
manual *nodes* were not.

The open questions were who may author a card, what review state it enters in,
and whether an authored card can be changed or removed afterwards.

## Options considered

1. **Facilitator-only authorship, cards enter pre-accepted.** Simple and matches
   the existing commit gate. Rejected as the *whole* answer: it makes the
   facilitator the sole scribe for a room convened to think collectively, and it
   would need replacing the moment multi-instance sync lands.
2. **Anyone may author, cards enter accepted.** Rejected: a participant's claim
   entering as settled fact bypasses the facilitator's review authority, which
   the contract assigns explicitly.
3. **Everything enters as `suggested`, including the facilitator's own typing.**
   Preview then always shows a complete diff. Rejected: forcing the review
   authority to approve their own sentence is friction without a safeguard —
   there is no second party for the review to protect.
4. **Author-scoped authorship split across propose and commit.** Chosen.
5. **Re-key a card's id when its wording is revised.** Rejected: ids are
   content-derived, and re-keying orphans edges and saved node positions.

## Decision

1. **Anyone may propose; only the facilitator commits.** Authorship is not gated
   on the facilitator claim, but publishing to the Hub remains gated, as it
   already was for map, record, and path commits (ADR 0013 rule 6).
2. **Review state follows authorship.** A facilitator-authored card enters
   `accepted` (`authorship_kind: "facilitator_manual"`); a participant-authored
   card enters `suggested` (`participant_manual`) and the facilitator still
   accepts, edits, rejects, or defers it. `manual_node_command()` takes the author
   and status as parameters, so participant proposals are a caller change rather
   than new adapter logic when multi-instance sync arrives.
3. **Human origin stays visible.** Manual items carry
   `produced_by: "scensyn.workshop_manual_map_item@1"`, `authored_by`, and
   `authorship_kind`, and their card reads "Added by facilitator" rather than
   "Participant said" — the latter implies a transcript quote.
4. **An author may revise or withdraw their own item until it is committed.**
   `revise_own_node()` and `withdraw_node()` share one predicate,
   `is_own_uncommitted()`. Revision is deliberately *not*
   `review_proposal("edited")`: that models reviewing another party's proposal and
   requires `suggested` status, whereas correcting your own typo is not a review
   decision and must work on an already-accepted card.
5. **AI proposals are never withdrawable.** Rejecting them sets a status and keeps
   the record, so the specialists do not silently re-suggest the same claim.
   Withdrawal exists for human authorship only.
6. **Withdrawal cascades to edges.** Removing a node without its edges leaves
   dangling endpoints, which `GraphWorkspaceDocument.validate()` rejects
   (`dangling_edge_from` / `dangling_edge_to`). The removed edge ids are reported
   so the UI can say what else went.
7. **Ids stay keyed to the original wording.** A revision updates the label and
   records `original_label`, `revised_by`, and `revised_at`, but not the id.
8. **Retraction is history.** A withdrawal appends a `withdrawn` entry to the
   decision ledger even though the node is gone, and the ledger ships in the
   commit payload.

## Consequences

- Positive: the map becomes a surface humans can write to, not only react to; the
  category picker sidesteps the marker-word classifier entirely; the
  participant path is designed now and cheap to enable later; provenance keeps
  AI, transcript, and human-authored claims distinguishable in the committed
  artifact.
- Trade-offs: because ids are content-derived and survive revision, add-dedupe
  still matches a revised card's *original* wording, so re-adding the new wording
  can create a twin for the author to withdraw. Chosen over orphaning every edge
  and saved position. A manual card also duplicates rather than merges when its
  text matches an existing AI proposal, since the two have different provenance
  and different ids.
- Trade-offs: rule 2 means the review state of a card no longer implies who
  reviewed it — `accepted` may mean "authored by the facilitator" or "reviewed by
  the facilitator." `provenance.authorship_kind` is the discriminator.
- Follow-ups: participant authorship stays inert until Workshop Catalyst
  multi-instance sync exists (ADR 0013 records Invite as a stub). The facilitator
  manual is worth a mention of Add / Save edit / Withdraw when next revised.
  Nothing here crosses the client↔hub seam: the commit payload gains provenance
  fields inside the existing `ui.workshop_thinking_map` envelope, and the graph
  schema version is unchanged.
