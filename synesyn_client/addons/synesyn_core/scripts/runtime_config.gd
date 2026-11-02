extends RefCounted
class_name RuntimeConfig

static func get_config_path_abs() -> String:
	# Example (Windows):
	# C:/Users/<you>/Documents/Synesyn/synesyn/config/synesyn_client.json
	var base := _default_storage_root_dir()
	if base.strip_edges().is_empty():
		# Best-effort fallback: if Documents isn't available, fall back to user://.
		# (This still keeps a single config path in that environment.)
		return ProjectSettings.globalize_path("user://synesyn_client.json")
	return base.path_join("synesyn").path_join("config").path_join("synesyn_client.json")

static func _default_storage_root_dir() -> String:
	# Prefer a user-visible folder (Documents/Synesyn) over Godot's app_userdata.
	# This is our own convention for Synesyn assets/workspaces; it does NOT change user://.
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs.strip_edges().is_empty():
		return ""
	return docs.path_join("Synesyn")


## Canonical local storage root (Documents/Synesyn by default, or storage.root_dir override).
## User-authored ScenSyn artifacts must use this — not Godot app_userdata (user://).
static func get_storage_root_dir() -> String:
	var cfg: Dictionary = load_config()
	var storage_any: Variant = cfg.get("storage", {})
	if typeof(storage_any) == TYPE_DICTIONARY:
		var configured: String = String(
			(storage_any as Dictionary).get("root_dir", "")
		).strip_edges()
		if not configured.is_empty():
			return configured
	return _default_storage_root_dir()


## Documents/Synesyn/scensyn/ — drafts, libraries, and other ScenSyn user data.
static func get_scensyn_data_dir() -> String:
	var base: String = get_storage_root_dir()
	if base.strip_edges().is_empty():
		return ProjectSettings.globalize_path("user://scensyn/")
	return base.path_join("scensyn") + "/"


static func get_open_play_scenarios_dir() -> String:
	return (
		get_scensyn_data_dir()
		.path_join("story_catalyst")
		.path_join("open_play")
		.path_join("scenarios")
		+ "/"
	)


static func get_open_play_draft_path() -> String:
	return (
		get_scensyn_data_dir()
		.path_join("story_catalyst")
		.path_join("open_play")
		.path_join("scenario_draft_v1.json")
	)


static func get_workshop_scenarios_dir() -> String:
	return (
		get_scensyn_data_dir()
		.path_join("workshop_catalyst")
		.path_join("scenarios")
		+ "/"
	)


static func get_workshop_draft_path() -> String:
	return (
		get_scensyn_data_dir()
		.path_join("workshop_catalyst")
		.path_join("scenario_draft_v1.json")
	)


## Documents/Synesyn/scensyn/scenario_exports/ — shareable Scenario bundles.
## User-facing on purpose: this is the folder people attach to an email.
static func get_scenario_exports_dir() -> String:
	return get_scensyn_data_dir().path_join("scenario_exports") + "/"


## Documents/Synesyn/synesyn/ — shared client module data (threads, packs, UI).
static func get_synesyn_module_dir() -> String:
	var base: String = get_storage_root_dir()
	if base.strip_edges().is_empty():
		return ProjectSettings.globalize_path("user://synesyn/")
	return base.path_join("synesyn") + "/"


static func get_ui_config_path() -> String:
	return get_synesyn_module_dir().path_join("config").path_join("synesyn_ui.cfg")


static func get_character_metaprompts_dir() -> String:
	return get_scensyn_data_dir().path_join("character_metaprompts") + "/"


static func get_graph_layouts_path() -> String:
	return get_synesyn_module_dir().path_join("context_graph_layouts.json")


static func get_character_voices_path() -> String:
	return (
		get_synesyn_module_dir()
		.path_join("syntree_voice")
		.path_join("character_voices.json")
	)


static func get_voice_recordings_dir() -> String:
	return (
		get_synesyn_module_dir()
		.path_join("syntree_voice")
		.path_join("recordings")
		+ "/"
	)


