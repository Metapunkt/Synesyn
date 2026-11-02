# 0030 — Story Stage motion and imagery are coordinated opt-in layers

- **Status:** Proposed
- **Date:** 2026-09-24
- **Area:** client, hub

## Context

A reviewer watching Ireti Okan on Story Stage found the conversation convincing and the
picture not: "more like a loop of pre-generated frames than a dynamic or responsive
system". That is an accurate description of what the stage does today.

- Characters are authored loops played at 5 fps: three to ten idle frames, three
  talking frames. The stage chooses who is shown and switches between idle and talking.
- In hub mode the talking loop's speed and bob follow a mouth-open curve, but the hub
  estimates that curve from the text of the line (`app/voice/lipsync.py`), not from the
  audio. The frames themselves never change.
- Responsive code exists and does nothing. `talking_big` sprites are never selected.
  Expressions are inferred from keywords, but no scenario has expression folders.
  `BackgroundController.process_ai_response` has no caller on the live path and
  `send_phase` has no callers at all.
- Stochastic Dreams opts into `[VIS_STORY]`, `[LULL_PROTOCOL]` and `[AMBIENT_SOUND]`;
  Ireti Okan opts into none of them, so the one generative visual system in the client
  never runs there.
- VIS_STORY (per-turn ComfyUI renders shown as a slideshow behind the characters) lives
  in ScenSyn, not in the Story Stage addon, so other hosts of the stage cannot use it.
- ADR 0029 made the stage host-driven but left its caches and character registry as
  process-wide statics, so two stages in one program still collide.

