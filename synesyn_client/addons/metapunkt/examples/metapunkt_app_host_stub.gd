@tool
extends MetapunktAppHostBase

## Example: MetapunktAppHost stub (REFERENCE ONLY)
##
## This file is NOT wired as an autoload. It exists as a copy/paste starting point for apps.
##
## How to use in an app:
## 1) Copy this script into your app folder (e.g. `res://MyApp/scripts/metapunkt_myapp_host.gd`)
## 2) Add `class_name MyAppMetapunktAppHost` and keep `extends MetapunktAppHostBase`
## 3) Customize `get_app_id()`, `get_synterface_catalog()`, and `bind_synterfaces()`
## 4) Do NOT replace `/root/MetapunktAppHost` (it is the router autoload). The router will auto-discover your host.
##
## Important contract rules:
## - `bind_synterfaces()` must return JSON-friendly dictionaries for each bound synterface
## - If a required port cannot be bound, return {ok:false, missing:[...], error:"..."}
## - Avoid returning raw Node references inside the port binding objects. Keep those private if needed.

func get_app_id() -> String:
	# Example values: "scensyn", "readymade"
	return "myapp"

func get_synterface_catalog() -> Dictionary:
	# Apps can publish additional synterfaces beyond Metapunkt core synterfaces.
	# Use namespaced IDs to avoid collisions:
	# - scensyn.story_state
	# - readymade.workplan_store
	# - myapp.inventory
	return {
		"myapp.story_state": {
			"version": "v1",
			"description": "Access to app story state/events (example custom port).",
			"schema": {
				"$schema": "https://json-schema.org/draft/2020-12/schema",
				"type": "object",
				"additionalProperties": true,
				"required": ["kind", "operations"],
				"properties": {
					"kind": {"type": "string", "enum": ["service"]},
					"service": {"type": "string"},
					"operations": {
						"type": "array",
						"items": {"type": "string"},
						"minItems": 1
					}
				}
			}
		}
	}

func bind_synterfaces(required_synterfaces: Array, hints: Dictionary) -> Dictionary:
	# This is a deliberately conservative example implementation:
	# - It returns a "service capability" dictionary for each requested port.
	# - It does not expose Node references; apps can keep those privately.

	var synterfaces: Dictionary = {}
	var missing: Array = []

	for p in required_synterfaces:
		var pid := str(p).strip_edges()
		if pid.is_empty():
			continue

		match pid:
			"conversation_io":
				synterfaces[pid] = {
					"kind": "service",
					"service": "metapunkt.conversation_io",
					"operations": ["call_tool", "chat"]
				}
			"thread_scope":
				# Example: choose a scope using hints or fall back to app_id.
				var scope := str(hints.get("default_scope", "")).strip_edges()
				if scope.is_empty():
					scope = get_app_id()
				synterfaces[pid] = {
					"scope": scope
				}
			"scene_root":
				# Example: bind by group name hint; host can resolve internally at runtime.
				var group := str(hints.get("spawn_root_group", "")).strip_edges()
				if group.is_empty():
					group = "main"
				synterfaces[pid] = {
					"kind": "path",
					"path": "/root", # Placeholder. Prefer a stable NodePath string in your app.
					"label": "scene_root (group=%s)" % group
				}
			"workplan":
				synterfaces[pid] = {
					"kind": "service",
					"service": "myapp.workplan",
					"operations": ["get_next_task", "update_task", "list_tasks"]
				}
			"ui_hooks":
				synterfaces[pid] = {
					"kind": "service",
					"service": "myapp.ui_hooks",
					"operations": ["toast", "notify", "set_status"],
					"channels": ["toast", "status_strip"]
				}
			_:
				# Custom ports: you decide whether they're always available or conditional.
				# If not available, mark missing to fail-fast.
				if pid.begins_with("myapp."):
					synterfaces[pid] = {
						"kind": "service",
						"service": pid,
						"operations": ["get", "set"]
					}
				else:
					missing.append(pid)

	if not missing.is_empty():
		return {
			"ok": false,
			"missing": missing,
			"error": "Host cannot bind required ports: %s" % str(missing)
		}

	return {"ok": true, "synterfaces": synterfaces}


