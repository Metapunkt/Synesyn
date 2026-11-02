# Building on Synesyn

Synesyn is a shared infrastructure with applications built on top of it. ScenSyn and
ReadyMade are two of such applications, which show **what it can be used for**. They are examples and not templates for how it must be
used. This page covers extending it, from simply adding a scenario (which needs no code) to
starting an application of your own.

## The layers, and the one rule

| Layer | Where | Depends on |
| --- | --- | --- |
| **Applications** | `synesyn_client/ScenSyn/`, `synesyn_client/readymade/`, yours | Addons, freely |
| **Product addons** | `addons/syntree`, `synaxes`, `synpunkt`, `metapunkt`, `syntree_voice`, `story_stage` | `synesyn_core` only |
| **Shared library** | `addons/synesyn_core` | Nothing in the project |
| **Hub** | `services/synesyn_hub/` | Nothing in the client |

The rule is that **dependencies point downward and never sideways**. An
application may use any addon. An addon reaches shared behaviour through
`synesyn_core` rather than through another product addon. Nothing in an addon
depends on an application.

This is what makes the infrastructure reusable at all: a product addon plus
`synesyn_core` should drop into a clean Godot project and work. If that stops
being true, the boundary has been breached somewhere.

### What `synesyn_core` gives you

While ADR 0017 describes this in full, find below an outline:

- **Config and policy** — runtime configuration, provider-mode policy
- **Hub client** — transport and the endpoint facade, so you never hand-roll HTTP
- **Theme** — theme configuration and manager, soft-loading host theme packs
- **Render** — the versioned render request contract, Comfy client, render service
- **Graph workspace** — shared graph editing surface
- **Hub deployment** — locating a hub, rendering hub errors for humans
- **Shared vocabulary** — e.g. Closure Map quadrant definitions, read by both
  SynAxes and ScenSyn so the two cannot disagree about what a quadrant means

If you need something from this list, take it from `synesyn_core`. If you need
a variation of one of them, put that variation in `synesyn_core` and contribute
it, so the next application can use it too.

### Two rules that bite

**Never reference a project autoload by bare identifier inside an addon.**
`ContentBus.foo()` compiles in the editor, where autoloads are always live, and
fails in a fresh drop-in project or in headless tooling that loads scripts before
autoloads register. Resolve through the scene tree at use time, via
`addons/syntree/scripts/autoload/syntree_autoloads.gd` for SynTree-owned autoloads
or `addons/synesyn_core/scripts/synesyn_autoload_access.gd` for host autoloads.
Never cache the result in a field — an autoload that registers later would leave
your cached value null forever. This is enforced:

```bash
python utilities/checks/check_addon_autoloads.py
```

