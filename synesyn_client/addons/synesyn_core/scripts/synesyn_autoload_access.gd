extends RefCounted
class_name SynesynAutoloadAccess
## Resolve host/project autoloads without bare global identifiers.
## Product addons must use this so they parse when an autoload is absent (drop-in).

static func get_named(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)

static func theme_manager() -> Node:
	return get_named("ThemeManager")

static func workspace_bootstrapper() -> Node:
	return get_named("WorkspaceBootstrapper")

static func global() -> Node:
	return get_named("Global")

static func story_state() -> Node:
	return get_named("StoryState")

static func voice_service() -> Node:
	return get_named("VoiceService")
