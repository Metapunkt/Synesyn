# ScenSyn — the session runtime

ScenSyn is a session runtime built on the Synesyn infrastructure, and the most
developed application in the project. It runs **sessions** where a scenario sets the
frame, participants work with an AI cast or with specialist analysis running in
the background, and everything said is recorded with attribution and provenance.

This page covers what the two session types share. For running a workshop, go to
the [Workshop Catalyst facilitator manual](workshop-catalyst-facilitator-manual.md).
For narrative work, go to [Story Catalyst](story-catalyst.md).

---

## How ScenSyn is organised

ScenSyn is organised at three levels - described with terms that matter because they appear
throughout the interface:

| Level | Meaning | Examples |
| --- | --- | --- |
| **Session type** | The kind of session, and what it is for | Workshop Catalyst, Story Catalyst |
| **Collection** | A group of scenarios of a similar kind within a session type | Decision Triage; Sustainability; Cultural Narratives; Open Play |
| **Scenario** | One specific situation, with its own cast and framing | *Karlsruhe Library Future Design*; *Ireti Okan* |

You choose for all three, in that order, when starting a session.

## The two session types

Both session types run inside ScenSyn and share scenario loading, character
rotation, the story log, voice and artifact storage. They differ in what a
session is *for*, and therefore in the role the AI plays.

### Workshop Catalyst — deciding

A facilitator runs a timeboxed workshop through a staged agenda. AI specialists
analyse contributions **out of sight** and surface structure — claims, causes,
risks, options — rather than performing as characters. The session is judged by
whether the group leaves with a defensible decision record.

Collection: **Decision Triage**. This is the most developed and most thoroughly
tested part of the project. See the
[facilitator manual](workshop-catalyst-facilitator-manual.md).

### Story Catalyst — rehearsing

An ensemble of characters speaks **in their own voices**, optionally staged
visually with sprites and synthesised speech. The point is rehearsal, resonance
and cultural specificity rather than a decision record.

Collections: **Sustainability**, **Cultural Narratives** and **Open Play**, which
differ in what they ask of participants. See [Story Catalyst](story-catalyst.md).

---

## Story Log and Story Stage

Both session types run through the **Story Log**, a text record of the session.
Story Catalyst can additionally open the **Story Stage**, a 2D visual view.

### Story Log (text)

AI turns are generated from the scenario's framing and the conversation so far.
Every turn is logged with a timestamp, the speaker, and provenance for the model
that produced it. Use it for solo exploration, for text-first facilitation on a
shared screen, and for reviewing an earlier session.

### Story Stage (visual)

Characters appear as sprites, dialogue is spoken through TTS, and scene
transitions give the session a performed quality. Use it for staged sessions and
for presentation.

It helps to be clear about what is
generated live and what is pre-drawn in Story Stage. The dialogue, the voices, and the choice of
who speaks next are generated during the session. The artwork is authored ahead
of time. Each character has at least two short hand-made frame loops, one for idle and one
for talking (plus optional `talking_big`, expression variants, and a `mouth/` viseme sheet), and the stage switches between them as the voice starts and stops.
While a character speaks, their voice runs through a dedicated audio bus so portrait bob, stage lighting, and optional visemes respond to the actual spoken audio (with scenarios also able to opt into `[STAGING]` cues, `[CHARACTER_MOTION]` breathing/blinking, and `[VIS_PORTRAIT]` sheets). The
backdrop stays on the scenario's default image unless the scenario enables the
generated slideshow (`[VIS_STORY]`) or you trigger a render from the menu. In a
video recording, the stage on its own can therefore look like a pre-rendered
loop. Show the Story Log beside it when you want viewers to see that the dialogue
is being generated live.

Bundled character art exists for the two Cultural Narratives scenarios (*Ireti
Okan* and *Stochastic Dreams*). Because those sprite frames total 545 MB, they
ship as an optional download rather than in this repository. See
[Story Stage sprite packs](story-stage-sprites.md) to install them or supply your
own art. A fresh clone still runs full sessions in Story Stage without them; any
speaker without sprites is shown with the spectrum visualiser.

3D staging is not implemented. The current stage is 2D.

### Replaying a saved session

Every session's Story Log is saved as it goes, and **Play a Story Log** on the
launcher puts a saved one back on the stage. No live session, model or hub is
needed, so a finished performance can be shown again or left looping in an
exhibition.

- **Open** a log from `Documents/Synesyn/scensyn/story_logs/`.
- **Pace**: *Reading* moves on once a line has been spoken or read. *Original*
  keeps the gaps the session actually had, capped at twenty seconds. *Manual* waits
  for **Step**.
- **Speed** runs from half to four times. **Loop** starts again after the last line.
- Voices are spoken when a voice service is available, with the session's voice
  settings.

A log saved by this version records its scenario, so the player uses that
scenario's backdrop and character art. An older log still plays, with each speaker
drawn as a visualiser; the sprite-folder button lets you pick art by hand.

---

## Scenario files

Scenarios are plain `.txt` files with bracketed sections, so authoring one needs
no code:

```
res://ScenSyn/session_types/story_catalyst/<collection>/scenarios/<name>.txt
res://ScenSyn/session_types/workshop_catalyst/scenarios/<name>.txt
```

