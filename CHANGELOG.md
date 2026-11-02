# Changelog

Notable changes to Synesyn, in the style of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned according to
[Semantic Versioning](https://semver.org/).

Two things to know before reading. **Before 1.0 there are no compatibility
promises**: artifact schemas, addon APIs and workspace layout may change between
releases, and an ADR records it when they do. And the git history begins with a
wholesale import of an existing codebase, so there is no per-change record of the
work that produced the platform itself — the README describes what it is, and
[`docs/architectural-decisions/`](docs/architectural-decisions/README.md) records
why it is built that way.

## [Unreleased]

Everything below is in `main` and unreleased; it becomes **0.1.0** when the
repository is published and tagged.

### Added

- Optional **content packs** for the Story Stage sprite library, which is too large
  to commit: a build/install/inspect tool and manifest in `utilities/assets/`, with
  deterministic archives, checksum verification and validation before any existing
  art is replaced
- Documentation for the two ScenSyn **session types** as distinct things, including a
  Story Catalyst page covering its three collections and an authoring guide for Open
  Play stories
- **Building on Synesyn**: layer boundaries, how to register a session type or
  collection, and how to start a separate application on the infrastructure
- A **glossary**, which disambiguates *closure* in particular, and a
  **privacy and data** page stating what leaves the machine
- A **documentation site** built from `docs/` with MkDocs, with publishing left
  dormant until the repository is public
- A **documentation path checker** (`utilities/checks/check_doc_paths.py`) and a
  policy-checks workflow, so a documented path that stops resolving fails CI
- Licensing and provenance surface: `LICENSE`, `TRADEMARK.md`,
  `THIRD-PARTY-NOTICES.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`,
  `CITATION.cff` and issue and pull request templates
- **Reproducible screenshots**: the harness can now capture at a chosen window size,
  capture repeatedly within one run, and mount a second view of a running session, so
  the published README images are regenerated from a scripted session with assertions
  rather than staged by hand (`scensyn_readme_captures.json`)
- A **story-log player** (**Play a Story Log** on the launcher). It replays a saved story
  log on Story Stage with no session, model or hub. It paces lines by reading time, by the
  gaps originally recorded, or one step at a time, at five speeds, with an optional loop
  for exhibitions. It speaks when a voice service is present. The harness spec is
  `playback_smoke.json`
- The story-log provenance sidecar is now `synesyn_provenance_v2`, with a **`stage`
  block**: collection, scenario, default background, cast and voice overrides, so a log
  can be restaged later. Logs without it still play, with dialogue only
- A `log_not_contains` harness assertion

### Changed

- Copyright notice is © 2025 “Synesyn” by Ayodele Arigbabu, Norwegian University of Science and Technology. Source code stays MIT. Text, documentation, and other website material are CC BY-SA 4.0. `TRADEMARK.md` no longer restates the MIT permissions. The NTNU Discovery pilot credit and logo are in the README and the documentation index.

- **Story Stage is its own addon**, `addons/story_stage`, and depends only on
  `synesyn_core`. It asks a `StoryStageHost` for everything it used to read from ScenSyn's
  autoloads. ScenSyn supplies `ScenSynStageHost` and wraps the stage in
  `scensyn_story_stage.tscn`. Scenario art stays in `ScenSyn/story_stage/`. A boundary
  check and a clean-project drop-in test keep the addon standalone. The unused
  standalone visual-novel mode was removed (ADR 0029)
- **Story Stage refactoring for motion and imagery layers**: `addons/story_stage` now uses
  per-stage `StoryStageCharacter` registries, `SubViewport` rendering, per-speaker audio
  buses (`StoryStageMotion`) driving rung-1 speech level and visemes, `StoryStagePresenter`
  / `StoryStagePresenter2D`, audio-timed `stage_cues` (`[STAGING]`), the `StoryStageImagery`
  port (`[VIS_PORTRAIT]`), rung-3 `Skeleton2D` and shader deformation
  (`[CHARACTER_MOTION]`), and `[STAGES]` topology (ADR 0030)
- **Renamed `artrhythmetic_*` kernel, memory, and store to `stfx` (`stfx_core`,
  `stfx_memory`, `stfx_store`)** across hub packages, `/stfx-memory` and `/stfx-store`
  HTTP routes, workspace storage paths, contract schemas, and `HubSubstrateClient`
  methods (ADR 0032)

- Session captures moved from the `ui.closure` artifact type to
  **`ui.workshop_closure`**, with hub-side validation for both. Writing two
  incompatible payload shapes under one type corrupted SynAxes' coverage figures and
  crowded genuine slices out of its query window (ADR 0026)
- The client directory became **`synesyn_client/`**, and `synesyn/` the repository
  root (ADR 0023)
- Developer tooling regrouped under **`utilities/`** (harness, checks, docs, assets),
  and implementation contracts moved into `docs/`
- `docs/` now publishes explanation only; checklists and delivery plans live in
  `implementation_tracking/` (ADR 0025)
- A word ceiling with `reprompt_on_excess` now carries a **tolerance of a quarter**: a
  line a few words long is cut at a sentence boundary, and only one running well past the
  ceiling is sent back for a shorter take. A reprompt is a second model call, which
  doubles the wait for that line, and half the turns were paying it to lose five words
- The per-call `[budget]` log line now reports **how long the call took**, printed on
  completion rather than dispatch, and each turn prints a `[turn]` line giving the
  seconds to its first line and to its last. A turn costs a director call, an actor call
  per speaker and sometimes a repair, in sequence; together the two lines separate the
  provider's share of a slow turn from ours — measured on Ireti Okan with grok-4.5, a
  15.6s turn was 15.6s of model time, and a repaired line added 11.1s
- **Cues and repairs are written on a low reasoning budget**, which took a single-speaker
  turn on Ireti Okan from 15.6s to 11.5s and a repair from 10.3s to 3.0s. Those `[budget]`
  seconds turned out to be almost entirely reasoning tokens nobody reads: Grok spent about
  four of them per token of a director cue, and thought longer about shortening a line than
  about writing it. A director cue is internal and a repair only restates an existing line,
  so both can be thought about less; first takes are untouched, because that is the writing.
  Scenarios override either with `director_reasoning_effort` and `actor_reasoning_effort`,
  and providers that do not accept the setting never receive it (ADR 0028)
- **Which model answers stays the participant's choice.** Selecting a non-reasoning model
  takes a single-speaker Ireti Okan turn from 15.6s to **3.3s** — the difference between a
  staged line landing in conversational time and a visible wait — and timed against every
  model the key serves, the fast one answers in about a second where the reasoning models
  spend five to twenty, keeping the cast's register while reading a little more literally.
  That is published as a reason to choose such a model in Settings, not applied as a pin: no
  bundled scenario names a model, because a scenario that does silently overrides the
  selection and the transcript then records a model nobody chose. The `director_model` and
  `actor_model` keys remain for anyone authoring their own (ADR 0028)
- **The xAI model list now matches what the API serves** (nine chat models, was three).
  A scenario can only be routed to a model the client lists, and an unlisted one is assumed
  to be a local Ollama model: the call fails instantly and the turn falls through to its
  fallback line, on the globally selected model, without saying so
- **Cultural Narratives opens on Ireti Okan.** A collection with nothing chosen yet opened on
  whichever scenario its registry happened to list first, so the collection introduced itself
  with Stochastic Dreams — an installation piece still marked work in progress, and one that
  waits on a pendulum for input. A collection can now name its own default, and the ones that
  name none still fall back to list order
- **Inter Bold** replaced a font named "Claris Sans" in the light themes, because the
  upstream release carried no licence grant, no copyright line and no attribution in
  its name table, and so was not redistributable as it stood

### Fixed

- **The first spoken line from the human participant now carries its resolved scenario
  voice** instead of falling back to the hub default (`en-US-AriaNeural`), and `/voice/speak`
  no longer caches SAPI fallback audio under neural voice cache keys in `tts_cache.json`
  (ADR 0031)
- **A line stays in the dialogue box for as long as its speaker is on stage.** The box
  retired two seconds after every line, so the standing character was left beside an empty
  panel, reading as though they had said nothing and giving a participant no chance to
  re-read what was said. It now retires only when nobody is on stage — a disembodied voice,
  or a cast that ships no art — which is what still clears the stage for an unattended
  installation as its silence escalates
- **A turn's second and third speakers are no longer rejected for punctuation.** A colon in the
  first forty characters was read as a leftover speaker attribution, so "Listen: the river does
  not argue" was thrown out as malformed — a shape figurative dialogue takes constantly. The
  repair call could not fix a line that was not broken, so it failed twice and the line was
  dropped; when every planned speaker was dropped the turn fell through to a single fallback
  line, which is why a two- or three-speaker turn kept arriving as one response. Only a known
  name in front of a colon now counts as attribution, and it is stripped rather than rejected,
  which also saves the repair call it used to cost. A bracketed or asterisked aside — "(leans
  in)", "*a pause*" — is stripped on the same grounds: the line's words are already there, and
  losing the speaker costs the scene more than the aside did. Measured over three turns before
  and after: 2 planned speakers and 0 spoken became 2 planned and 2 spoken
