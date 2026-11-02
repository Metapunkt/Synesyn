# 0014 — Documents/Synesyn as the user-visible storage root

- **Status:** Accepted
- **Date:** 2026-08-06
- **Area:** client | scensyn

## Context
Synesyn already stores config, story logs, and workspace material under a
user-visible root (`Documents/Synesyn` by default via `RuntimeConfig`). Open Play
and Workshop scenario drafts were incorrectly written to Godot `user://`
(`AppData/Roaming/Godot/app_userdata/Synesyn/...`), which is hard for facilitators
to find, back up, or share. That contradicted an earlier product directive that
user-authored artifacts belong under Documents.

## Options considered
1. **Keep `user://` for drafts/libraries** — simple Godot default; opaque to users.
2. **Documents/Synesyn via RuntimeConfig helpers** — matches story logs/config;
   requires migration from legacy `user://` paths.
3. **Workspace-relative only** — couples personal drafts to the active workspace;
   wrong for scenario libraries that should survive workspace switches.

## Decision
User-authored / user-visible Synesyn persistence resolves through
`RuntimeConfig` under `Documents/Synesyn/...` (or `storage.root_dir` when
configured). This covers ScenSyn drafts/libraries/story logs, shared client
config, SynTree resources, Metapunkt overrides, packs, workplans, voice data,
ReadyMade exports/sessions, and similar artifacts. Do **not** introduce new
long-lived user-facing writes to Godot `app_userdata` / `user://`.
Legacy `user://...` files are migrated into Documents on first read where helpers
exist.

`user://` remains acceptable for ephemeral engine caches (e.g. embedding cache),
test/harness temp paths, and true fallbacks when Documents is unavailable.

Canonical helpers (non-exhaustive):
- `RuntimeConfig.get_storage_root_dir()` / `get_scensyn_data_dir()` / `get_synesyn_module_dir()`
- `RuntimeConfig.get_open_play_scenarios_dir()` / `get_open_play_draft_path()`
- `RuntimeConfig.get_workshop_draft_path()` / `get_scensyn_story_log_dir()`
- `RuntimeConfig.get_ui_config_path()` / `get_packs_dir()` / `get_workplans_dir()`
- `RuntimeConfig.get_metapunkt_data_dir()` / `get_readymade_data_dir()`
- `RuntimeConfig.migrate_file_if_needed()` / `migrate_binary_file_if_needed()`

## Consequences
- Positive: drafts, libraries, exports, and config are discoverable under one root.
- Positive: agents and future features have one storage convention to follow.
- Trade-off: first load after upgrade copies legacy AppData files into Documents;
  old AppData copies are left in place (not deleted).
- Follow-up: Cursor rule `documents-synesyn-storage.mdc` keeps this prior visible
  in agent sessions.
