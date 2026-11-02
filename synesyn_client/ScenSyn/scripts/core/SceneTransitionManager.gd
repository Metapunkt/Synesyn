extends Node
class_name SceneTransitionManager

## SceneTransitionManager - Simple scene switching for Story Log ↔ story_stage
## Maintains story state during transitions

signal scene_switched(from_scene: String, to_scene: String)

enum InterfaceMode { STORY_LOG, STORY_STAGE }
var current_mode: InterfaceMode = InterfaceMode.STORY_LOG

# Scene paths
const STORY_LOG_SCENE = "res://ScenSyn/scenes/game_session.tscn"
const STORY_STAGE_SCENE = "res://ScenSyn/scenes/scensyn_story_stage.tscn"

## Switch to Story Log interface (chat-based)
func switch_to_story_log():
	# In dual-window mode, "switch" should focus the other window rather than swapping scenes.
	if typeof(DualWindowManager) != TYPE_NIL and DualWindowManager and DualWindowManager.is_dual_window_mode():
		DualWindowManager.focus_story_log_window()
		current_mode = InterfaceMode.STORY_LOG
		return
	# Don't rely on current_mode alone: other systems may change scenes directly.
	var current_scene := get_tree().current_scene
	var is_already_story_log: bool = (current_scene != null and current_scene.scene_file_path == STORY_LOG_SCENE)
	if is_already_story_log:
		current_mode = InterfaceMode.STORY_LOG
		print("SceneTransitionManager: Already in Story Log mode")
		return
	
	print("SceneTransitionManager: Switching to Story Log interface")
	current_mode = InterfaceMode.STORY_LOG
	scene_switched.emit("story_stage", "story_log")
	get_tree().change_scene_to_file(STORY_LOG_SCENE)

## Switch to story_stage interface (visual novel)
func switch_to_story_stage():
	# In dual-window mode, "switch" should focus the other window rather than swapping scenes.
	if typeof(DualWindowManager) != TYPE_NIL and DualWindowManager and DualWindowManager.is_dual_window_mode():
		DualWindowManager.focus_story_stage_window()
		current_mode = InterfaceMode.STORY_STAGE
		return
	# Don't rely on current_mode alone: other systems may change scenes directly.
	var current_scene := get_tree().current_scene
	var is_already_story_stage: bool = (current_scene != null and current_scene.scene_file_path == STORY_STAGE_SCENE)
	if is_already_story_stage:
		current_mode = InterfaceMode.STORY_STAGE
		print("SceneTransitionManager: Already in story_stage mode")
		return
	
	print("SceneTransitionManager: Switching to story_stage interface")
	current_mode = InterfaceMode.STORY_STAGE
	scene_switched.emit("story_log", "story_stage")
	get_tree().change_scene_to_file(STORY_STAGE_SCENE)

## Get current interface mode
func get_current_mode() -> InterfaceMode:
	return current_mode

## Check if currently in Story Log mode
func is_story_log_mode() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.scene_file_path == STORY_LOG_SCENE:
		return true
	return current_mode == InterfaceMode.STORY_LOG

## Check if currently in story_stage mode
func is_story_stage_mode() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.scene_file_path == STORY_STAGE_SCENE:
		return true
	return current_mode == InterfaceMode.STORY_STAGE

## Centralized story log loading
var game_session_ref: Node = null

func register_game_session(node: Node) -> void:
	game_session_ref = node

func unregister_game_session(node: Node) -> void:
	if game_session_ref == node:
		game_session_ref = null

func load_story_log_from_path(path: String) -> void:
	if path == "":
		return
	# Prefer a live reference if registered
	if game_session_ref and is_instance_valid(game_session_ref) and game_session_ref.has_method("_apply_story_log_from_json"):
		game_session_ref._apply_story_log_from_json(path)
		return
	# Fallback: try to find a node named GameSession in the tree (recursive)
	var candidate = get_tree().get_root().find_child("GameSession", true, false)
	if candidate and candidate.has_method("_apply_story_log_from_json"):
		candidate._apply_story_log_from_json(path)
		return
	# Instantiate a temporary GameSession offscreen to reuse its loader without changing scenes
	var scene: PackedScene = load(STORY_LOG_SCENE)
	if scene:
		var temp_session: Node = scene.instantiate()
		temp_session.name = "__TempGameSessionLoader__"
		# IMPORTANT: This instance exists only to run _apply_story_log_from_json().
		# Skip full GameSession startup (which awaits frames and may race cleanup).
		temp_session.set("_is_temp_story_log_loader", true)
		get_tree().get_root().add_child(temp_session)
		# Defer call to ensure _ready() runs
		temp_session.call_deferred("_apply_story_log_from_json", path)
		# Free AFTER the deferred apply call runs (ordered on the same node).
		temp_session.call_deferred("queue_free")
	else:
		print("SceneTransitionManager: Unable to instantiate GameSession scene for loading.")

func _cleanup_temp_session(node: Node) -> void:
	if node and is_instance_valid(node):
		node.queue_free()

func request_load_story_log(parent: Control) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Select Story Log JSON"
	dialog.filters = PackedStringArray(["*.json ; JSON files"])
	parent.add_child(dialog)
	dialog.current_dir = RuntimeConfig.get_scensyn_story_log_dir()
	dialog.file_selected.connect(func(p: String): load_story_log_from_path(p))
	dialog.popup_centered_ratio(0.6)
