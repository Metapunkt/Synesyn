@tool
extends MetapunktAppHostBase
class_name ReadyMadeMetapunktAppHost

const _SynterfaceCatalog := preload("res://addons/metapunkt/Core/Ports/synterface_catalog.gd")

func get_app_id() -> String:
	return "readymade"

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
		"readymade.workplan": {
			"version": "v1",
			"description": "ReadyMade workplan/task access (domain-specific operations).",
			"schema": service_schema
		},
		"readymade.ui_hooks": {
			"version": "v1",
			"description": "ReadyMade UI hooks (toast/status).",
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
			"readymade.workplan":
				if not _has_autoload("ReadyMadeOrchestrator"):
					missing.append(sid)
				else:
					syn[sid] = {
						"kind": "service",
						"service": "readymade.workplan",
						"operations": ["list_tasks", "get_task", "set_task_status", "add_task"]
					}
			"readymade.ui_hooks":
				syn[sid] = {
					"kind": "service",
					"service": "readymade.ui_hooks",
					"operations": ["toast", "status"],
					"channels": ["toast", "status"]
				}
			_:
				missing.append(sid)

	if not missing.is_empty():
		return {"ok": false, "missing": missing, "error": "ReadyMade host missing synterfaces: %s" % str(missing)}
	return {"ok": true, "synterfaces": syn}

func get_agent_slots() -> Array:
	# Minimal v0: expose a single "A1" slot for ReadyMade orchestration.
	return [
		{
			"slot_id": "readymade.a1",
			"label": "ReadyMade A1",
			"kind": "planner",
			"required_synterfaces": ["conversation_io", "thread_scope", "ui_hooks", "workplan", "readymade.workplan"],
			"recommended_templates": ["ReadyMade A1"],
			"default_thread_scope": "readymade_session",
			"notes": "Optional slot for delegating ReadyMade planning/workplan reasoning to a Metapunkt-managed agent."
		}
	]

func _has_autoload(autoload_name: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return false
	return tree.root.get_node_or_null(autoload_name) != null
