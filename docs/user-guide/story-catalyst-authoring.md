# Story Catalyst authoring: Open Play

There are two ways to put new narrative material into
[Story Catalyst](story-catalyst.md), and they are for different situations.

| | Bundled collections | Open Play |
| --- | --- | --- |
| **Written as** | A `.txt` scenario file in the repository | A story you create inside the application |
| **Needs** | A code-side registration to appear | Nothing — it appears as soon as you save it |
| **Lives** | In the repository, shared with everyone | In your workspace folder, private to you |
| **Carries** | Phases, dramaturgy, domain tracking, voice maps | A setting, a cast, plot twists and genre tags |

This page is about **Open Play**, which is the one to reach for first. Adding a
scenario to Sustainability or Cultural Narratives is covered in
[building on Synesyn](../developer-guide/building-on-synesyn.md); it is worth doing
once an idea has proven itself, and premature before that.

Open Play deliberately carries no didactic overlay: no domain meters, no phase
scoring, no curriculum framing. It exists for narrative play, and for finding out
whether a recurring idea deserves to become a proper collection.

## The fastest path

1. Launch the client, open **ScenSyn**, choose session type **Story Catalyst**,
   then collection **Open Play**.
2. The Scenario dropdown starts on **"— Create new story —"**, so a story you
   saved earlier is never silently reused.
3. Click **"Create / describe Story Scenario"**. The Story Builder opens and
   drafts with you: you describe the situation, it proposes setting, cast and
   twists, and you keep editing until it reads right.
4. Finish the draft. It is saved to your library and appears in the dropdown
   under its own name.
5. **Confirm**, pick the character you want to play, and start.

Selecting a saved story later turns the same button into **"Review / edit selected
Story Scenario"**. To start something new while a saved story is selected, either
pick "— Create new story —" again or Shift+click the button.

## What a story is made of

| Field | What it does | Worth knowing |
| --- | --- | --- |
| `name` | Title, and what you pick in the dropdown | Also names the sprite folder, if you add art |
| `objective` | The question the session circles | Not a lesson — something the cast can disagree about |
| `setting` | Place, time and pressure | A few concrete sentences beat a paragraph of atmosphere |
| `characters` | The cast | Roles with conflicting wants produce better sessions than detailed biographies |
| `plot_twists` | Dramatic fuel, drawn on when a scene stalls | Optional, and never graded |
| `tags` | Genre steer, folded into the prompt | Must come from the curated list below |

A cast of three to five is the sweet spot: enough friction to argue, few enough
that each character speaks often enough to stay distinct. Mark the one you intend
to play as not AI-driven; everyone else is voiced by the model.

### Genre tags

Exactly these ten are recognised:

`Fantasy` · `Sci-Fi` · `Horror` · `Mystery` · `Thriller` · `Adventure` ·
`Historical` · `Cyberpunk` · `Solarpunk` · `Espionage`

Matching ignores case, but **anything outside this list is dropped without
warning**. That is the most common surprise when editing a story file by hand: an
invented tag simply disappears on the next save.

## Where your stories live

Open Play stories are kept in your workspace folder, not in the repository, so
they survive updates and are yours to copy, back up or share:

```text
<workspace>/scensyn/story_catalyst/open_play/scenarios/<id>.json   saved library
<workspace>/scensyn/story_catalyst/open_play/scenario_draft_v1.json  working draft
```

`<workspace>` is `Documents/Synesyn/` unless you have pointed it elsewhere. The
working draft is the story you last finished or reviewed, which is why "review
draft" reopens it.

## Editing a story file by hand

The saved format is plain JSON, so you can write or fix a story in a text editor.
A minimal valid file:

```json
{
  "schema_version": 1,
  "id": "open_play_harbour_lights_1758271234",
  "name": "Harbour Lights",
  "objective": "Who gets to stay when the water rises?",
  "setting": "A working harbour on its last winter before managed retreat. The council has funding to relocate half the district and no agreed basis for choosing which half.",
  "characters": [
    { "id": 1, "name": "Ines", "role": "Harbour master", "description": "Knows every berth and every debt owed on them.", "is_ai": true },
    { "id": 2, "name": "Tobias", "role": "Council engineer", "description": "Has the model that decides, and doubts it.", "is_ai": true },
    { "id": 3, "name": "You", "role": "Newly appointed mediator", "description": "Arrived yesterday.", "is_ai": false }
  ],
  "plot_twists": ["A tanker runs aground and settles the question for one street"],
  "tags": ["Mystery", "Solarpunk"]
}
```

Rules the loader enforces, each of which fails quietly rather than loudly:

- **`id` must match the filename** without `.json`, and must begin with
  `open_play_`. The application generates ids as
  `open_play_<name-slug>_<timestamp>`; keep that shape.
- **A character without a `name` is skipped.** `role` falls back to `Character`,
  and `is_ai` defaults to true.
- **`setting` and `description` are the same text.** Set `setting`; it wins.
- **Unrecognised tags are dropped**, as above.
- `plot_twists` accepts either a JSON array or one multi-line string with `-`
  bullets, whichever is easier to type.
- The descriptive blurbs shown in the session panels are generated from the
  setting, tags and twists unless you write `about_text` and `how_to_text`
  yourself.

## Sharing a story

Copy the `.json` file into the same directory on another machine and it appears in
that machine's dropdown. Nothing else is needed.

Hosting a multiplayer session shares the story too: joining instances receive the
host's Open Play story on **Confirm**. An imported story never overwrites your own
working draft, so hosting or joining cannot cost you the thing you were writing.

## Giving your characters faces

Open Play has no bundled art, and the
[sprite packs](story-stage-sprites.md) only cover the two Cultural Narratives
scenarios, so Story Stage draws your cast with the spectrum visualiser rather
than character portraits until you supply some. Drop frames into your workspace:

```text
<workspace>/scensyn/sprites_generated/open_play/<story-name>/<character>/idle/*.png
<workspace>/scensyn/sprites_generated/open_play/<story-name>/<character>/talking/*.png
```

Both `<story-name>` and `<character>` are lowercased with spaces replaced by
underscores, so *Harbour Lights* becomes `harbour_lights` and `Ines` becomes
`ines`. A `_fallback` directory in place of a character name covers everyone you
have not drawn. Workspace art needs no repository change and no reimport — see
[sprite packs](story-stage-sprites.md) for the full lookup order.

## What Open Play does not do

By design it has no phase guidance, no relational or dramaturgical matrices, no
voice-assignment blocks and no domain tracking. Those belong to the `.txt`
collections, and if your story has started to want them, that is the signal to
promote it — see
[building on Synesyn](../developer-guide/building-on-synesyn.md).

It is also the least covered part of Story Catalyst by tests. The scenario
contract itself is verified, and you can run that check without a model provider
or a hub:

```bash
godot --headless --path synesyn_client \
  --script res://ScenSyn/tests/test_open_play_story_scenario.gd
```

## See also

- [Story Catalyst](story-catalyst.md) — the session type and its three collections
- [Story Stage sprite packs](story-stage-sprites.md) — character art, bundled and your own
- [ScenSyn](scensyn.md) — the shared session runtime
- [Building on Synesyn](../developer-guide/building-on-synesyn.md) — promoting a story into a registered collection
