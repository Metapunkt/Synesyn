# Content packs

Tooling for assets that are too large to commit but too useful to lose. At present
that is the Story Stage sprite library: roughly 545 MB of PNG animation frames for
two Cultural Narratives scenarios, excluded by `.gitignore` and distributed as
optional packs instead.

| File | Role |
| --- | --- |
| `story_stage_sprites.py` | Build, publish, install and inspect the packs |
| `story_stage_packs.json` | What each pack contains, its size and its checksum |

The user-facing instructions are in
[`../../docs/user-guide/story-stage-sprites.md`](../../docs/user-guide/story-stage-sprites.md).
In short, from the repository root:

```bash
python utilities/assets/story_stage_sprites.py status
python utilities/assets/story_stage_sprites.py install ireti-okan --from <archive>
python utilities/assets/story_stage_sprites.py build all --out ../packs --update-manifest
```

Two properties are worth knowing before changing any of this.

**Archives are deterministic.** Entries are sorted, timestamps fixed, and already
compressed images stored rather than deflated, so rebuilding from unchanged art
reproduces the recorded SHA-256. Without that the checksum in the manifest would
be a one-off value nobody could reproduce or check.

**Installation validates before it deletes.** The checksum and every archive path
are verified first, and only then is an existing install replaced. An interrupted
or tampered download therefore cannot leave a contributor with no art at all —
which is the failure that matters, since the art is not in version control.

Stdlib only, no dependency on the hub environment: a contributor who has cloned the
repository and installed nothing else can still fetch the art.

## Publishing the packs

The manifest already records the file count, sizes and SHA-256 of both archives, so
the only thing missing is a public URL. To publish:

1. **Build both archives somewhere outside the repository**, since together they are
   over half a gigabyte:

   ```bash
   python utilities/assets/story_stage_sprites.py build all --out ~/Downloads/synesyn-sprite-packs
   ```

   Confirm each printed `sha256` matches `archive_sha256` in the manifest. It should,
   because the build is deterministic; if it does not, the art has changed, and the
   manifest needs `--update-manifest` and a re-commit.

2. **Create a release** whose tag covers content rather than code — `assets-v1` — so
   it is not confused with a software release, and attach both `.zip` files. GitHub
   allows up to 2 GB per asset, so both fit comfortably.

3. **Record the download URLs** in `story_stage_packs.json`. Each is of the form
   `https://github.com/Metapunkt/Synesyn/releases/download/<tag>/<archive>`. Commit
   the manifest.

4. **Verify a clean install** as a user would experience it, from a clone without the
   art:

   ```bash
   python utilities/assets/story_stage_sprites.py install all
   python utilities/assets/story_stage_sprites.py status
   ```

Once step 3 is committed, `install` needs no `--from` and the user-facing
instructions in
[`../../docs/user-guide/story-stage-sprites.md`](../../docs/user-guide/story-stage-sprites.md)
become accurate as written — that page currently states plainly that no public
download exists yet, so **update it in the same commit**.

If the art is ever revised, bump the release tag rather than replacing an asset in
place: an existing clone verifies against the checksum in its own copy of the
manifest, and silently swapping the file behind a URL turns that check into a
failure the user cannot explain.
