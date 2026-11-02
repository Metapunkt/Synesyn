class_name StoryLogPlaybackHost
extends StoryStageHost

## Story Stage replaying a saved story log: the entries of a .json log, and whatever its
## .provenance.json sidecar records about how it was staged. Nothing is generated, typed
## or sent anywhere. The entries are all loaded up front, and the player lets them onto
## the stage one at a time with reveal_next(), which is what paces the playback.
##
## A log saved before its sidecar carried a `stage` block still plays: without a
## scenario to name its art, every speaker is drawn by the spectrum visualiser unless a
## sprite folder is picked with set_sprite_root().

const PROVENANCE_SUFFIX := ".provenance.json"
const SPRITE_LIBRARY_SETTING := "story_log_player/sprite_library"
const BACKGROUNDS_DIR_SETTING := "story_log_player/backgrounds_dir"
const DEFAULT_SPRITE_LIBRARY := "res://ScenSyn/story_stage/sprites"
const DEFAULT_BACKGROUNDS_DIR := "res://ScenSyn/story_stage/assets/images/"
const META_SENDER := "_meta"

var log_path: String = ""
var provenance: Dictionary = {}
## Speak lines when a voice service is present. Off, every line is paced by reading time.
var voice_enabled: bool = true

var _entries: Array = []
var _revealed: int = 0
var _owns_voice: bool = true
var _sprite_root: String = ""