- **A dropped line says so in the log.** A planned speaker whose line failed validation was
  skipped in silence, so a turn that planned three speakers and posted one looked like a turn
  that had planned one. The `[turn]` line now reports planned and spoken separately
- **The home screen's setup message sits in the middle of its banner.** The message label was
  set to expand, so it took the whole row and left its text hard against the left edge while
  the Open Settings button was pushed to the far right, defeating the row's own centring. The
  message is centred now, held there by a spacer mirroring the button's width, which collapses
  when the button is hidden; the banner is a little wider to pay for the space that costs
- **A harness run that dies no longer passes on the previous run's results.** The pointer
  to the newest run outlives the run that wrote it, and the runner accepted whatever it
  found, so a session that ended early was reported with an earlier session's directory,
  scene logs and assertions: a green result for a run that never happened. The pointer is
  now cleared before Godot is launched, and its absence afterwards is the failure it is
- **Story Stage now finishes starting up, so characters appear and speak again.** Four
  small handlers had been inserted between the halves of the stage's `_ready()`, which
  ended the function early and left the rest of it — the setup that starts story-log
  tracking, routes speech to the stage, creates the voice bridge and the microphone —
  inside a function nothing calls. The stage therefore rendered its backdrop and then
  waited forever: typed input reached the session and the model answered, but no line
  and no character was ever shown, and the silence escalated the lull protocol. It
  looked like missing sprite art, which was intact all along
