# Screenshot capture guide

This folder holds the screenshots used by the root `README.md` and the
documentation site. Filenames matter, because the README refers to them directly.

All four are produced by the harness rather than by hand, which is the point: a
README image that drifts from the product is a small lie that nobody notices, and
regenerating these is one command.

## Regenerating the Workshop Catalyst captures

```bash
python utilities/harness/test_harness.py \
  --spec docs/technical-review/run_specs/scensyn_readme_captures.json
```

The run holds a real session — three facilitator turns against a live model, so it
costs model calls and takes around six minutes — then walks the workspace presets,
capturing as it goes. It writes `workshop-catalyst-session.png`, `thinking-map.png`,
`thinking-map-graph.png` and `session-record.png` into the run directory reported in
its output. Copy the ones you want here — `session-record.png` is published as
`review-compare-paths.png`, which is what it actually shows — quantised to 256 colours
to keep each file near 120 KB rather than 360 KB.

The spec asserts the session actually accumulated material, so an empty or broken
capture fails the run rather than producing a plausible-looking screenshot of
nothing.

| Filename | What it shows | Why this one |
| --- | --- | --- |
| `workshop-catalyst-session.png` | Full Dashboard three turns in: facilitator prompt, chat, and the map filling up | The most developed and most tested part of the project. If a reader sees one image, this is it |
| `thinking-map.png` | Column view with claims marked *AI inferred / Suggested*, each offering Accept, Edit, Reject, Defer | Shows "systems propose, humans commit" (ADR 0019) in one picture, which prose struggles to do |
| `review-compare-paths.png` | The Review workspace comparing paths, including the explicit do-nothing path | Where the session's record is examined before anything is committed — that a session leaves something defensible |
| `story-stage.png` | A character from *Ireti Okan* on stage, mid-line, against the scenario's backdrop | The only image that conveys the generative-theatre side, and the clearest evidence that the two session types are genuinely different things |

Captured but currently unusable: `thinking-map-graph.png`. The graph view draws node
panels dark against the light theme, so the text in them is illegible. Worth
recapturing once that is fixed, because the typed relations read better as a graph
than as columns.

## Regenerating the Story Stage capture

```bash
python utilities/harness/test_harness.py \
  --spec docs/technical-review/run_specs/scensyn_story_stage_capture.json
```

Story Stage is a view of a session rather than a session of its own — it shows whoever
is speaking in the story log — so the run opens a Story Catalyst session, takes one real
turn against *Ireti Okan*, then mounts the stage beside it. That costs one model call and
about three minutes, and it needs a
[sprite pack](../../user-guide/story-stage-sprites.md) installed; without the art the
stage falls back to a visualiser, which is honest but not what this image is for.

Three details, all learned the hard way:

- The window is **16:9**, unlike the other captures. The stage is laid out for the
  project's 1152×648 viewport, and any other ratio expands the canvas — which drifts the
  centre-anchored input field over the portrait
- The AI character arrives **third**, after the narrator's welcome and the typed line
  have each been spoken aloud, so the run takes a series of captures and the best frame
  is published. `stage-03` or `stage-04` is usually the one
- The dialogue box shows about three lines. A longer line runs past its fold, so crop
  the final image just below the last complete line rather than publishing a half-line

This one is **not** quantised to 256 colours: the portrait is photographic and
posterises visibly where the flat UI captures do not. It is downscaled to 1280 px
instead, which lands around 800 KB.

Optional, if the Closure Map is in a presentable state:
`synaxes-closure-map.png` — closures placed against orientation, showing coverage.

## Conventions

- **PNG**, around 1600×1120 for the dashboard views — the size their capture spec runs
  at. Larger is wasted; smaller loses UI text. Story Stage is the exception, and the
  section above says why
- **One theme throughout.** The existing captures are light; match them
- **Use a shipped scenario.** Karlsruhe for Workshop Catalyst, *Ireti Okan* for Story
  Stage. Never a real client engagement
- **No participant data.** No real names, no actual workshop content, nothing from a
  session anyone attended in confidence
- **Check the window edges** before saving: no file paths containing your home
  directory, no API keys, no provider account names, no notification popups
- **Keep each file small.** These live in the repository permanently and are served by
  the docs site. Flat UI captures quantise to around 120 KB with no visible loss;
  anything photographic is downscaled instead
- Crop to the application window rather than the whole desktop

## Adding one to the README

The image block sits directly under the opening description. Add a row for a new
capture, and never leave a reference to a file that is not here — a broken image is
worse than an absent one.
