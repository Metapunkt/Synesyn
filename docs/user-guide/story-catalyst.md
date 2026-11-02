# Story Catalyst

Story Catalyst is one of ScenSyn's two session types. An ensemble of AI characters
speaks **in their own voices**, working through a scenario that has been written
to provoke rather than to inform.

It is the counterpart to [Workshop Catalyst](workshop-catalyst-facilitator-manual.md),
and the difference is worth stating plainly, because it determines which one you
want:

| | Workshop Catalyst | Story Catalyst |
| --- | --- | --- |
| **The session is for** | Reaching decisions a group can defend | Rehearsing a situation and hearing how it sounds |
| **The AI** | Analyses out of sight and surfaces structure | Performs as named characters |
| **You leave with** | A decision record: decisions, risks, deferred questions | A story log, and whatever the room now understands |
| **Success looks like** | The group committed to something | Someone changed their mind about what matters |

Use Workshop Catalyst when a group must decide. Use Story Catalyst when a group
needs to feel the shape of a situation first — which is often the more useful
thing to do earlier.

For the shared runtime — Story Log, Story Stage, voices, models, renders — see
[ScenSyn](scensyn.md).

---

## The three collections

A **collection** groups scenarios of a similar kind. Story Catalyst has three,
and they differ in what the scenario asks of participants.

| Collection | Ask | Scenarios shipped |
| --- | --- | --- |
| **Sustainability** | Take a stakeholder position in a civic dilemma and argue it | 5 |
| **Cultural Narratives** | Enter a culturally specific world on its own terms | 2 |
| **Open Play** | Bring your own scenario | None — you write them |

### Sustainability

Near-future civic dilemmas, all set in and around **Trondheim, Norway**, across a
range of years. Each scenario convenes stakeholders whose interests genuinely
conflict — residents, industry, researchers, government, and in one case the
non-human party — and asks participants to hold a position rather than seek
consensus early.

| Scenario | The situation |
| --- | --- |
| **Hello Trondheim** | 2024–2035. Four AI systems do anticipatory foresight on the city's energy transition before it reaches crisis |
| **The Crisis — Goodnight Trondheim** | 2035. Severe energy shortage; communities, corporations and government negotiate a way through |
| **Energy Futures** | 2073. The city must decide whether to sell its wind technology, with Sámi rights advocates at the table |
| **The Windmill Syndrome** | Near future. An unexplained health condition around wind farms sets public health against energy policy |
| **The Revolt of the Salmon** | 2025. Genetically modified farmed salmon become sentient and begin making demands |

Discussion is tracked across five domains — **energy, community, innovation,
environment and equity** — by watching for their vocabulary in what is said. It
is a coarse instrument: read it as a prompt for "what have we not talked about?"
rather than as a measurement.

Scenarios may define narrative **phases**, so the framing shifts as a session
progresses rather than repeating one prompt.

*Hello Trondheim* is flagged work-in-progress. The other four are the more
settled path into this collection.

### Cultural Narratives

Culturally grounded pieces, scored more like theatre than like a discussion
prompt. Scenarios in this collection can carry relational and dramaturgical
matrices, phase guidance, voice assignments and constraints on how characters may
speak to one another.

**Ireti Okan: Awaiting an Awakening** — two parallel performance spaces joined by
a glitching oracle, the Tree Hive Interface, blending contemporary Yorùbá
traditions with Icelandic technological aesthetics. Characters await the
prophesied arrival of *Okan*, a transcendent AI consciousness, through repeated
failed awakenings. It negotiates human scepticism, traditional wisdom,
techno-capitalist power and emerging human-AI hybrid identity. This is the most
completely realised scenario in the project, and the one to open first if you want
to understand what generative theatre means here.

**Stochastic Dreams** — a divination piece set in the Oscillator's Court, where
participants place beads on a board to state an intent and a swinging pendulum
supplies the flux. Characters interpret the gap between the two to determine what
has changed in the Tapestry and what it cost. It is written as an **installation**
driven by physical input over a local network listener, so on a desktop without
that hardware you are running part of a larger work. It is flagged
work-in-progress.