## Reads a story log and its sidecar. Returns an error message, or "" on success.
func load_log(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return "Cannot read %s" % path
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return "%s is not a story log (expected a JSON array)" % path.get_file()
	var entries: Array = []
	for entry_any: Variant in parsed:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender: String = String(entry.get("sender", "")).strip_edges()
		if sender.is_empty() or sender == META_SENDER or String(entry.get("message", "")).strip_edges().is_empty():
			continue
		entries.append(entry)
	log_path = path
	_entries = entries
	_revealed = 0
	provenance = _read_provenance(path)
	return ""


static func provenance_path_for(json_path: String) -> String:
	return json_path.trim_suffix(".json") + PROVENANCE_SUFFIX


static func _read_provenance(json_path: String) -> Dictionary:
	var prov_path: String = provenance_path_for(json_path)
	if not FileAccess.file_exists(prov_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(prov_path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## How the log was staged, from the sidecar's `stage` block, or {} for older logs.
func stage_info() -> Dictionary:
	var stage_any: Variant = provenance.get("stage", {})
	return stage_any if typeof(stage_any) == TYPE_DICTIONARY else {}

func entry_count() -> int:
	return _entries.size()

func revealed_count() -> int:
	return _revealed

func entry_at(index: int) -> Dictionary:
	return _entries[index] if index >= 0 and index < _entries.size() else {}

## Let one more entry onto the stage. Returns false once every entry is out.
func reveal_next() -> bool:
	if _revealed >= _entries.size():
		return false
	_revealed += 1
	story_log_changed.emit()
	return true

## Take every entry back off the stage, ready to play from the first line.
func rewind() -> void:
	_revealed = 0

## Seconds between an entry and the one before it as they were first played, or -1
## when the log does not say.
func original_gap_seconds(index: int) -> float:
	if index <= 0 or index >= _entries.size():
		return -1.0
	var previous: Dictionary = _entries[index - 1]
	var current: Dictionary = _entries[index]
	# Tick stamps are exact but restart with each run of the app, so a log resumed in a
	# later run can step backwards; the wall-clock stamps are whole seconds but survive.
	if previous.has("timestamp_us") and current.has("timestamp_us"):
		var delta_us: float = float(current["timestamp_us"]) - float(previous["timestamp_us"])
		if delta_us >= 0.0:
			return delta_us / 1_000_000.0
	var previous_unix: int = _unix_time(String(previous.get("timestamp", "")))
	var current_unix: int = _unix_time(String(current.get("timestamp", "")))
	if previous_unix > 0 and current_unix >= previous_unix:
		return float(current_unix - previous_unix)
	return -1.0


static func _unix_time(stamp: String) -> int:
	var s: String = stamp.strip_edges()
	if s.is_empty():
		return 0
	return Time.get_unix_time_from_datetime_string(s.replace(" ", "T"))


## Draw characters from this folder instead of the one the log's scenario names. It
## holds one folder per character, as a scenario's sprite folder does.
func set_sprite_root(path: String) -> void:
	_sprite_root = path.strip_edges().replace("\\", "/")
	StoryStageCharacter.clear_all_characters()

func get_sprite_root() -> String:
	return _sprite_root


# ── Scenario and story log ───────────────────────────────────────────────

func get_scenario() -> Dictionary:
	var stage: Dictionary = stage_info()
	if stage.is_empty():
		return {}
	return {
		"name": String(stage.get("scenario_name", provenance.get("scenario", ""))),
		"scenario_key": String(stage.get("scenario_key", "")),
		"_collection_id": String(stage.get("collection", "")),
		"default_background": String(stage.get("default_background", "")),
	}

func has_session() -> bool:
	return not _entries.is_empty()

func get_story_log_entries() -> Array:
	return _entries.slice(0, _revealed)

func get_story_log_dir() -> String:
	return log_path.get_base_dir() if not log_path.is_empty() else OS.get_user_data_dir()


# ── Voice ────────────────────────────────────────────────────────────────

func create_voice() -> StoryStageVoice:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree and tree.root.has_node("VoiceService"):
		return SyntreeStageVoice.new()
	return StoryStageVoice.new()

func stage_owns_voice() -> bool:
	return voice_enabled and _owns_voice

func set_stage_owns_voice(owns: bool) -> void:
	_owns_voice = owns

func set_voice_enabled(enabled: bool) -> void:
	voice_enabled = enabled
	voice_owner_changed.emit(stage_owns_voice())

func resolve_voice_name(speaker: String) -> String:
	var overrides_any: Variant = stage_info().get("voice_overrides", {})
	if typeof(overrides_any) == TYPE_DICTIONARY and (overrides_any as Dictionary).has(speaker):
		return String((overrides_any as Dictionary)[speaker])
	return speaker


# ── Art ──────────────────────────────────────────────────────────────────

func _sprite_library() -> String:
	return String(ProjectSettings.get_setting(SPRITE_LIBRARY_SETTING, DEFAULT_SPRITE_LIBRARY))

## Filed the way ScenSyn files them: <library>/<collection>/<scenario>/, then the shared
## <library>/default/.
func get_sprite_roots() -> Array[String]:
	var roots: Array[String] = []
	if not _sprite_root.is_empty():
		roots.append(_sprite_root)
	var stage: Dictionary = stage_info()
	if stage.is_empty():
		return roots
	var library: String = _sprite_library()
	var collection_dir: String = StoryStageCharacter._dir_slug(String(stage.get("collection", "")))
	var scenario_dir: String = StoryStageCharacter._dir_slug(String(stage.get("scenario_name", "")))
	if not collection_dir.is_empty() and not scenario_dir.is_empty():
		roots.append(library.path_join(collection_dir).path_join(scenario_dir))
	roots.append(library.path_join("default"))
	return roots

func get_scenario_art_dir() -> String:
	var stage: Dictionary = stage_info()
	var collection: String = String(stage.get("collection", "")).strip_edges()
	var scenario_key: String = String(stage.get("scenario_key", "")).strip_edges()
	if scenario_key.is_empty():
		scenario_key = String(stage.get("scenario_name", "")).strip_edges().to_lower().replace(" ", "_")
	if collection.is_empty() or scenario_key.is_empty():
		return ""
	return _sprite_library().path_join(collection).path_join(scenario_key)

func get_backgrounds_dir() -> String:
	return String(ProjectSettings.get_setting(BACKGROUNDS_DIR_SETTING, DEFAULT_BACKGROUNDS_DIR))
