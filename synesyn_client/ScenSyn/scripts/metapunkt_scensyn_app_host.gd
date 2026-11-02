@tool
extends MetapunktAppHostBase
class_name ScenSynMetapunktAppHost

const _SynterfaceCatalog := preload("res://addons/metapunkt/Core/Ports/synterface_catalog.gd")

func get_app_id() -> String:
	return "scensyn"

func get_synterface_catalog() -> Dictionary:
	var service_schema := {
		"$schema": _SynterfaceCatalog.SCHEMA_DRAFT,
		"type": "object",
		"additionalProperties": true,
		"required": ["kind", "operations"],
		"properties": {
			"kind": {"type": "string", "enum": ["service"]},
			"service": {"type": "string"},
			"operations": {"type": "array", "items": {"type": "string"}, "minItems": 1}
		}
	}
	return {
		"scensyn.story_state": {
			"version": "v1",
			"description": "ScenSyn story-state access (read/write narrative state).",
			"schema": service_schema
		},
		"scensyn.ui_hooks": {
			"version": "v1",
			"description": "ScenSyn UI hooks (toast/status).",
			"schema": service_schema
		}
	}

func bind_synterfaces(required_synterfaces: Array, _hints: Dictionary) -> Dictionary:
	var syn: Dictionary = {}
	var missing: Array = []

	for s in required_synterfaces:
		var sid := str(s).strip_edges()
		if sid.is_empty():
			continue
		match sid:
			"scensyn.story_state":
				# Envelope only; StoryState autoload is the runtime implementation.
				if not _has_autoload("StoryState"):
					missing.append(sid)
				else:
					syn[sid] = {
						"kind": "service",
						"service": "scensyn.story_state",
						"operations": ["get_state", "set_state", "get_character", "set_character"]
					}
			"scensyn.ui_hooks":
				syn[sid] = {
					"kind": "service",
					"service": "scensyn.ui_hooks",
					"operations": ["toast", "status"],
					"channels": ["toast", "status"]
				}
			_:
				missing.append(sid)

	if not missing.is_empty():
		return {"ok": false, "missing": missing, "error": "ScenSyn host missing synterfaces: %s" % str(missing)}
	return {"ok": true, "synterfaces": syn}

func get_agent_slots() -> Array:
	# Minimal v0: expose a Narrator slot. ScenSyn can add character/planner slots later.
	return [
		{
			"slot_id": "scensyn.narrator",
			"label": "Narrator",
			"kind": "narrator",
			"required_synterfaces": ["conversation_io", "thread_scope", "ui_hooks", "scene_root", "scensyn.story_state"],
			"recommended_templates": ["ScenSyn Narrator"],
			"default_thread_scope": "scensyn_session",
			"notes": "Optional slot for delegating narrator generation to a Metapunkt-managed agent. ScenSyn internal pipeline remains default unless the app opts in."
		}
	]

func _has_autoload(autoload_name: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return false
	return tree.root.get_node_or_null(autoload_name) != null


