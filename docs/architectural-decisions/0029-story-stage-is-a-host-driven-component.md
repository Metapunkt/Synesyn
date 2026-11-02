# 0029 — Story Stage is a host-driven component

- **Status:** Accepted
- **Date:** 2026-09-24
- **Area:** client

## Context

Story Stage began as a ScenSyn screen and grew into the most capable presentation surface
in the client: sprites with lip-sync, scenario backdrops, a slideshow fed by renders, the
lull protocol, ambient audio. Every one of those capabilities is reached only through a
live ScenSyn session, because the stage asks for the facts of its situation itself. It
reads the scenario, the local character, the TTS emitter and the welcome flags from
`Global`; decides who commits a typed line through `Network`; reads and writes the story
log on `StoryState`; builds a `ScenSynVoiceBridge`; and navigates by loading ScenSyn scene
paths.

That has two costs. Nothing but ScenSyn can put a line on the stage — replaying a saved
session for an exhibition or an archive needs the hub, a model and a session running.
And because each of those facts is a single app-wide value, one program can hold only one
stage.

## Options considered

1. **Leave it in ScenSyn and add a playback mode there.** Cheapest, but every new use
   repeats the same entanglement, and a replay would still boot ScenSyn's session stack.
2. **Move the folder into `addons/` as it stands.** Breaches the layering rule
   immediately: an addon naming ScenSyn autoloads, preloading ScenSyn services and
   `syntree_voice` scripts.
3. **Make the stage ask a host for its situation, then move it.** The stage talks to a
   `StoryStageHost`; ScenSyn supplies one, and other applications supply their own.

## Decision

Option 3, in three phases, each shippable and each leaving ScenSyn's behaviour unchanged:

1. **Host interface in place.** `StoryStageHost` defines what a stage may ask for —
   scenario and stage config, story-log entries, local speaker, voice, navigation,
   optional session services, asset roots — with inert defaults. `ScenSynStageHost`
   answers with today's calls. A stage opened by `change_scene_to_file`, where nobody can
   hand it a host, loads the script named by the project setting
   `story_stage/default_host_script`. A guard script keeps ScenSyn names out of the stage.
2. **Move into `addons/story_stage`.** Code, scenes and generic assets move; the voice
   bridge is reached through a port; ScenSyn's own controls live in a wrapper scene.
3. **Prove it with a story-log player** that runs with no hub and no model.

Scenario art — `sprites/`, `resources/generated/`, scenario backgrounds — is ScenSyn
content, not stage code, and stays where it is. The generated `.tres` files and the
sprite tooling keep their paths.

## Consequences

- Positive: a saved session can be staged without a session, and any application that
  produces "speaker says line" can use the stage.
- Positive: the ScenSyn-only features (renders, model controls, services panel, dual
  window, consent, STT) are visible as a list on one class rather than scattered.
- Negative: `Character` is a static class that caches sprite frames by name, so its
  sprite context is process-wide, set by the most recently readied stage. Two stages
  showing different scenarios in one program need that cache keyed by host first; that
  is deferred until a consumer needs it.
- Negative: the host surface is wide because the stage's needs are. It should narrow as
  ScenSyn-only behaviour moves out of the stage and into the host.
- The standalone visual-novel mode (`dialog_file`, `SceneManager`, `title_screen`) was
  reachable only without `StoryState`, which never happens in this project, and is
  removed rather than carried into the addon.
- Nothing here crosses the client↔hub seam. The story-log provenance sidecar gaining a
  `stage` block in phase 3 is a client file format change.

## As built

- The host is `StoryStageHost` (`addons/story_stage/scripts/story_stage_host.gd`). It is
  set on `stage.host` before the stage enters the tree. Otherwise it comes from the
  `story_stage/default_host_script` project setting, and failing both, from the base
  class. Optional controls are gated by `supports(feature)`. The participant's own lines
  (the microphone, auto-input and recording controls) are all `FEATURE_TYPED_INPUT`.
- The stage reads lines from `get_story_log_entries()` and waits for `story_log_changed`.
  A host paces a replay by revealing entries. The stage keeps its own hold per line:
  until the voice ends, or else a reading time. `StoryStageLineFeed.read_pause_scale`
  shortens or removes the reading pause without changing the default.
- `replay_story_log()` restarts the stage over the host's current log.
  `BackgroundController.restage_scenario_background()` re-resolves the backdrop after the
  host's scenario changes. The stage resolves the backdrop only once, when it becomes
  ready.
- The sidecar is `synesyn_provenance_v2`. Its `stage` block holds `collection`,
  `scenario_key`, `scenario_name`, `default_background`, `cast` and `voice_overrides`.
- `StoryStageCharacter` is now instantiated per stage (`CharacterRegistry`) rather than
  holding a process-wide static sprite cache, so multiple stages in one process do not
  collide.
- The consumer is `synesyn_client/playback/`: `StoryLogPlaybackHost` and
  `story_log_player.tscn`. It is covered by `playback_smoke.json`.