Common sections include `[SCENARIO]` for the framing, `[CHARACTERS]` for the
cast, `[CONTEXT]`, `[GAMEPLAY]`, `[ABOUT]` and `[HOW_TO]`. Story Catalyst
scenarios may add `[PHASE_GUIDANCE]`, `[VOICES]` and dramaturgical sections;
Workshop Catalyst scenarios add `[WORKSHOP_AGENDA]` defining the stages.

A scenario must be registered before it appears in the launcher. Authoring and
registration are covered in
[workshop scenario authoring](../developer-guide/workshop-scenario-authoring.md)
and, for the registry itself,
[building on Synesyn](../developer-guide/building-on-synesyn.md).

Open Play is the exception: it is built for scenarios you write yourself and save
to your personal library under `Documents/Synesyn/` rather than into the
repository. See [Story Catalyst authoring](story-catalyst-authoring.md).

---

## AI model selection

ScenSyn selects its model through the hamburger menu (☰) in the Story Log or
Story Stage. Changes apply to subsequent requests.

ScenSyn's model choice is kept **separate** from SynTree's, so switching models
in the assistant dock does not change the model running your session. A scenario
file can also pin a model for the director or the cast.

---

## Voice

Each character can be mapped to a voice, with optional rate, pitch and volume
adjustments. Mappings come from the scenario's `[VOICES]` section and from
`Documents/Synesyn/synesyn/syntree_voice/character_voices.json` (an older
`user://syntree_voice/character_voices.json` file is migrated automatically on
first read).

Voice runs either through the hub's voice service or, for testing, a separate
local voice server, and character mappings work the same way in both. Note that
the default voices are Microsoft's Edge voices, which means spoken text leaves
your machine — see [privacy and data](privacy-and-data.md).

---

## Renders from Story Stage

ScenSyn can enqueue SynPunkt image-generation jobs without interrupting a
session. In Story Stage, open the hamburger menu (☰) and look for **Synpunkt
renders (async)**, which can generate a background image, a portrait of the
current speaker, or a prop card.

These actions only **submit** jobs. They never block dialogue or speech, and
results arrive as hub artifacts (usually `image.generated`) with provenance.

### Generated sprites

Completed portrait renders can be saved into the active workspace so that Story
Stage picks them up as character sprites:

```
<workspace_root>/scensyn/sprites_generated/<collection>/<scenario>/<character>/<frames>/0001.png
```

`<frames>` is the animation folder name already used for sprites, such as `idle`
or `talking`. Workspace-generated sprites take priority over packaged ones.

### Making render presets discoverable

ScenSyn chooses a workflow by reading **tags** on SynPunkt workflow presets
(`json.workflow` artifacts). To tag one, open SynPunkt → Render, fill **Preset
Tags**, and save. Include at least:

   - `scensyn:render_purpose=background` (or `portrait`, `prop_card`)

Optionally narrow a preset with `scensyn:collection=<id>`,
`scensyn:scenario=<scenario_key>` or `scensyn:character=<character_slug>`.
ScenSyn looks first for a preset matching both the scenario and the collection,
then the collection alone, and finally any preset tagged with that purpose.

---

## What a session produces

Every session writes versioned artifacts into the workspace:

- **Story logs** — turns with attribution, timestamps and model provenance
- **Transcripts** — when speech-to-text is enabled, captured with consent
- **Generated images** — with the prompt, model and closure they came from
- **Workshop records** — session summaries, decision records and path sets,
  committed explicitly by the facilitator

Artifacts managed by the hub live under
`Documents/Synesyn/Workspaces/<workspace_slug>/artifacts/`. Story logs the client
writes directly live under `Documents/Synesyn/scensyn/story_logs/`.

---

## Why "generative theatre"

ScenSyn treats scenario work as **embodied rehearsal** rather than branching
fiction. The principles behind that:

- **Plural futures** — scenarios provoke rather than predict
- **Cultural specificity** — grounded in particular contexts, not generic futurism
- **Collective sense-making** — the discussion after a scene is the point
- **Forward Remembrance** — treating futures as emerging from archetypes and
  desires already present in cultural archives

---

## Current state

**Working:** the Story Log for both session types; Workshop Catalyst's full
facilitated runtime, records and exports; Story Stage (with character sprites or
the spectrum visualiser); replaying a saved Story Log on the stage; model
switching; voice with character mappings.

**Limits worth knowing before you plan a session:**

- Bundled character art covers two scenarios and is an optional download
  ([sprite packs](story-stage-sprites.md)); without it, Story Stage draws
  speakers with the spectrum visualiser
- 3D staging is not yet implemented
- A workshop runs on one device; remote participants and implementation of multi-client
  synchronisation is deferred for the time being, and the Invite system is still yet to be implemented.

---

## See also

- [Story Catalyst](story-catalyst.md) — the three narrative collections
- [Workshop Catalyst facilitator manual](workshop-catalyst-facilitator-manual.md) — running a workshop
- [Metapunkt](metapunkt.md) — the orchestration underneath ScenSyn's AI, voice and rendering
- [SynPunkt](synpunkt.md) — the canvas and render surface Story Stage draws on
- [Getting started](getting-started.md) — first-time setup
- [Building on Synesyn](../developer-guide/building-on-synesyn.md) — adding a session type, collection or application