The documentation now describes the stage as it is ("a talking animation timed to the
voice"). The question this ADR answers is how to make the stage itself visibly
generative for any scenario, while staying light enough to run, configure and maintain
by one person, and without closing off a 3D stage later.

## Options considered

1. **Narrow the claim and stop there.** Already done for the documentation. As the
   whole answer it concedes the point the work is meant to make.
2. **A streaming avatar service** (StreamDiffusion, or hosted real-time avatars such as
   ACTx486). Latency, GPU cost and an external dependency on the critical path of a
   live performance. It would also be the one part of the stage nobody here can repair.
   It stays reachable later behind the same port as rung 4 below, but is not built.
3. **A custom fine-tuned avatar model.** Training data, training runs and a model to
   maintain across driver and framework updates, for a gain the existing open models may
   already deliver. Revisit only if the spike below shows identity loss that an adapter
   (a LoRA on the portrait style) would fix.
4. **Coordinated opt-in layers with a motion ladder.** Each visual capability is a
   layer a scenario asks for, the stage grants what its host and machine can support,
   and motion climbs from cheap to expensive rungs with a working fallback at every
   step. Chosen.

## Decision

Option 4.

### Layers and the scenario sections that request them

Sections follow ADR 0027: a section `[X]` in the scenario file becomes `scenario["x"]`
and is read with `scenario_section_enabled("x", default)`. Every layer is off, or at its
current behaviour, unless the scenario asks.

| Layer | Section | What it decides | When absent |
| --- | --- | --- | --- |
| Topology | `[STAGES]` | one shared stage, or one stage per character; which window or viewport each occupies | one shared stage |
| Cues and stagecraft | `[STAGING]` | whether the director writes cues for each line, and how the stage realises them (marks, gaze, light, transitions, `talking_big` by intensity) | speaker selection only |
| Motion | `[CHARACTER_MOTION]` | the highest motion rung wanted, and its settings | rung 0 |
| Scene imagery | `[VIS_STORY]` | generated backdrops per turn, as today | none |
| Portrait imagery | `[VIS_PORTRAIT]` | generated portrait frames or clips from the scenario's own sprites | authored sprites only |

### Coordination runs both ways

What a layer does is the intersection of three things: what the scenario requests, what
the host declares through `StoryStageHost.supports()`, and what is available when the session
starts (a hub, a reachable ComfyUI, a model on it). A layer that cannot have its
requested rung steps down one rung at a time until one works, and the stage logs the
reason once.

The stage also reports back. The host passes the granted capabilities to the director,
so the model only writes cues the stage can show. For example, with one stage per
character there is no shared floor to cross, so "turn to Didi" becomes a turn toward
the edge of the stage nearest Didi's window, and "walk to the window" is not offered at
all. Each story-log entry records which rung rendered it (the provenance sidecar's stage
block from ADR 0029 gains the fields), so a replay knows what the audience saw and a
reviewer can check what was generated and what was authored.

### A renderer-neutral cue vocabulary

When `[STAGING]` is on, each story-log entry may carry a `stage_cues` object:

| Field | Meaning |
| --- | --- |
| `speaker` | character id |
| `target` | character id or mark the speaker addresses or looks at |
| `expression` | named expression (`neutral`, `concern`, `delight`, ...) from the character's profile |
| `intensity` | 0 to 1; selects `talking_big`, scales motion and light |
| `gesture` | named gesture from the character's profile |
| `mark` | named position on the stage |
| `stage_id` | which stage, when `[STAGES]` gives each character its own |
| `at` | seconds from the start of the line's audio at which the cue applies |

Cues name things; they never carry pixels, frames or file paths. The same log drives a
2D stage, a 3D stage or a replay, and a presenter ignores what it cannot show.

### The motion ladder

| Rung | What moves | Where it is computed | Cost |
| --- | --- | --- | --- |
| 0 | authored idle and talking loops | client | none (today) |
| 1 | mouth and bob follow the actual audio; visemes when the character has a mouth sheet | client, from the speaker's audio bus | negligible |
| 2 | in-between and expression frames generated once from the scenario's sprites, blended by cue | ComfyUI, before the performance (`[VIS_PORTRAIT]`) | offline |
| 3 | parametric 2D: blink, breath, head tilt by deformation and shaders | client | low |
| 4 | a generated talking clip for each line | ComfyUI via the hub, per line (`[VIS_PORTRAIT]`) | a GPU on the ComfyUI machine |
| 5 | continuous streaming avatar | not built | not built |

Rungs 1 to 3 need no new services. Rung 4 is gated on the spike in
`utilities/spikes/story_stage_motion/`, which runs SoulX-FlashHead on the ComfyUI machine
and measures the real-time factor, identity, lip-sync and compositing. At a warm
real-time factor at or below 1 a clip can accompany each line; up to 3 it can if lines
are generated one ahead; above 3 rung 4 is limited to offline portrait sheets and
re-rendered replays.

### Imagery is a port, and VIS_STORY's stage half moves into the addon

The addon gains a `StoryStageImagery` port, built like `StoryStageVoice`: it asks for a
backdrop for a cue, for a portrait frame set for a character, or for a clip for a line,
and receives textures or streams when they are ready. The addon ships a null
implementation. ScenSyn implements it over the existing VIS_STORY services and the hub's
`render.comfyui` job.

"Porting VIS_STORY to the addon" therefore means moving what the stage does with images
(the queue, the slideshow, `BackgroundController`, the transitions) into
`addons/story_stage`, and leaving generation behind the port, where the hub and ComfyUI
are. A playback host can then show a saved session's renders without any of ScenSyn.

### Hub support, added with this ADR

`render.comfyui` requests may now name `input_uploads` (artifacts the hub uploads to
ComfyUI's input folder before submitting, for a ComfyUI on another machine), may opt
into video and audio outputs with `output_routing.videos` / `.audio` (stored as
`video.generated` / `audio.generated` and listed as `media_artifact_ids`), and may set
`timeout_sec`. Requests that use none of these behave as before.

### Prerequisite: per-host registries

`[STAGES]` with one stage per character needs the process-wide statics in
`StoryStageCharacter`, `StoryStageHost` and `DynamicBackgroundManager` moved onto the
host or the stage instance. That work comes before any topology beyond one stage.

### Godot features the layers are built on

| Feature | Used for |
| --- | --- |
| A bus per speaker with `AudioEffectCapture` or `AudioEffectSpectrumAnalyzer` | rung 1 from the real voice; TTS plays on Master today |
| `AnimationTree` with `BlendSpace1D` / `BlendSpace2D` | blending idle, talking and expression frames by `intensity` and `expression` (rungs 1 and 2) |
| SpriteFrames ping-pong playback (4.7) | smoother loops and in-betweens from half the frames |
| CanvasItem shaders; `PointLight2D` with normal maps | blink, breath, glow in the cracked panels, dissolves; light that answers cues |
| `Skeleton2D` with weighted `Polygon2D` | rung 3 deformation of existing sprites |
| `SubViewport` per stage, `Window`, `ViewportTexture` | topology: separate stages, a second display, a stage used as a texture in a 3D scene |
| `VideoStreamPlayer` (Theora `.ogv` only) | rung 4 playback; clips are converted before play, or decoded to frames when a matte is needed |
| `AudioStreamPlayer.get_playback_position()` with `Tween` | firing cues at `at` seconds into the line |
| Movie Maker mode | recording a story-log replay frame-exact, as evidence of what the stage generates |

### What to build in now for a 3D stage later

1. **The cue vocabulary above**, with names instead of coordinates.
2. **A presenter interface separate from the stage core.** The core owns the line queue,
   cue timing and the host; a `StoryStagePresenter` shows a line, applies a cue, sets a
   mouth shape, sets gaze and plays a gesture. Today's sprites become the 2D presenter;
   a rigged character becomes the 3D one.
3. **A character profile Resource** (`StoryStageCharacterProfile`): id, display name,
   sprite sets, an optional 3D scene, and the character's expression, gesture and
   viseme maps.
4. **One viseme set for both.** The hub emits `mouth_a`, `mouth_e`, `mouth_m` and
   `mouth_s`, while `syntree_voice`'s `LipSyncAnimator` understands `mouth_e`, `mouth_s`,
   `mouth_o` and `mouth_u` and drives `mouth_open` / `mouth_wide` blend shapes on a
   `MeshInstance3D`. A single small set (rest, open, wide, round, lips closed, teeth) maps
   to 2D mouth sheets and to 3D blend shapes alike.
5. **Named marks.** Character positions, now computed in pixels, become named
   `Marker2D` nodes in the stage scene; a 3D stage uses `Marker3D` with the same names.
6. **Cue timing relative to the line's audio**, never to wall-clock or frame counts.
7. **The stage renders inside a `SubViewport`**, so a 2D stage can already appear as a
   surface in a 3D scene.

The 3D presenter can then use Godot's skeleton modifiers without changes to the core:
`LookAtModifier3D` for gaze (4.4), `SpringBoneSimulator3D` for hair and cables and
`BoneConstraint3D` (4.5), and the `IKModifier3D` family (4.6) for gestures.

## Consequences

- Any scenario can become visibly responsive by adding sections, and a scenario that
  adds none looks exactly as it does now.
- The story log becomes a record of staging as well as dialogue, so replays and
  recorded demonstrations show the generated behaviour rather than a description of it.
- Four more sections to document, and more ways a scenario can be misconfigured. The
  step-down rule and a single logged reason per layer keep a bad setting from breaking a
  performance.
- Per-host registries and the presenter split are refactors of working code, done
  before the features that need them and guarded by the existing Story Stage specs.
- Rung 4 depends on a GPU machine running ComfyUI with the FlashHead node and its
  weights. The stage never waits on it: a clip that is late or missing leaves rung 1 or 2
  on screen.
- Order of work: the hub support and spike (with this ADR); rung 1 and the cue vocabulary
  with the dormant code revived under `[STAGING]`; per-host registries and `[STAGES]`;
  the imagery port with VIS_STORY's stage half and `[VIS_PORTRAIT]` sheets; rung 4 if the
  spike passes. Status moves to Accepted when the spike's results are recorded.

The implementable contract for a from-scratch addon that follows this decision is
[`../developer-guide/story-stage-functional-specification.md`](../developer-guide/story-stage-functional-specification.md).

## Implementation status (2026-11-01)

- `synesyn_client/addons/story_stage/` has been refactored to implement steps 1–6 of the
  functional specification:
  - Per-stage `StoryStageCharacter` registries and `SubViewport` rendering (`StageViewport`).
  - `StoryStageMotion` (per-speaker audio bus with `AudioEffectSpectrumAnalyzer` routed
    through `ScenSyn` → `Master`) driving rung-1 speech level, portrait bob, `CueLight`
    energy, 16-band `StoryStageSpectrum`, and canonical visemes (`StoryStageViseme`).
  - `StoryStagePresenter` / `StoryStagePresenter2D` split, `StoryStageCuePlayer` firing
    `stage_cues` against audio playback position, named `Marker2D` stage marks, and
    `talking_big` selection at high intensity under `[STAGING]`.
  - `StoryStageImagery` port, `[VIS_PORTRAIT]` frame-sheet swap, and rung-3
    `Skeleton2D` + `portrait.gdshader` blink/breath deformation under `[CHARACTER_MOTION]`.
  - `StoryStageTopology` (`[STAGES]`) supporting shared or per-character `SubViewport` /
    `Window` slots, and `StoryStageCapabilities` granting rungs with step-down logging
    and stamping `motion_rung`, `imagery`, and `stage_id` onto presented log entries.
- Rung 4 remains gated in `StoryStageCapabilities` until a warm real-time factor is
  recorded from `utilities/spikes/story_stage_motion/`.
