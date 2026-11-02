# Story Stage sprite packs

[Story Stage](scensyn.md) is ScenSyn's visual view: characters appear on a staged
backdrop and speak their lines aloud instead of only writing them into the Story
Log. The character art is roughly **545 MB of PNG animation frames**. Because
that is too large to keep in the source repository for art used by two
scenarios, it is distributed as optional **content packs**.

Nothing about these packs is required. Without one, ScenSyn still loads, runs a
full session, speaks, and records and exports logs. When you open Story Stage,
any speaker without sprites is drawn with the spectrum visualiser rather than a
character portrait.

## The packs

| Pack | Covers | Files | Download |
| --- | --- | --- | --- |
| `ireti-okan` | *Ireti Okan: Awaiting an Awakening* | 94 | 66 MB |
| `stochastic-dreams` | *Stochastic Dreams* | 638 | 479 MB |

Only the two [Cultural Narratives](story-catalyst.md) scenarios have bundled art.
The Sustainability collection, Workshop Catalyst and Open Play ship without
sprites, so a pack changes nothing for them. If you only want to see what Story
Stage does, install `ireti-okan`: it is the smaller download and the more
completely realised scenario.

## Check what you have

```bash
python utilities/assets/story_stage_sprites.py status
```

This reports each pack as installed, not installed, or incomplete, and counts the
files actually on disk rather than trusting that a previous download finished.

## Install a pack

```bash
python utilities/assets/story_stage_sprites.py install ireti-okan --from <archive>
```

`--from` takes either a local `.zip` or an `https://` URL. The archive is checked
against the SHA-256 recorded in
[`utilities/assets/story_stage_packs.json`](https://github.com/Metapunkt/Synesyn/blob/main/utilities/assets/story_stage_packs.json)
and rejected on mismatch, and an archive whose contents do not sit under the
directory the pack claims is rejected as well. Neither failure touches art you
already have.

Once the packs are attached to a public release, the URL comes from the manifest
and no `--from` is needed:

```bash
python utilities/assets/story_stage_sprites.py install all
```

**No public download is published yet.** The manifest records the exact size and
checksum each archive must have, but its `download_url` is still empty, so until a
release carries them you need either an archive supplied by the project or your
own copy of the art (see *Publishing a pack* below). The tool says so rather than
failing obscurely.

### After installing

Files land in `synesyn_client/ScenSyn/story_stage/sprites/<collection>/<scenario>/`,
which `.gitignore` excludes, so an installed pack never shows up as a pending
change. Reopen the project in Godot afterwards; it imports the new frames on load,
which takes a minute or two for the larger pack. The packs carry Godot's `.import`
sidecars so import settings and resource IDs match what the scenarios were built
against.

To replace an existing install, add `--force`.

### The art stays with ScenSyn

The stage itself is now a separate addon, `synesyn_client/addons/story_stage/`, which any
application can use (see [Building on Synesyn](../developer-guide/building-on-synesyn.md)).
The art did not move with it. Sprites, scenario backdrops and the generated `.tres`
files are ScenSyn content, so they stay under `synesyn_client/ScenSyn/story_stage/`, and
the pack paths above are unchanged. ScenSyn tells the stage where to look.

The **story-log player** (**Play a Story Log** on the launcher) uses the same art. A log
saved by this version records its collection and scenario in the `.provenance.json` file
next to it, and the player looks up the art from those. A log saved before that has no
such record. It still plays, with every speaker drawn as a spectrum visualiser, unless
you choose a sprite folder with the player's sprite-folder button (tooltip: *Draw
characters from another sprite folder*). The player does not look in the workspace
`sprites_generated` folder described below.

## Bring your own art

You do not need a pack to put faces on a stage, and for your own
[Open Play](story-catalyst-authoring.md) stories you cannot use one — write the
art into your workspace instead, where it needs no repository change and no
reimport:

```text
<workspace>/scensyn/sprites_generated/<collection>/<scenario>/<character>/<animation>/*.png
```

- Every path segment is lowercased with spaces turned into underscores, so a story
  called `Harbour Lights` becomes `harbour_lights`
- `<animation>` is `idle` and `talking` at minimum; the bundled art also uses
  `talking_big` for emphasis
- A `_fallback` character directory is used for any character with no folder of
  its own, which is the cheapest way to get every cast member visible at once

ScenSyn can also materialise generated portraits into that workspace location
itself — see [ScenSyn](scensyn.md). Character art is searched for in the
workspace first, then in the installed pack, then in a shared `default`
directory, so your own art wins over a pack without removing it.

## Publishing a pack

For maintainers with the art present locally:

```bash
python utilities/assets/story_stage_sprites.py build all --out ../packs --update-manifest
```

Archives are built deterministically — entries sorted, timestamps fixed, already
compressed images stored rather than deflated — so rebuilding from unchanged art
reproduces the same checksum. That is what makes the value recorded in the
manifest meaningful rather than decorative. `--update-manifest` writes the file
count, sizes and checksum back into `story_stage_packs.json`; attach the archives
to a release, record each `download_url` by hand, and commit the manifest with the
release.

Windows thumbnail caches and macOS metadata files are excluded from archives
automatically, so they cannot leak into a published pack.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Checksum mismatch` | Truncated or wrong archive. Nothing was extracted; re-download |
| `status` says `INCOMPLETE` | An earlier extraction was interrupted. Re-install with `--force` |
| `lies outside` on install | The archive is not the pack it was named as |
| Characters still invisible | Check `status`, and check the scenario is one of the two with art |
| Art appears for some characters only | Expected where a character has no folder and no `_fallback` exists |

## See also

- [Story Catalyst](story-catalyst.md) — the session type this art belongs to
- [Story Catalyst authoring](story-catalyst-authoring.md) — writing Open Play stories, including their art
- [ScenSyn](scensyn.md) — Story Log, Story Stage and the shared runtime
- [Local development](../developer-guide/local-dev.md) — the other component excluded from this repository