- **A turn's first line no longer waits for its last.** A turn plans up to three speakers
  and generates them in sequence, but every line was held back until the whole cluster
  had returned, so a two- or three-speaker turn showed nothing at all for the length of
  all of its model calls — the first line had been ready for ten or twenty seconds. Each
  line is now posted as it arrives, still through the one seam that writes a visible line,
  and what the actors are shown stays the log as it was when the scene was planned
- **Story Stage keeps someone on stage.** Visibility was strictly per line: the sprite
  faded out two seconds after each one, and the opening is narrated by a voice with no
  sprite of its own, so a participant met a bare backdrop and saw no character at all
  until they had typed and their own character spoke. Whoever is on stage now stays
  standing between lines, a narrator no longer clears the stage — the audio visualiser
  stands in only when nothing else is there — and the stage opens with the local player's
  own character, or the first cast member with art, already present
- **The waiting animation now shows for the whole wait.** It was triggered on the single
  frame the AI became busy and skipped that frame while a line was still on screen, so a
  turn where generation started while the previous line was still being spoken showed no
  sign of working at all — exactly the turns that wait longest
- **An actor's line is no longer discarded for being a few words too long.** A scenario
  can set a word ceiling and ask for a reprompt rather than truncation; when the
  reprompted line was still over, the line was dropped and the character said nothing.
  Ireti Okan's 30-word ceiling and a verbose model met exactly that, turn after turn.
  Length is the one rule repairable without another model call, so a still-long line is
  now cut at a sentence boundary and kept — a rejected line costs the scene its turn,
  which reads as a broken session
