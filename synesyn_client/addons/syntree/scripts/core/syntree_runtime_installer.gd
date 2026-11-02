## Purpose: Runtime installer for SynTree core (no editor plugin required)
##
## v1 goal: apps can use SynTree core services without EditorPlugin dependencies.
## This helper installs the required core autoloads at runtime (best-effort).
##
## Usage:
##   var res := SynTreeRuntimeInstaller.ensure_core_installed()
##   if not res.ok: push_error(res.error)
extends RefCounted
class_name SynTreeRuntimeInstaller

const ContentBusScript = preload("res://addons/syntree/scripts/autoload/content_bus.gd")
const NotificationManagerScript = preload("res://addons/syntree/scripts/utils/notification_manager.gd")

static func _root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root
	return null

static func ensure_core_installed() -> Dictionary:
	var root := _root()
	if not is_instance_valid(root):
		return {"ok": false, "error": "SceneTree root not available"}

	var installed: Array[String] = []

	# NotificationManager
	if root.get_node_or_null("NotificationManager") == null:
		var nm := NotificationManagerScript.new()
		nm.name = "NotificationManager"
		root.add_child(nm)
		installed.append("NotificationManager")

	# ContentBus
	if root.get_node_or_null("ContentBus") == null:
		var cb := ContentBusScript.new()
		cb.name = "ContentBus"
		root.add_child(cb)
		installed.append("ContentBus")

	return {"ok": true, "installed": installed}