### Open Play

No bundled scenarios, by design. Open Play is for scenarios **you** write: you
author a setting, a cast, plot twists and genre tags, save the result to a
personal library, and run it without any didactic overlay or tracking.

Drafts and saved scenarios live under your `Documents/Synesyn/` folder rather than
in the repository, so they are yours and survive updates. This is the fastest way
to try your own material, and a good way to work out whether a recurring idea
deserves to become a proper collection.

[Story Catalyst authoring](story-catalyst-authoring.md) walks through it: the
in-application Story Builder, what a story is made of, the saved file format if you
prefer a text editor, and how to share one.

---

## Running a session

1. Launch the client and open **ScenSyn**.
2. Choose session type **Story Catalyst**, then a collection, then a scenario.
3. The session opens in the **Story Log**. Characters take turns; you type into
   the same log.
4. Optionally open the **Story Stage** for the visual, spoken view.

Practical notes:

- **A model provider must be configured**, and turns take as long as the model
  takes. [Getting started](getting-started.md) covers setup.
- **Story Stage character art ships separately** as an optional download, because
  it is 545 MB. A fresh clone runs a full session either way; speakers without
  sprites are drawn with the spectrum visualiser until you install a
  [sprite pack](story-stage-sprites.md) or supply your own art.
- **Spoken output uses Microsoft's Edge voices by default**, so text leaves your
  machine. Tell participants, and see [privacy and data](privacy-and-data.md).
- Sessions are recorded as story logs under `Documents/Synesyn/scensyn/story_logs/`.

---

## Authoring a scenario

Scenarios are plain `.txt` files with bracketed sections, so no code is needed.
Beyond the common sections, Story Catalyst scenarios tend to use:

- `[CHARACTERS]` — the cast, with roles and motivations
- `[PHASE_GUIDANCE]` — how the framing should shift as the session progresses
- `[VOICES]` and `[VOICE_OVERRIDES]` — character-to-voice mappings
- Dramaturgical sections — director principles, pivot rules, poetics, dialogue
  guardrails, relationship rules

The most instructive thing you can do is read
`ireti_okan_awaiting_an_awakening.txt` in
`synesyn_client/ScenSyn/session_types/story_catalyst/cultural_narratives/scenarios/`.
It exercises nearly every section available.

To add a scenario to an existing collection, or to add a whole collection, see
[building on Synesyn](../developer-guide/building-on-synesyn.md). For Open Play you
need neither: author it in the application and save it to your library, as
[Story Catalyst authoring](story-catalyst-authoring.md) describes.

---

## Current state

Story Catalyst is **smaller and less tested than Workshop Catalyst**. Its shared
runtime is exercised by the session-type registry test and by end-to-end harness
specs for both the sustainability and cultural collections, and Open Play's
scenario contract has its own test. There is no per-collection test suite
comparable to Workshop Catalyst's, so expect rougher edges.

Known limits:

- Bundled character art is an optional download covering the two Cultural
  Narratives scenarios; without a sprite pack or workspace art, Story Stage
  draws speakers with the spectrum visualiser
- 3D staging is not implemented
- *Hello Trondheim* and *Stochastic Dreams* are flagged work-in-progress
- Stochastic Dreams assumes installation hardware to be experienced as intended
- Some scenario files exist in the repository without being registered, so they
  do not appear in the launcher

---

## See also

- [ScenSyn](scensyn.md) — the shared session runtime
- [Story Catalyst authoring](story-catalyst-authoring.md) — writing your own Open Play stories
- [Story Stage sprite packs](story-stage-sprites.md) — installing character art, or supplying your own
- [Workshop Catalyst facilitator manual](workshop-catalyst-facilitator-manual.md) — the other session type
- [Privacy and data](privacy-and-data.md) — what leaves the machine
- [Building on Synesyn](../developer-guide/building-on-synesyn.md) — registering scenarios, collections and session types
