# 0005 — Split HubSubstrateClient into a transport base + endpoint facade

- **Status:** Accepted (amended 2026-11-01)
- **Date:** 2026-07-09
- **Area:** client (GDScript) / contract

> Amendment note (2026-11-01, ADR 0032): `artrhythmetic_store_*` methods on
> `HubSubstrateClient` were renamed to `stfx_store_*`.

## Context
`scripts/hub_substrate_client.gd` was a 1251-line hard violation (ADR 0004) and the single
class mediating the entire Godot client ↔ Python hub seam. It is a `class_name` `Node`
instantiated via `preload(...).new()` in 11 call sites, all invoking methods directly on the
instance (e.g. `client.artrhythmetic_store_status()`). Any split had to preserve that public
API exactly to avoid a wide, regression-prone edit across consumers.

## Options considered
1. **Composition sub-clients** (`client.store.status()`, `client.render.get_job()`) — clean
   domains, but changes the public API and forces edits to all 11 call sites (high blast radius).
2. **Extract only static helpers** into a util file — trivially safe, but only removes ~100 lines;
   the file stays a hard violation.
3. **Inheritance split**: a `HubSubstrateTransport extends Node` base holding all plumbing
   (HTTP verbs, WebSocket loop, retry policy, auth, signals, state), and
   `HubSubstrateClient extends HubSubstrateTransport` holding the domain endpoint wrappers.

## Decision
Option 3. Methods and signals are inherited, so all 11 call sites keep working with zero
changes. The dependency is one-directional: the transport base is self-contained and never
calls into the facade; the facade calls inherited transport helpers (`_post_json`, `_get_json`,
`_delete_json`, `_patch_json`, `_get_workspace_root`, `ensure_ws_connected`). Both files now sit
in `scripts/` alongside each other (no new directory, no duplicated code).

## Consequences
- Positive: `hub_substrate_client.gd` 1251 -> 799; new `hub_substrate_transport.gd` well under
  limits; the seam's transport policy is now isolated and independently readable.
- Negative / trade-offs: introduces one inheritance layer (a base class) — judged acceptable and
  idiomatic vs. the call-site churn of composition.
- Verification: headless parse/instantiate check confirmed inheritance, all 21 methods, all 6
  signals, and inherited state on one instance; ScenSyn smoke harness passed (8 story-log
  entries, no errors). Ratchet baseline regenerated.
