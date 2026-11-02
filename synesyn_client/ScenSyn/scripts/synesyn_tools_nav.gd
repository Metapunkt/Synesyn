extends RefCounted
class_name SynesynToolsNav

## Navigation helpers for the shared Synesyn Tools shell.
## Keeps return-path state out of the Tools scene script (autoload-safe).

const SCENE_PATH := "res://ScenSyn/scenes/synesyn_tools.tscn"
const RETURN_LAUNCHER_PATH := "res://scenes/synesyn_launcher.tscn"
const RETURN_SCENSYN_MENU_PATH := "res://ScenSyn/scenes/main_menu.tscn"
const RETURN_GAME_SESSION_PATH := "res://ScenSyn/scenes/game_session.tscn"
const ACTION_PROPOSE_THEMES := "propose_themes"

static var _return_scene_path: String = RETURN_SCENSYN_MENU_PATH
## Pending Tools open action consumed once by synesyn_tools.gd (REQ-NDP-016).
static var _pending_action: Dictionary = {}


static func set_return_scene(scene_path: String) -> void:
	var clean_path: String = scene_path.strip_edges()
	if clean_path.is_empty():
		_return_scene_path = RETURN_SCENSYN_MENU_PATH
		return
	_return_scene_path = clean_path


static func get_return_scene() -> String:
	var target: String = _return_scene_path.strip_edges()
	if target.is_empty():
		return RETURN_SCENSYN_MENU_PATH
	return target


static func open_from(tree_ref: SceneTree, return_scene_path: String) -> void:
	if tree_ref == null:
		return
	set_return_scene(return_scene_path)
	tree_ref.change_scene_to_file(SCENE_PATH)


static func open_synaxes_propose_themes(
	tree_ref: SceneTree,
	return_scene_path: String = RETURN_GAME_SESSION_PATH,
	session_id: String = ""
) -> void:
	## Workshop / ScenSyn entry: open Tools → SynAxes with session preload + discover queued.
	_pending_action = {
		"action": ACTION_PROPOSE_THEMES,
		"tab": "SynAxes",
		"session_id": session_id.strip_edges(),
	}
	open_from(tree_ref, return_scene_path)


static func take_pending_action() -> Dictionary:
	var pending: Dictionary = _pending_action.duplicate(true)
	_pending_action.clear()
	return pending