static func get_packs_dir() -> String:
	return get_synesyn_module_dir().path_join("packs") + "/"


static func get_workplans_dir() -> String:
	return get_synesyn_module_dir().path_join("workplans") + "/"


static func get_metapunkt_data_dir() -> String:
	return get_synesyn_module_dir().path_join("config").path_join("metapunkt") + "/"


static func get_prompt_chains_dir() -> String:
	return get_synesyn_module_dir().path_join("prompt_chains")


static func get_conversation_threads_dir() -> String:
	return get_synesyn_module_dir().path_join("conversation_threads")


static func get_syntree_config_path() -> String:
	return get_synesyn_module_dir().path_join("config").path_join("syntree_config.cfg")


static func get_syntree_resources_path() -> String:
	return get_synesyn_module_dir().path_join("syntree_resources.tres")


static func get_readymade_data_dir() -> String:
	return get_synesyn_module_dir().path_join("readymade") + "/"


## Visual system assets (ComfyUI workflows, presets, prompt scaffolding).
## Honours a `render.visualsystem_dir` override so an existing checkout can be
## pointed at anywhere on disk; otherwise resolves under the storage root. The
## directory is optional — callers must tolerate its absence, because rendering
## is opt-in and requires a separately installed ComfyUI.
static func get_visualsystem_dir() -> String:
	var cfg: Dictionary = load_config()
	var render_any: Variant = cfg.get("render", {})
	if typeof(render_any) == TYPE_DICTIONARY:
		var configured: String = String(
			(render_any as Dictionary).get("visualsystem_dir", "")
		).strip_edges()
		if not configured.is_empty():
			return configured.rstrip("/\\") + "/"
	return get_storage_root_dir().path_join("visualsystem") + "/"


## Copy legacy user:// (or other) file into Documents destination once.
static func migrate_file_if_needed(dest_path: String, legacy_paths: Array) -> void:
	var dest: String = dest_path.strip_edges()
	if dest.is_empty() or FileAccess.file_exists(dest):
		return
	for legacy_any: Variant in legacy_paths:
		var legacy_path: String = String(legacy_any).strip_edges()
		if legacy_path.is_empty() or not FileAccess.file_exists(legacy_path):
			continue
		var source: FileAccess = FileAccess.open(legacy_path, FileAccess.READ)
		if source == null:
			continue
		var body: String = source.get_as_text()
		source.close()
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var dest_file: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
		if dest_file == null:
			return
		dest_file.store_string(body)
		dest_file.close()
		return


## Binary-safe copy of a legacy file (e.g. .tres / .wav) into Documents once.
static func migrate_binary_file_if_needed(dest_path: String, legacy_paths: Array) -> void:
	var dest: String = dest_path.strip_edges()
	if dest.is_empty() or FileAccess.file_exists(dest):
		return
	for legacy_any: Variant in legacy_paths:
		var legacy_path: String = String(legacy_any).strip_edges()
		if legacy_path.is_empty() or not FileAccess.file_exists(legacy_path):
			continue
		var source: FileAccess = FileAccess.open(legacy_path, FileAccess.READ)
		if source == null:
			continue
		var bytes: PackedByteArray = source.get_buffer(source.get_length())
		source.close()
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var dest_file: FileAccess = FileAccess.open(dest, FileAccess.WRITE)
		if dest_file == null:
			return
		dest_file.store_buffer(bytes)
		dest_file.close()
		return