- **The lull protocol's tier flags now actually reset**, so a second silence escalates
  like the first. Resetting them assigned an untyped array literal through a dynamic
  property reference, which the engine rejects rather than converts: every reset failed
  with a script error and left the flags as they were, so tiers that had already fired
  stayed fired for the rest of the session
- **Story Stage no longer goes black for scenarios without their own backdrop art.**
  Resolving a scenario backdrop fell through to a placeholder image that happens to be
  pure black; because it loaded successfully, it silently overwrote the background the
  scenario declared, and nothing reported a failure. A resolver that finds nothing now
  returns nothing, and the declared background stands
- **Stage features built for one scenario no longer run in all of them** (ADR 0027).
  The tiered lull protocol — slideshow, breathing arcs, murmurs, replay of the opening
  — and the vis_story background slideshow are opt-in, declared by `[LULL_PROTOCOL]`
  and `[VIS_STORY]`. They exist so an unattended installation never looks dead, which
  is the opposite of what a facilitated session wants from a pause
- **A character chosen in one scenario is no longer carried into the next.** It was
  announced as "You are playing as …" in a scenario that character has nothing to do
  with, and — worse — used to attribute typed input in the story log, crediting a line
  to a cast member from elsewhere. A session role, facilitator or participant, is not
  scenario cast and still persists
- A scenario with no human player, driven by external input, now names that input
  source in the header instead of reporting missing character information as an error
- **A session role no longer follows a person from a workshop into a story.** It
  outlives a scenario change on purpose — a facilitator stays the facilitator — but
  "Facilitator" is a *system voice* in Story Catalyst, so carrying it across attributed
  the human's own typed lines to the system and the cast never answered them. A role now
  belongs to its session type as well as outliving the scenarios within it. Declining to
  answer a sender also says so in the log now, since a deliberate silence and a model
  that never replied looked identical from outside
- The header no longer describes the session type the scene was built for after a
  scenario switch crosses into the other one — Workshop Catalyst chrome, Session Record
  tab and all, over a Story Catalyst session
- One resolver now decides who a typed line is from, for both the session and Story
  Stage, so the same line cannot be credited to two different speakers depending on
  which view it was typed in. It also treats *both* of the network's "unknown" names as
  unknown; checking only one wrote "Unknown Peer" into the story log as an author
- The session header no longer keeps its placeholder text when a scenario resolves
  after the scene has loaded. The refresh existed but was never connected to
  `Global.scenario_changed`, so a slow load, a host's synced choice or a mid-session
  switch left "Scenario Label" on screen for the rest of the session
- Story logs are no longer written into the project source tree when the system
  Documents directory cannot be resolved; the fallback is app_userdata, matching the
  sibling resolver. A session record is user data
- A hub run **from source** no longer writes a second log into `services/hub/` inside
  the repository. That path exists for packaged builds, where a user expects logs
  beside the service, and is now gated accordingly

### Excluded from the repository

Recorded here because a fresh clone is affected. `.gitignore` says which and why.

- **LimboAI binaries** (~130 MB), required before the project opens cleanly.
  Published upstream under MIT; the pinned version is in `addons/limboai/version.txt`
- **Story Stage character art** (545 MB), entirely optional, installable with the
  content-pack tool
- ReadyMade's Found Concepts **source texts**, withheld deliberately (ADR 0024)
- One workshop scenario from the pilot, withheld deliberately
