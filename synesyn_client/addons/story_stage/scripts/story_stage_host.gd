class_name StoryStageHost
extends RefCounted

## Everything the stage asks of its application. Defaults are an empty stage.

signal story_log_changed
signal voice_owner_changed(stage_owns_voice: bool)
signal phase_changed(phase: String)

const FEATURE_STORY_LOG_VIEW := &"story_log_view"
const FEATURE_LANDING := &"landing"
const FEATURE_SERVICES := &"services"
const FEATURE_NEW_STORY_LOG := &"new_story_log"
const FEATURE_LOAD_STORY_LOG := &"load_story_log"
const FEATURE_RENDER := &"render"
const FEATURE_MODEL_CONTROLS := &"model_controls"
const FEATURE_DUAL_WINDOW := &"dual_window"
const FEATURE_SAVE_RECORDINGS := &"save_recordings"
const FEATURE_TYPED_INPUT := &"typed_input"

static var _default_host: StoryStageHost

var _stage_voice_owned := true
var _save_recordings := false
var _opening_spoken := false
var _opening_cleared := false
var _granted: Dictionary = {}


static func resolve_default() -> StoryStageHost:
	if _default_host != null:
		return _default_host
	var path := str(ProjectSettings.get_setting("story_stage/default_host_script", ""))
	if path != "" and ResourceLoader.exists(path):
		var loaded: Variant = load(path)
		if loaded is Script:
			var inst: Variant = (loaded as Script).new()
			if inst is StoryStageHost:
				_default_host = inst
				return _default_host
	_default_host = StoryStageHost.new()
	return _default_host


func granted_capabilities() -> Dictionary:
	return _granted.duplicate(true)


func set_granted_capabilities(caps: Dictionary) -> void:
	_granted = caps.duplicate(true)


func get_scenario() -> Dictionary:
	return {}


func get_default_background_name() -> String:
	var scenario := get_scenario()
	var name := str(scenario.get("default_background", ""))
	if name.to_lower().ends_with(".png"):
		name = name.substr(0, name.length() - 4)
	return name


func has_session() -> bool:
	return false


func get_story_log_entries() -> Array:
	return []


## A live session already showed these lines elsewhere. A log player performs them.
func plays_existing_log() -> bool:
	return true


func commit_local_line(_sender: String, _text: String) -> bool:
	return false


func get_local_speaker_name(_peer_id: int) -> String:
	return ""


func get_local_character_name() -> String:
	return ""


func load_story_log(_path: String) -> void:
	pass


func get_story_log_dir() -> String:
	return OS.get_user_data_dir()


func create_voice() -> StoryStageVoice:
	return StoryStageVoice.new()


func create_imagery() -> StoryStageImagery:
	return StoryStageImagery.new()


func stage_owns_voice() -> bool:
	return _stage_voice_owned


func set_stage_owns_voice(owns: bool) -> void:
	_stage_voice_owned = owns
	voice_owner_changed.emit(owns)


func resolve_voice_name(speaker: String) -> String:
	return speaker


func get_save_recordings() -> bool:
	return _save_recordings


func set_save_recordings(_stage: Node, enabled: bool) -> bool:
	_save_recordings = enabled
	return false


func get_opening_welcome_text() -> String:
	if _opening_cleared:
		return ""
	return ""


func mark_opening_spoken_on_stage() -> void:
	_opening_spoken = true


func reset_opening_spoken() -> void:
	_opening_spoken = false
	_opening_cleared = false


func clear_opening_for_loaded_log() -> void:
	_opening_cleared = true
	_opening_spoken = true


func opening_was_spoken() -> bool:
	return _opening_spoken


func get_player_auto_input() -> Object:
	return null


func is_ai_busy() -> bool:
	return false


func supports(_feature: StringName) -> bool:
	return false


func attach_session_services(_stage: Node) -> void:
	pass


func populate_settings(_stage: Node) -> void:
	pass


func navigate(_stage: Node, _target: String) -> void:
	pass


func toggle_services(_stage: Node) -> bool:
	return false


func close_services(_stage: Node) -> bool:
	return false


func start_new_story_log(_stage: Node) -> bool:
	return false


func request_render(_stage: Node, _kind: String) -> void:
	pass


func set_dual_window(_enabled: bool) -> void:
	pass


func get_dialog_theme() -> Theme:
	return null


func get_sprite_roots() -> Array[String]:
	var roots: Array[String] = []
	return roots


func get_generated_sprite_resource_path(_root_path: String, _char_dir_name: String) -> String:
	return ""


func get_scenario_art_dir() -> String:
	return ""


func get_backgrounds_dir() -> String:
	return ""


func get_replay_backgrounds_dir() -> String:
	return ""


func forget_cached_paths() -> void:
	pass
