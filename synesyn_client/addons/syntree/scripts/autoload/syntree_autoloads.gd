## Typed resolvers for the autoloads SynTree owns.
##
## Bare autoload identifiers (`ContentBus.foo()`) only resolve while the autoload
## is live, so scripts using them fail to compile in a fresh drop-in project or
## in headless tooling that loads scripts before autoloads register. Resolving
## through the scene tree instead keeps every SynTree script compilable with no
## autoloads present, while the preloaded script constants keep the returned
## references statically typed and expose autoload enums without a live instance.
##
## Always call these at use time. Never cache the result in a field: an autoload
## that registers later would leave the cached value null forever.
##
## Enforced by `synesyn/utilities/checks/check_addon_autoloads.py`.
@tool
extends RefCounted

const ContentBusScript = preload("res://addons/syntree/scripts/autoload/content_bus.gd")
const PluginManagerScript = preload("res://addons/syntree/scripts/plugin_manager.gd")

static func _node(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(autoload_name))

static func content_bus() -> ContentBusScript:
	return _node("ContentBus") as ContentBusScript

static func plugin_manager() -> PluginManagerScript:
	return _node("PluginManager") as PluginManagerScript