static func default_config() -> Dictionary:
	var voice_service_url := "http://127.0.0.1:8000"
	if ProjectSettings.has_setting("syntree_voice/service_url"):
		voice_service_url = str(ProjectSettings.get_setting("syntree_voice/service_url", voice_service_url))

	var voice_provider_mode := "direct"
	if ProjectSettings.has_setting("syntree_voice/provider_mode"):
		voice_provider_mode = str(ProjectSettings.get_setting("syntree_voice/provider_mode", voice_provider_mode))

	var hub_url := "http://127.0.0.1:17777"
	if ProjectSettings.has_setting("syntree_voice/hub_url"):
		hub_url = str(ProjectSettings.get_setting("syntree_voice/hub_url", hub_url))

	return {
		"schema_version": 1,
		"storage": {
			# If set, Synesyn client-side data (threads, prompt chains, etc.) is stored here
			# instead of under Godot's app_userdata (user://).
			# Example (Windows): C:/Users/<you>/Documents/Synesyn
			"root_dir": _default_storage_root_dir(),
		},
		"hub": {
			"base_url": hub_url, # single canonical local hub URL
			# UX: if true and hub.base_url points to localhost, the launcher may try to start the hub automatically.
			"autostart": true,
			# If true, Synesyn will best-effort stop the local hub when the app exits
			# (implemented in the `WorkspaceBootstrapper` autoload so scene changes don't affect it).
			"stop_on_exit": true,
			# Optional absolute path override (useful for dev or custom installs).
			# If empty, Synesyn will try default packaged layouts like:
			# - <app_root>/services/synesyn_hub/synesyn_hub.exe
			# - <app_root>/../services/synesyn_hub/synesyn_hub.exe
			"exec_path": "",
			# Optional hub auth (shared across apps).
			# When enabled, clients send: Authorization: Bearer <token>
			"auth": {
				"enabled": false,
				"token": "",
			},
		},
		"voice": {
			"provider_mode": voice_provider_mode, # "direct" | "hub"
			"service_url": voice_service_url,      # syntree_voice external service (direct mode)
			"hub_url": hub_url,                    # Synesyn Hub base URL (hub mode)
			"hub_tts_provider_preference": "auto", # "auto" | "edge_tts" | "sapi" | "sidecar"
		},
		# App-specific config. Any app at the “application layer” (ScenSyn, ReadyMade, etc.)
		# should read/write settings under apps.<app_id> to avoid hardcoding conventions.
		# Back-compat: legacy top-level app keys (e.g. "scensyn") may still exist.
		"display": {
			# UI content scale factor (applied to the root Window at startup).
			# 1.0 = default. Increase for large screens / projectors.
			"ui_scale": 1.0,
		},
		"apps": {
			"scensyn": {
				# Whether this app should append SynTree ContentBus sources to its prompts.
				# This is intentionally opt-in to prevent context bleed.
				"include_syntree_context": false,
				# Pause (seconds) inserted between consecutive character speeches in the voice queue.
				# Default 0.1 s. Raise (e.g. 1.0–2.0 s) for more breathing room between turns.
				"inter_character_pause_sec": 0.1,
				# Optional: mirror captured ui.workshop_closure payloads into STFX Store `closures/`.
				# Keep false by default so live workshop capture remains substrate-only unless opted in.
				"publish_closures_to_stfx_store": false,
				# Workshop Catalyst workspace density. Presets only control panel visibility;
				# safety, consent, error, and End & Save controls remain outside this state.
				"workshop_workspace_preset": "full_dashboard",
				"workshop_workspace_custom_panels": {
					"conversation": true,
					"thinking_map": true,
					"ai_assistant": true,
					"session_record": true,
					"participants": true,
					"navigation": true,
				},
			},
			"metapunkt": {
				# Optional authentication mode for Metapunkt SLOP endpoints.
				# - "no-auth": no authentication required (default for local/offline workflows)
				# - "auth-required": require Authorization + explicit user id headers on SLOP requests
				"auth_mode": "no-auth", # "no-auth" | "auth-required"
				# Shared bearer token used when auth_mode == "auth-required".
				# For local deployments only; for hub-verified auth we would add a separate flow.
				"auth_token": "",
				# If true and auth_mode == "required", verify bearer tokens by calling the hub
				# (GET /auth/whoami) instead of comparing to auth_token locally.
				# Keep false by default (local-first, offline-friendly).
				"auth_verify_via_hub": false,
			},
			"syntree": {
				# Ollama may run locally or on another trusted machine. Store the
				# origin only; SynTree appends /api/chat, /api/tags, and related
				# endpoint paths as needed.
				"ollama_base_url": "http://127.0.0.1:11434",
				"ollama_refresh_on_startup": true,
				# Last AI model the user explicitly selected in any app (ScenSyn
				# hamburger menu, SynTree panel, etc.). Restored on startup so the
				# choice survives project reloads; empty string means "auto-select".
				"selected_model": "",
				# Optional substrate persistence for "important outputs" (metaprompts/analyses).
				# When enabled, SynTree will best-effort persist prompt/summary/metrics artifacts to the Hub substrate.
				# Keep false by default to avoid surprising storage/volume and to preserve privacy-by-default.
				"persist_important_outputs": false,
				# Optional: when SynTree publishes a ui.context_graph, also emit a separate bridge artifact
				# that only references the published context graph id (distinct from thread bridge artifacts).
				"publish_context_graph_bridge": false,
				# Optional: also mirror published ui.context_graph payloads into the file-backed
				# STFX Store for human-readable memory/provenance workflows.
				"publish_context_graph_to_stfx_store": false,
				# Optional STFX Store retrieval. When enabled, SynTree best-effort ingests
				# local active content sources into the Hub's file-backed STFX Store and
				# appends the returned context pack to chat prompts. Direct ContentBus injection
				# remains available as fallback.
				"use_stfx_store_context": false,
				"stfx_store_top_k": 5,
				"stfx_store_expansion_depth": 1,
				"stfx_store_default_seed": "primary",
			},
		},
	}

