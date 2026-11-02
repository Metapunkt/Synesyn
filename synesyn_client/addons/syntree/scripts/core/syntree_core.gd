## Purpose: Runtime-safe SynTree core entrypoint (apps can use core without editor UI)
##
## This file intentionally contains **no EditorPlugin/UI dependencies**.
## It can be used in:
## - editor (as part of the SynTree plugin), and
## - runtime apps (ScenSyn/ReadyMade/etc) that want SynTree core services.
##
## Note: Core services are primarily accessed via autoloads (e.g. `/root/ContentBus`).
## Runtime apps should add required autoloads in Project Settings (or via their own bootstrap).
extends RefCounted
class_name SynTreeCore

static func get_required_autoloads() -> PackedStringArray:
	return ["ContentBus", "NotificationManager"]

static func get_autoload_node(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null(name)

static func get_core_status() -> Dictionary:
	var missing: Array[String] = []
	for nm in SynTreeCore.get_required_autoloads():
		if not is_instance_valid(get_autoload_node(nm)):
			missing.append(nm)
	return {
		"ok": missing.is_empty(),
		"missing": missing,
		"required": Array(SynTreeCore.get_required_autoloads()),
	}

static func require_core() -> Dictionary:
	var st := get_core_status()
	if bool(st.get("ok", false)):
		return {"ok": true}
	return {
		"ok": false,
		"error": "SynTree core not installed (missing autoloads)",
		"details": st,
	}

static func get_content_bus() -> Node:
	return get_autoload_node("ContentBus")


