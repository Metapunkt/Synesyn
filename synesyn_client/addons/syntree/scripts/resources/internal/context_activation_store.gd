## Purpose: Persist transparent activation policy on SynTree graph nodes.
extends RefCounted

const VALID_MODES: Array[String] = [
	"always",
	"when_relevant",
	"conditional",
	"manual_only",
	"excluded",
]


func get_activation(
	content_state: Object,
	source_id: String,
	node_id: String
) -> Dictionary:
	var location: Dictionary = _resolve_location(
		content_state,
		source_id,
		node_id
	)
	if location.is_empty():
		return {"mode": "when_relevant", "conditions": {}, "priority": 0}
	var source_data: Dictionary = location.get("source_data", {})
	if bool(location.get("is_source_node", false)):
		var source_meta: Dictionary = source_data.get("meta", {})
		var ai_context: Dictionary = source_meta.get("ai_context", {})
		return _normalize(ai_context.get("activation", {}))
	var content_data: Dictionary = source_data.get("content", {})
	var nodes: Array = content_data.get("nodes", [])
	var node_index: int = int(location.get("node_index", -1))
	if node_index < 0 or node_index >= nodes.size():
		return _normalize({})
	var node_data: Dictionary = nodes[node_index]
	return _normalize(node_data.get("activation", {}))


func set_activation(
	content_state: Object,
	source_id: String,
	node_id: String,
	activation: Dictionary
) -> Dictionary:
	var normalized: Dictionary = _normalize(activation)
	if not VALID_MODES.has(str(normalized.get("mode", ""))):
		return {"ok": false, "errors": ["invalid_activation_mode"]}
	var location: Dictionary = _resolve_location(
		content_state,
		source_id,
		node_id
	)
	if location.is_empty():
		return {"ok": false, "errors": ["node_not_found"]}
	var target_source_id: String = str(location.get("source_id", ""))
	var source_data: Dictionary = location.get("source_data", {})
	if bool(location.get("is_source_node", false)):
		var source_meta: Dictionary = source_data.get("meta", {})
		var ai_context: Dictionary = source_meta.get("ai_context", {})
		ai_context["activation"] = normalized
		source_meta["ai_context"] = ai_context
		source_data["meta"] = source_meta
	else:
		var content_data: Dictionary = source_data.get("content", {})
		var nodes: Array = content_data.get("nodes", [])
		var node_index: int = int(location.get("node_index", -1))
		var node_data: Dictionary = nodes[node_index]
		node_data["activation"] = normalized
		nodes[node_index] = node_data
		content_data["nodes"] = nodes
		source_data["content"] = content_data
	var did_save: bool = bool(content_state.call(
		"update_source",
		target_source_id,
		source_data
	))
	return {
		"ok": did_save,
		"activation": normalized,
		"errors": [] if did_save else ["source_update_failed"],
	}


func _resolve_location(
	content_state: Object,
	source_id: String,
	node_id: String
) -> Dictionary:
	if not is_instance_valid(content_state):
		return {}
	var target_source_id: String = source_id
	var local_node_id: String = node_id
	if node_id.contains("::"):
		var id_parts: PackedStringArray = node_id.split("::", false, 1)
		if id_parts.size() == 2:
			target_source_id = id_parts[0]
			local_node_id = id_parts[1]
	var source_data: Dictionary = content_state.call(
		"get_source_data",
		target_source_id
	)
	if source_data.is_empty():
		return {}
	if local_node_id == target_source_id:
		return {
			"source_id": target_source_id,
			"source_data": source_data,
			"is_source_node": true,
		}
	var content_data: Dictionary = source_data.get("content", {})
	var nodes: Array = content_data.get("nodes", [])
	for node_index in range(nodes.size()):
		var node_data: Dictionary = nodes[node_index]
		if str(node_data.get("node_id", "")) == local_node_id:
			return {
				"source_id": target_source_id,
				"source_data": source_data,
				"is_source_node": false,
				"node_index": node_index,
			}
	return {}


func _normalize(activation_any: Variant) -> Dictionary:
	var activation: Dictionary = {}
	if typeof(activation_any) == TYPE_DICTIONARY:
		activation = (activation_any as Dictionary).duplicate(true)
	var activation_mode: String = str(
		activation.get("mode", "when_relevant")
	).to_lower()
	var conditions_any: Variant = activation.get("conditions", {})
	var conditions: Dictionary = {}
	if typeof(conditions_any) == TYPE_DICTIONARY:
		conditions = (conditions_any as Dictionary).duplicate(true)
	return {
		"mode": activation_mode,
		"conditions": conditions,
		"priority": int(activation.get("priority", 0)),
	}
