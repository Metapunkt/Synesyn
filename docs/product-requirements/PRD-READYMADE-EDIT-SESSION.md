---
id: PRD-READYMADE-EDIT-SESSION
title: ReadyMade edit session
status: implementing
version: "0.1"
owner: ReadyMade product owner
last_reviewed: 2026-07-10
primary_users: [writer, editor, researcher]
supersedes: null
---

# ReadyMade edit session

## Problem and outcome

Writers and editors working across multiple documents need AI assistance that
respects the active document, selected context, editing intent, and user control.
ReadyMade Edit Session should provide a focused workspace for loading documents,
choosing an editing mode, controlling which context reaches the model, reviewing
changes, and exporting useful results without collapsing document work into the
separate task-management workflow.

## Users and jobs

- **Writer:** improve a draft while retaining authority over text and revisions.
- **Editor:** apply a named editing mode across one or more documents and inspect
  the basis for suggestions.
- **Researcher:** work with multiple source documents while controlling context
  selection and avoiding accidental prompt-surface mixing.

## Success measures

- A user can load one or more documents and identify the primary document.
- Editing requests use the selected edit mode and explicit document context.
- Large documents remain usable through bounded context construction.
- Suggestions remain reviewable and do not silently overwrite source material.
- A session can produce an edited document or reviewable change summary.

## Scope

### In scope

- Edit Session as a distinct ReadyMade workflow.
- Multiple active documents and a primary document.
- Developmental, structural, content, line, copy, and proofreading modes.
- Explicit single-document, multi-document, and automatic context selection.
- Text selection and document-aware brainstorming.
- Large-document loading and bounded model context.
- Session save/load, change review, and export as product targets.

### Out of scope

- ReadyMade's six-month content workplan and calendar as product requirements for
  Edit Session.
- Autonomous publication or silent source overwrite.
- Treating SynTree conversation history as implicit document context.
- Full ReadyMade platform repositioning beyond the Edit Session flow.

## Critical journey

1. The user switches ReadyMade to Edit Session.
2. They load one or more documents and choose the primary document.
3. They choose an editing mode and document-context policy.
4. They select text or describe an editing need.
5. The system constructs bounded, visible context and produces assistance.
6. The user reviews, edits, accepts, rejects, or exports the result.

Detailed current behavior is documented in
[`readymade/README.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/readymade/README.md). This app-local
guide should later be promoted to the user guide without duplicating its content.

## Requirements

- **REQ-EDIT-001:** Users must be able to load and remove documents without
  changing unrelated ReadyMade workplans.
- **REQ-EDIT-002:** One active document must be identifiable as primary.
- **REQ-EDIT-003:** The selected edit mode must shape the editing instruction.
- **REQ-EDIT-004:** Cross-document context must be explicit and visible to the
  user.
- **REQ-EDIT-005:** SynTree or brainstorming context must not bleed into Edit
  Session unless deliberately included.
- **REQ-EDIT-006:** Large-document handling must bound model context and memory
  use without hiding truncation or document identity.
- **REQ-EDIT-007:** AI output must remain a proposal until the user accepts or
  edits it.
- **REQ-EDIT-008:** Session history and exports must preserve source identity and
  enough provenance to explain what changed.

## Acceptance

No canonical executable run spec currently covers this flow. Before the PRD moves
to `shipped`, add focused specs for:

- loading a document and setting it primary;
- switching edit and context modes;
- constructing bounded multi-document context;
- saving and restoring a session;
- exporting an edited document or change summary.

Manual review remains necessary for editing quality, change visualization,
context legibility, and source-preservation behavior.

## Constraints and dependencies

- [Human Agency UX Contract](../implementation_docs/Human_Agency_UX_Contract.md)
- [`readymade/EDIT_SESSION_IMPLEMENTATION_PLAN.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/readymade/EDIT_SESSION_IMPLEMENTATION_PLAN.md)
- Document session and Mission Control facades documented in
  [`developer-guide/code-map.md`](../developer-guide/code-map.md)

## Open questions and risks

- The app-local implementation plan and current code appear out of sync: several
  features remain unchecked in the plan although implementations exist. Reconcile
  status before declaring the flow shipped.
- ReadyMade lacks a canonical user-guide page.
- Hub artifact and provenance behavior for edited documents needs a normative
  product-to-contract mapping.
- Automated acceptance coverage is absent.

## Evidence map

- Current product and workflow description:
  [`synesyn_client/readymade/README.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/readymade/README.md)
- Implementation tracker:
  [`EDIT_SESSION_IMPLEMENTATION_PLAN.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/readymade/EDIT_SESSION_IMPLEMENTATION_PLAN.md)
- Troubleshooting:
  [`readymade/TROUBLESHOOTING.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/readymade/TROUBLESHOOTING.md)
- Global UX contract:
  [`Human_Agency_UX_Contract.md`](../implementation_docs/Human_Agency_UX_Contract.md)
