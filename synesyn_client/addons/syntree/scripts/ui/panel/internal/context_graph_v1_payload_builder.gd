## Purpose: Build the existing SynTree ui.context_graph schema-v1 payload.
##
## This preserves the currently published contract while the enhanced v2
## ContextGraphAdapter is developed separately.
extends RefCounted


func collect_source_ids(
	content_state: Object,
	active_source_ids: Array[String]
) -> Array:
	var included: Dictionary = {}
	for source_id in active_source_ids:
		included[source_id] = true
		var source_data: Dictionary = content_state.call(
			"get_source_data",
			source_id
		)
		if source_data.is_empty():
			continue
		var source_meta: Dictionary = source_data.get("meta", {})
		var ai_context: Dictionary = source_meta.get("ai_context", {})
		if not bool(ai_context.get("is_stack", false)):
			continue
		var stack_sources_any: Variant = ai_context.get("stack_sources", [])
		if typeof(stack_sources_any) != TYPE_ARRAY:
			continue
		for child_any in (stack_sources_any as Array):
			var child_id: String = _stack_child_id(child_any)
			if not child_id.is_empty():
				included[child_id] = true
	var source_ids: Array = included.keys()
	source_ids.sort()
	return source_ids


func append_source(
	content_state: Object,
	source_id: String,
	nodes: Array,
	edges: Array
) -> bool:
	var source_data: Dictionary = content_state.call(
		"get_source_data",
		source_id
	)
	if source_data.is_empty():
		return false
	var source_meta: Dictionary = source_data.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	var is_stack: bool = bool(ai_context.get("is_stack", false))
	var stack_child_ids: Array[String] = []
	if is_stack:
		var stack_sources_any: Variant = ai_context.get("stack_sources", [])
		if typeof(stack_sources_any) == TYPE_ARRAY:
			for child_any in (stack_sources_any as Array):
				var child_id: String = _stack_child_id(child_any)
				if not child_id.is_empty():
					stack_child_ids.append(child_id)

	nodes.append({
		"id": source_id,
		"kind": "stack" if is_stack else "content_source",
		"meta": {
			"name": str(source_meta.get("name", source_id)),
			"source_type": str(source_meta.get("source_type", "")),
			"is_metaprompt": bool(ai_context.get("metaprompt", false)),
			"is_active": bool(ai_context.get("is_active", false)),
			"is_stack": is_stack,
			"stack_source_ids": stack_child_ids,
		},
	})
	if is_stack:
		for child_id in stack_child_ids:
			edges.append({
				"from": source_id,
				"to": child_id,
				"kind": "stack_member",
			})
	return true


func make_payload(
	active_source_ids: Array[String],
	nodes: Array,
	edges: Array,
	timestamp_text: String
) -> Dictionary:
	return {
		"schema_version": 1,
		"name": "SynTree Context %s" % timestamp_text,
		"nodes": nodes,
		"edges": edges,
		"selection": {"active_source_ids": active_source_ids},
	}


func _stack_child_id(child_any: Variant) -> String:
	if typeof(child_any) == TYPE_DICTIONARY:
		return str((child_any as Dictionary).get("id", "")).strip_edges()
	return str(child_any).strip_edges()
