extends RefCounted
class_name WorkshopProposeThemesEntry

## Thin Workshop → SynAxes entry (REQ-NDP-016).
## Opens Tools with session data preloaded and discovery queued (not headless Phase F).

const SynesynToolsNavScript = preload("res://ScenSyn/scripts/synesyn_tools_nav.gd")


static func open(
	tree_ref: SceneTree,
	session_id: String = "",
	return_scene_path: String = SynesynToolsNavScript.RETURN_GAME_SESSION_PATH
) -> void:
	if tree_ref == null:
		return
	SynesynToolsNavScript.open_synaxes_propose_themes(
		tree_ref,
		return_scene_path,
		session_id
	)
