extends Object
class_name MetapunktSynterfaceCatalog

## Metapunkt Synterface Catalog (v1)
##
## A "Synterface" is a host-provided integration surface required by an agent.
## - Metapunkt ships core synterfaces with JSON Schema "shapes".
## - Apps can add namespaced synterfaces (e.g. `scensyn.story_state`) via `MetapunktAppHost.get_synterface_catalog()`.
##
## v1 design intent:
## - Keep schemas simple and JSON-native (for transmission, UI, docs, validation).
## - Bindings may still wrap runtime objects; schemas describe the "capability envelope" the host returns.

const SCHEMA_DRAFT: String = "https://json-schema.org/draft/2020-12/schema"

static func get_core_synterface_catalog_v1() -> Dictionary:
	# Returns: synterface_id -> { description, schema, version }
	return {
		"conversation_io": {
			"version": "v1",
			"description": "Capability to request tool calls / chat through Metapunkt (policy + audit enforced).",
			"schema": {
				"$schema": SCHEMA_DRAFT,
				"type": "object",
				"additionalProperties": true,
				"required": ["kind", "operations"],
				"properties": {
					"kind": {"type": "string", "enum": ["service"]},
					"service": {"type": "string"},
					"operations": {"type": "array", "items": {"type": "string"}, "minItems": 1}
				}
			}
		},
		"thread_scope": {
			"version": "v1",
			"description": "Thread scoping metadata used to isolate agent conversations/artifacts per app/session.",
			"schema": {
				"$schema": SCHEMA_DRAFT,
				"type": "object",
				"additionalProperties": true,
				"required": ["scope"],
				"properties": {"scope": {"type": "string", "minLength": 1}}
			}
		},
		"scene_root": {
			"version": "v1",
			"description": "Scene attachment root for scene-coupled agents (host provides a stable spawn parent).",
			"schema": {
				"$schema": SCHEMA_DRAFT,
				"type": "object",
				"additionalProperties": true,
				"required": ["kind"],
				"properties": {
					"kind": {"type": "string", "enum": ["node", "path"]},
					"path": {"type": "string"},
					"label": {"type": "string"}
				}
			}
		},
		"workplan": {
			"version": "v1",
			"description": "Workplan/task-queue access for planning/execution apps (e.g. ReadyMade).",
			"schema": {
				"$schema": SCHEMA_DRAFT,
				"type": "object",
				"additionalProperties": true,
				"required": ["kind", "operations"],
				"properties": {
					"kind": {"type": "string", "enum": ["service"]},
					"service": {"type": "string"},
					"operations": {"type": "array", "items": {"type": "string"}, "minItems": 1}
				}
			}
		},
		"ui_hooks": {
			"version": "v1",
			"description": "UI feedback hooks (toasts/notifications and optional status strip updates).",
			"schema": {
				"$schema": SCHEMA_DRAFT,
				"type": "object",
				"additionalProperties": true,
				"required": ["kind", "operations"],
				"properties": {
					"kind": {"type": "string", "enum": ["service"]},
					"service": {"type": "string"},
					"operations": {"type": "array", "items": {"type": "string"}, "minItems": 1},
					"channels": {"type": "array", "items": {"type": "string"}}
				}
			}
		}
	}


