@tool
extends Node
class_name MetapunktAppHostBase

## MetapunktAppHostBase (autoload contract)
##
## Apps should add an autoload named **MetapunktAppHost** whose script extends this base.
## Metapunkt uses it as the deterministic composition root for port binding and (later) scene-agent provisioning.
##
## v1 responsibilities:
## - Publish app_id
## - Publish additional (namespaced) Synterface catalog entries (id -> {description, schema, version})
## - Bind required synterfaces at spawn time (return JSON-friendly binding objects)

func get_app_id() -> String:
	# Example: "scensyn", "readymade"
	return ""

func get_synterface_catalog() -> Dictionary:
	# Return additional app-defined synterfaces (namespaced IDs strongly recommended),
	# e.g. { "scensyn.story_state": { "version":"v1", "description":"...", "schema":{...} } }
	return {}

func bind_synterfaces(required_synterfaces: Array, hints: Dictionary) -> Dictionary:
	# Return:
	# {
	#   "ok": true/false,
	#   "synterfaces": { synterface_id: <binding object> },
	#   "missing": [synterface_id, ...],          # optional
	#   "error": "human readable message"   # optional
	# }
	#
	# Binding objects should be JSON-friendly dictionaries so they can be validated
	# against JSON Schemas and reflected in UI/docs.
	#
	# NOTE: A host may still keep runtime objects privately; ports returned here are
	# the declarative contract objects.
	return {"ok": true, "synterfaces": {}}

func get_agent_slots() -> Array:
	# Optional: app declares an "agent ensemble" as a set of slots/roles.
	# Router will merge these from all installed apps for UI + validation + persistence.
	#
	# Slot record (recommended keys):
	# - slot_id: String (namespaced, e.g. "scensyn.narrator")
	# - label: String
	# - kind: String (narrator/character/planner/reviewer/...)
	# - required_synterfaces: Array[String]
	# - recommended_templates: Array[String] (ties to AgentDefs templates)
	# - default_thread_scope: String (optional)
	# - notes: String (optional)
	return []

func spawn_agent_node(_agent_id: String, _def: Resource, _ports: Dictionary) -> Dictionary:
	# Optional (future): for scene-coupled agents, host can instance/add nodes here.
	# Return: { "ok": true, "node": <Node> } or { "ok": false, "error": "..." }
	return {"ok": false, "error": "spawn_agent_node not implemented"}

func stop_agent_node(_agent_id: String) -> Dictionary:
	# Optional (future): stop/cleanup a scene-coupled agent node.
	return {"ok": false, "error": "stop_agent_node not implemented"}