## Returns the directory where ScenSyn should store user-level session files
## (story logs, workshop summaries, autosaves). Resolves relative to the
## canonical Documents/Synesyn storage root established in config.
static func get_scensyn_story_log_dir() -> String:
	var base: String = get_storage_root_dir()
	if base.strip_edges().is_empty():
		# Only reachable where the system Documents directory cannot be resolved,
		# such as a headless run. Falls back to app_userdata, as get_scensyn_data_dir()
		# does: a session's record is user data and must never land in the project
		# source tree, which is not a writable location in an exported build either.
		return ProjectSettings.globalize_path("user://scensyn/story_logs/")
	return base.path_join("scensyn").path_join("story_logs") + "/"

static func load_config() -> Dictionary:
	var new_path_abs := get_config_path_abs()
	var has_new := (not new_path_abs.is_empty() and FileAccess.file_exists(new_path_abs))
	if not has_new:
		return default_config()

	# Canonical Documents path only (no migration; fresh implementation).
	var f := FileAccess.open(new_path_abs, FileAccess.READ)
	if not f:
		return default_config()

	var raw := f.get_as_text()
	f.close()
	if raw.strip_edges().is_empty():
		return default_config()

	# Explicit typing to avoid "Variant inference" warnings (often treated as errors in strict setups).
	var parsed_any: Variant = JSON.parse_string(raw)
	if typeof(parsed_any) != TYPE_DICTIONARY:
		return default_config()
	var parsed: Dictionary = parsed_any

	# Shallow-merge onto defaults so new keys appear automatically
	var cfg := default_config()
	cfg.merge(parsed, true)
	return cfg

static func save_config(cfg: Dictionary) -> bool:
	var path_abs := get_config_path_abs()
	if path_abs.is_empty():
		path_abs = ProjectSettings.globalize_path("user://synesyn_client.json")
	var base_dir := path_abs.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var f := FileAccess.open(path_abs, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(cfg, "\t"))
	f.close()
	return true


## Applies stored display.ui_scale to a Window. Uses canvas-item scaling so the
## factor is visible in exported builds (viewport stretch often ignores it).
static func apply_stored_ui_scale(root_window: Window) -> float:
	var cfg: Dictionary = load_config()
	var display_any: Variant = cfg.get("display", {})
	var display_cfg: Dictionary = display_any if typeof(display_any) == TYPE_DICTIONARY else {}
	return apply_ui_scale(root_window, float(display_cfg.get("ui_scale", 1.0)))


static func apply_ui_scale(root_window: Window, scale: float) -> float:
	if root_window == null or not is_instance_valid(root_window):
		return 1.0
	var clamped: float = clampf(scale, 0.75, 2.0)
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root_window.content_scale_factor = clamped
	return clamped
