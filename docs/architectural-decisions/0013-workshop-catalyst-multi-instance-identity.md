# 0013 — Workshop Catalyst multi-instance identity and facilitator claim

- **Status:** Accepted
- **Date:** 2026-08-05
- **Area:** ScenSyn / Workshop Catalyst
- **Relates to:** ADR 0009 (session model; Invite/remote sync deferred as target UI)

## Context

Story Catalyst still has a local ENet host/join path for multiple ScenSyn
instances on one machine. Workshop Catalyst does not: Invite is a stub, each
instance starts an independent session, and custom Scenarios are local drafts
only. When multi-instance WC is built, workshop *state* (transcript, Session
Record, Thinking Map, Compare Paths, stage/timer) should sync — but facilitator
*identity* must not be copied onto every peer.

The open questions were: who becomes Facilitator, how peers name themselves,
whether rename is allowed, and what happens if the Facilitator disconnects or
nobody claims the role.

## Options considered

1. **First-launched instance is always Facilitator.** Simple, matches ENet
   server creation order. Rejected: launch order is unreliable for local demos;
   a spectator who opens first accidentally owns the session.
2. **Claim-until-taken, with persistent need-facilitator popup.** Every
   connected instance can claim Facilitator until one succeeds; if none has
   claimed (including after disconnect), all instances show a blocking popup
   that remains until someone claims. Chosen.
3. **Fixed literal sender `"Facilitator"` for the host; participants cannot
   rename.** Rejected: facilitator should be able to set a personal name
   (e.g. `Alex (Facilitator)`), and participants should be able to rename
   after join.
4. **Automatic facilitator handoff on disconnect.** Rejected: silent transfer
   is surprising; reclaim via the same popup keeps authority explicit.

## Decision

For Workshop Catalyst multi-instance sessions (initially same-machine ENet;
Hub-mediated remote sync remains a later contract):

1. **Sync workshop state, not a shared “everyone is Facilitator” identity.**
   Each peer keeps its own display name / sender; exactly one peer holds
   facilitator authority at a time (or none, while reclaim is open).
2. **Claim-until-taken.** Any connected instance may claim Facilitator until
   one claim succeeds; further claims are rejected.
3. **Need-facilitator popup.** If no peer holds the role — at session start
   before any claim, or after the Facilitator disconnects — **all** connected
   instances show a popup stating a facilitator is needed and offering to
   claim. Popups remain until one person claims.
4. **Facilitator naming.** The Facilitator may set a personal display name
   (recommended form: `Alex (Facilitator)`). Authority is the claim flag, not
   the literal string `"Facilitator"`.
5. **Participant naming.** Joining peers enter a display name (replacing the
   single-player default identity). Rename after join is allowed; renames sync
   so the story log and presence list stay consistent.
6. **Authority gates.** Facilitator-only actions (stage advance, stress
   inject, map/summary/path commits, End & Save as session owner, etc.) require
   the local peer to hold the claim. While no facilitator is claimed, those
   actions stay unavailable.

## Consequences

- Positive: launch order does not invent a facilitator; reclaim is the same UX
  as initial claim; names are human-readable without conflating role and label.
- Trade-offs: a session can exist briefly (or longer) with no facilitator while
  the popup is open — specialist turns and commits that need facilitator
  authority must wait; UI must treat “no facilitator” as a first-class state.
- Follow-ups: Hub publication of custom Scenarios and remote multi-client sync
  remain separate contracts. Facilitator manual should mention the local
  Multiplayer join + claim popup when that guide is next revised.

## Implementation note (2026-08-05)

MVP landed for same-machine ENet:
- `workshop_presence_store.gd` / `workshop_presence_sync.gd` (child of `Network`)
- `workshop_presence_controller.gd` + `NeedFacilitatorDialog` in the workspace shell
- `Network.is_enet_session()` distinguishes live ENet from Godot’s always-present
  OfflineMultiplayerPeer (do not use `is_multiplayer()` for WC presence)
- Host `_set_ws` → `sync_story_state`; clients rehydrate panels on fingerprint change
- Facilitator gates on Next Stage, Inject Stress, End & Save, map/record/paths commits
- Focused tests: `test_workshop_catalyst_stage12_presence.gd`
