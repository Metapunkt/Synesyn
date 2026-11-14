# ReadyMade output (legacy in-tree path)

Generated markdown from the A1 Synthesis Engine is **not** written here in
current builds. Runtime output goes under the user storage root from
`RuntimeConfig.get_readymade_output_dir()` (typically
`Documents/Synesyn/readymade/output/`), with a `user://readymade/output/`
fallback when Documents is unavailable. The older nested path
`Documents/Synesyn/synesyn/readymade/` is migrated once into this folder.

This directory is kept only as a placeholder so older docs and tooling that
mention `readymade/output/` still resolve. Any `.md` files that appear here are
ignored by git.