**Keep files small.** A script over 900 lines raises a warning, and one over 1,200
fails. `utilities/checks/check_line_limits.py` also stops a file that is already over
900 lines from growing past its recorded size. See
[`CONTRIBUTING.md`](https://github.com/Metapunkt/Synesyn/blob/main/CONTRIBUTING.md).

---

## Extending ScenSyn

There are four ways to extend ScenSyn, each entailing more work than the last. Use the cheapest
one that does the job.

### 1. Add a scenario (no code)

Scenarios are plain `.txt` files with bracketed sections. Write one, place it in
the right collection directory, and register it:

```
res://ScenSyn/session_types/story_catalyst/<collection>/scenarios/<name>.txt
res://ScenSyn/session_types/workshop_catalyst/scenarios/<name>.txt
```

See [workshop scenario authoring](workshop-scenario-authoring.md) for the Workshop
Catalyst agenda contract, and [Story Catalyst](../user-guide/story-catalyst.md) for
the narrative sections.

For **Open Play** you can skip registration entirely: author in the application and
save to your personal library under `Documents/Synesyn/`.

#### Stage features are opt-in (ADRs 0027, 0030)

Story Stage can do considerably more than show a backdrop and a speaking character,
but only for a scenario that asks. Declaring a section switches its feature on; saying
nothing leaves it off. A declared section can still be switched off with `enabled: false`.

| Section | What it turns on |
| --- | --- |
| `[LULL_PROTOCOL]` | Silence escalates through a slideshow, breathing arcs, murmurs, then a replay of the opening. Built for an unattended installation. In a facilitated session it will speak over a room that went quiet on purpose |
| `[LULL_MURMURS]` | The lines the murmur tier speaks |
| `[VIS_STORY] enabled: true` | Per-turn image rendering, and the background slideshow those images feed |
| `[AMBIENT_SOUND] enabled: true` | Ambient audio over OSC, following the narrative phase |
| `[PLAYER_AUTO_INPUT]` | Turns driven by external input rather than a person, which also skips character selection |
| `[STAGING]` | Stagecraft cues (`stage_cues` on log entries): named marks, gaze, expressions, gestures, cue light, and `talking_big` at high intensity |
| `[CHARACTER_MOTION]` | Highest motion rung requested (rung 1 audio-bus response is the default; rung 3 adds `Skeleton2D` head tilt and shader blink/breath) |
| `[VIS_PORTRAIT]` | Generated portrait frame sets or per-line clips via the `StoryStageImagery` port |
| `[STAGES]` | Stage topology: `shared` (default) or per-character `SubViewport` / `Window` slots |

Backdrops are opt-in too, but you add files instead of declaring a section. Drop one or
more PNGs in `story_stage/sprites/<collection>/<scenario>/background/` and they become
the scenario's backdrop, animated if there are several. Without them, the `.txt`
scenario's own `default_background` stands. The stage does not invent a backdrop when
the scenario supplies none.

#### How tight a word ceiling to set

`[SYSTEM_CONFIG]` takes `max_words_brief` and `max_words_default`, and
`reprompt_on_excess` chooses what happens when a line overruns: truncate it locally, or
spend a second model call asking for a shorter one. Set the ceiling to what the model
can actually hit in character. A ceiling far below what a scenario's personas invite
means most turns get reprompted, which doubles the calls and the latency for every one
of them. If the shorter version still overruns, it is truncated, not dropped. A tight
ceiling costs pace, not dialogue, and in a staged scene pace is most of what you have.

`reprompt_on_excess` carries a tolerance of a quarter over the ceiling
(`ActorAgent.REPROMPT_TOLERANCE`). A line a few words over the ceiling is cut at a
sentence boundary without another call. Only a line running well past the ceiling,
far enough that cutting would lose the end of a thought, is sent back. So the ceiling
is the length you want and the tolerance is what you will accept to keep a turn moving.

#### What a turn spends its seconds on (ADR 0028)

Most of the wait is the model. A provider's **non-reasoning** model answers in about a
second, where its reasoning models take five to twenty seconds. Switching to one brought
an Ireti Okan turn down from 15.6s to between 3.3s and 8.5s. Compared on the same cue, the
fast model kept the cast's register and argument, though its lines were a little more
literal. When pace matters, select a non-reasoning model in Settings, and check the lines
afterwards, not just the timing. That choice belongs to whoever runs the session. No
bundled scenario overrides it, although a scenario can (see below).

A turn is a sequence of model calls: one director call that writes a cue per speaker, then
one actor call per speaker, plus a repair call for any line that overruns. Each is a
round trip, so the wait is their sum. Two lines in the Godot log account for it.
`[budget]` records each call, with the prompt size, the model and the seconds. `[turn]`
records each turn, with the time to the first line and to the last.

The director's cues and the repair already use a low reasoning budget. Participants never
see the cues, and the repair only restates a line more briefly. First takes are left
alone, because that is the writing. `[SYSTEM_CONFIG]` overrides both per scenario:

| Key | Effect |
| --- | --- |
| `director_reasoning_effort: default` | Hand the cue batch back to the provider's own budget |
| `actor_reasoning_effort: low` | Spend less thinking on each spoken line, at some cost to the line |

Only providers that accept the setting receive it (today, xAI). Elsewhere it is ignored.

A scenario can pin its models with `director_model` and `actor_model`. A pin silently
overrides the participant's selection, and the session transcript then names a model they
never chose. Keep a pin for a scenario that cannot work otherwise.

The model must be one the client lists for that provider (for xAI, `xai_model.gd`). An
unlisted id is treated as a local Ollama model. The call fails at once and the fallback
line is used. If routing seems to do nothing, check the list first. `[budget]` names the
model each call actually went to.

Two other things affect the wait: how many speakers a turn plans, and how long the lines
are, because Story Stage finishes speaking each line before it shows the next.

Which model spends what, and what the fast one costs in register, is recorded in
[ADR 0028](../architectural-decisions/0028-internal-calls-get-a-low-reasoning-budget.md).

### 2. Register a scenario or collection

The registry lives in `synesyn_client/ScenSyn/scripts/Global.gd`. A scenario that
is not registered will not appear in the launcher, even if the file exists. A few such
unregistered files are already in the repository.

Adding a **scenario** means one edit: append its file stem to the right collection
list in `SESSION_TYPE_COLLECTIONS`.

Adding a **collection** means four edits:

| Constant | What to add |
| --- | --- |
| `SESSION_TYPE_COLLECTIONS` | Your collection id, with its list of scenario stems |
| `SESSION_TYPE_MANAGER_PATHS` | A `res://` path to the collection's metaprompt manager script |
| `COLLECTION_DISPLAY_NAMES` | The label shown in the dropdown |
| `wip_scenarios` | Optionally, stems to mark with a "⚠ WIP" prefix |

The **metaprompt manager** is what makes a collection distinct. It turns the
scenario's framing into the instructions the model receives each turn. The
existing three under `session_types/story_catalyst/*/` are the reference. The Open
Play one is the simplest place to start, since it deliberately adds no didactic
overlay.

Then run the registry test, which checks that every session type, collection and
manager path resolves:

```bash
godot --headless --path synesyn_client \
  --script res://ScenSyn/tests/test_session_type_registry.gd
```

### 3. Add a session type

A session type is a different kind of session, not a different topic. Register it
in `SESSION_TYPE_ORDER` and in the first three constants of the table above, and the
selector will offer it.

Be realistic about the rest. There is **no session-type plugin API**: Workshop
Catalyst and Story Catalyst share the scenario loader, character rotation, the
story log, voice and artifact storage, but Workshop Catalyst also brings its own
controller, workspace shell, session record, Thinking Map and Compare Paths. That is some
16,000 lines, because a workshop that works toward a decision needs different machinery
from a story that rehearses one. How much you must
build depends entirely on how much of that shape you need.

If your idea is closer to "these scenarios ask something different of the room"
than to "a session works differently here", it wants a **collection**, not a
session type. That is the cheaper and usually the right answer.

### 4. Build your own application

If what you want is not a ScenSyn session at all, add an application instead.
`synesyn_client/readymade/` is the worked example: a self-contained directory with
its own entry scene. It uses Metapunkt, SynTree and LimboAI without modifying any
of them.

The pattern to follow:

1. **Your own directory** under `synesyn_client/`, with your own entry scene.
2. **Consume addons; never edit them** to suit yourself. If an addon does not
   expose what you need, propose the change instead (see
   [Contributing back](#contributing-back)).
3. **Use `synesyn_core`** for configuration, hub access, themes and render
   requests rather than reimplementing them.
4. **Register your entry point** in the launcher
   (`synesyn_client/scripts/synesyn_launcher.gd`) so it can be opened alongside
   ScenSyn and ReadyMade.
5. **Decide whether you need the hub.** It is optional. If it is missing, say so
   plainly instead of failing in a way the user cannot follow. `hub_error_text.gd`
   exists to turn hub problems into messages a user can read.

Read `synesyn_client/readymade/README.md` before starting. It is candid about what
that application does and does not do, and it documents the one-way dependency in
practice.

#### Putting lines on a Story Stage

`addons/story_stage` is the stage ScenSyn sessions play on: sprites that talk while their voice plays,
scenario backdrops, the slideshow, the lull protocol, voice. It knows nothing about
ScenSyn. It asks a **host** for everything it needs to know about the session. A host is a
subclass of `StoryStageHost` (ADR 0029). An application that can say "this speaker says this line"
can use the stage by writing one. The
[Story Stage functional specification](story-stage-functional-specification.md)
is the contract for that host surface, and for a from-scratch replacement of the addon.

The base class answers every question with a safe default: no session, no story log, no
voice, no art, no optional features. A host overrides only the answers it can give. The smallest
useful one supplies the lines:

```gdscript
extends StoryStageHost

var lines: Array = [
	{"sender": "Didi", "message": "Are we waiting for someone?"},
	{"sender": "Gogo", "message": "We always are."},
]

func has_session() -> bool:
	return true

func get_story_log_entries() -> Array:
	return lines
```

Hand it to the stage **before** the stage enters the tree:

```gdscript
var stage := preload("res://addons/story_stage/scenes/story_stage.tscn").instantiate()
stage.host = MyHost.new()
add_child(stage)
```

The stage shows each entry it has not shown yet, holding it until its voice finishes or it
has been on screen long enough to read. Append an entry and emit `story_log_changed` to add a line. A stage opened by
`change_scene_to_file` cannot be handed a host, so it loads the script named by the
`story_stage/default_host_script` project setting; ScenSyn sets that to
`ScenSynStageHost`.

Other methods to override, depending on what you want the stage to do:

| To have | Override |
| --- | --- |
| Character art | `get_sprite_roots()`: folders holding one folder per character slug, each with `idle/` and `talking/` frames (plus optional `talking_big/`, `<expression>-idle/`, `<expression>-talking/`, and `mouth/` visemes). A speaker with no art is drawn by the spectrum visualiser |
| A backdrop | `get_scenario_art_dir()` and `get_backgrounds_dir()`, or `get_scenario()` with a `default_background` |
| Speech | `create_voice()`, returning a `StoryStageVoice`. `SyntreeStageVoice` speaks through `syntree_voice` |
| Generated stage imagery | `create_imagery()`, returning a `StoryStageImagery` port for backdrops, portrait frame sheets, and line clips |
| Scenario features (lull, ambient, staging, motion, topology) | `get_scenario()`, returning the parsed sections ADRs 0027 and 0030 describe, and `set_granted_capabilities()` to receive what the stage granted |
| Hamburger-menu controls | `supports(feature)`. The stage hides every control whose feature the host does not support |
| Typed or spoken input from the participant | `supports(FEATURE_TYPED_INPUT)`, `commit_local_line()` and `get_local_speaker_name()` |

`synesyn_client/playback/` is the worked example. Its `StoryLogPlaybackHost` replays a
saved story log with no session, model or hub. It reads the art and voice routing from the
log's `.provenance.json` sidecar, and it paces the lines by letting them onto the stage one
at a time.

Two checks hold the boundary. `check_story_stage_boundary.py` fails if the addon names a
project autoload, a class declared outside it or a `res://` path outside it.
`story_stage_dropin_test.py` builds a temporary Godot project containing only
`story_stage` and `synesyn_core` and plays three lines in it.

---

## Contributing back

**Improvements to the infrastructure are worth more than improvements to any one
application**, because every future application benefits from them.

The most useful signal you can send is friction. If building on Synesyn made you:

- reach across a boundary the layering says you should not,
- copy code out of an addon because it was not exposed,
- work around a missing extension point, or
- re-implement something `synesyn_core` nearly provided,

then the infrastructure has a gap worth filling. An issue describing what you were trying to do
is useful even without a patch. Design rationale lives in the
[ADRs](../architectural-decisions/README.md). If you disagree with a boundary, argue
your case against the ADR that set it. If the decision is reversed, the reversal and
its reasons are recorded as well.

Before proposing a change:

```bash
python utilities/checks/check_addon_autoloads.py
python utilities/checks/check_doc_paths.py
python utilities/checks/check_story_stage_boundary.py
python utilities/checks/story_stage_dropin_test.py
cd services/synesyn_hub && python -m pytest tests/
```

[`CONTRIBUTING.md`](https://github.com/Metapunkt/Synesyn/blob/main/CONTRIBUTING.md)
has the full expectations, including the line-limit policy and what must pass
before review.

---

## See also

- [Architecture](architecture.md) — how the pieces fit at runtime
- [Code map](code-map.md) — where things live
- [ADR 0017](../architectural-decisions/0017-synesyn-core-shared-library-addon.md) — the shared-library boundary
- [Artifacts and schemas](artifacts-and-schemas.md) — the artifact contracts you will be writing against
- [Local development](local-dev.md) — getting the client and hub running
