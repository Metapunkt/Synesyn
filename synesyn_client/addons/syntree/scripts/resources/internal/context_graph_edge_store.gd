## Purpose: Pure rich-edge persistence helpers for SynTree source data.
extends RefCounted

const RelationshipRegistryScript = preload(
	"res://addons/syntree/scripts/core/context_graph_relationship_registry.gd"
)


func upsert(edges: Array, edge_data: Dictionary, node_ids: Array[String]) -> Dictionary:
	var next_edges: Array = edges.duplicate(true)
	var edge_id: String = str(edge_data.get("id", "")).strip_edges()
	var existing_index: int = _find_edge_index(next_edges, edge_id)
	var validation_edges: Array = next_edges.duplicate(true)
	if existing_index >= 0:
		validation_edges.remove_at(existing_index)
	var validation: Dictionary = RelationshipRegistryScript.validate_edge(
		edge_data,
		node_ids,
		validation_edges
	)
	if not bool(validation.get("ok", false)):
		return {
			"success": false,
			"changed": false,
			"edges": edges,
			"errors": validation.get("errors", []),
		}
	var stored_edge: Dictionary = edge_data.duplicate(true)
	var timestamp_text: String = Time.get_datetime_string_from_system(true, true)
	if existing_index >= 0:
		var existing: Dictionary = next_edges[existing_index]
		stored_edge["created_at"] = str(existing.get("created_at", timestamp_text))
		stored_edge["updated_at"] = timestamp_text
		if stored_edge == existing:
			return {"success": true, "changed": false, "edges": next_edges, "errors": []}
		next_edges[existing_index] = stored_edge
	else:
		if not stored_edge.has("created_at"):
			stored_edge["created_at"] = timestamp_text
		if not stored_edge.has("updated_at"):
			stored_edge["updated_at"] = timestamp_text
		next_edges.append(stored_edge)
	return {"success": true, "changed": true, "edges": next_edges, "errors": []}


func remove(edges: Array, edge_id: String) -> Dictionary:
	var next_edges: Array = edges.duplicate(true)
	var edge_index: int = _find_edge_index(next_edges, edge_id.strip_edges())
	if edge_index < 0:
		return {"success": false, "changed": false, "edges": edges, "errors": ["edge_not_found"]}
	next_edges.remove_at(edge_index)
	return {"success": true, "changed": true, "edges": next_edges, "errors": []}


func remove_incident(edges: Array, node_id: String) -> Array:
	var remaining: Array = []
	var normalized_id: String = node_id.strip_edges()
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if (
			str(edge_data.get("from", "")).strip_edges() == normalized_id
			or str(edge_data.get("to", "")).strip_edges() == normalized_id
		):
			continue
		remaining.append(edge_data.duplicate(true))
	return remaining


func reverse(edges: Array, edge_id: String, node_ids: Array[String]) -> Dictionary:
	var edge_index: int = _find_edge_index(edges, edge_id.strip_edges())
	if edge_index < 0:
		return {"success": false, "changed": false, "edges": edges, "errors": ["edge_not_found"]}
	var reversed_edge: Dictionary = (edges[edge_index] as Dictionary).duplicate(true)
	var from_id: String = str(reversed_edge.get("from", ""))
	reversed_edge["from"] = str(reversed_edge.get("to", ""))
	reversed_edge["to"] = from_id
	return upsert(edges, reversed_edge, node_ids)


func migrate_legacy(nodes: Array, existing_edges: Array = []) -> Dictionary:
	var next_edges: Array = existing_edges.duplicate(true)
	var node_ids: Array[String] = _node_ids(nodes)
	var mappings: Array[Dictionary] = [
		{"key": "children", "relation": "contains"},
		{"key": "dependencies", "relation": "depends_on"},
		{"key": "associations", "relation": "related_to"},
	]
	for node_any in nodes:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		var from_id: String = str(node_data.get("node_id", "")).strip_edges()
		var relationships: Dictionary = node_data.get("relationships", {})
		for mapping in mappings:
			var relation_id: String = str(mapping.get("relation", ""))
			var targets_any: Variant = relationships.get(str(mapping.get("key", "")), [])
			if typeof(targets_any) != TYPE_ARRAY:
				continue
			for target_any in (targets_any as Array):
				var to_id: String = str(target_any).strip_edges()
				if _has_compatible_edge(next_edges, from_id, to_id, relation_id):
					continue
				var edge_data: Dictionary = RelationshipRegistryScript.make_edge(
					relation_id,
					from_id,
					to_id
				)
				var result: Dictionary = upsert(next_edges, edge_data, node_ids)
				if bool(result.get("success", false)):
					next_edges = result.get("edges", next_edges)
	return {"success": true, "edges": next_edges}


func _has_compatible_edge(
	edges: Array,
	from_id: String,
	to_id: String,
	projected_relation: String
) -> bool:
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if (
			str(edge_data.get("from", "")) != from_id
			or str(edge_data.get("to", "")) != to_id
		):
			continue
		var stored_relation: String = str(edge_data.get("relation", ""))
		if stored_relation == projected_relation:
			return true
		if projected_relation == "depends_on" and stored_relation == "precedes":
			return true
	return false


func get_source_edges(
	content_state: Object,
	source_id: String,
	edges_key: String,
	include_legacy_projection: bool = true
) -> Array:
	var source_data: Dictionary = content_state.call("get_source_data", source_id)
	var content_data: Dictionary = source_data.get("content", {})
	var stored_edges_any: Variant = content_data.get(edges_key, [])
	var stored_edges: Array = []
	if typeof(stored_edges_any) == TYPE_ARRAY:
		stored_edges = (stored_edges_any as Array).duplicate(true)
	if not include_legacy_projection:
		return stored_edges
	var nodes_any: Variant = content_data.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return stored_edges
	var migration: Dictionary = migrate_legacy(nodes_any, stored_edges)
	return migration.get("edges", stored_edges)


func upsert_source_edge(
	content_state: Object,
	source_id: String,
	edges_key: String,
	edge_data: Dictionary
) -> Dictionary:
	var source_data: Dictionary = content_state.call("get_source_data", source_id)
	var content_data: Dictionary = source_data.get("content", {})
	var nodes: Array = content_data.get("nodes", [])
	var node_ids: Array[String] = _node_ids(nodes)
	var existing_edges: Array = get_source_edges(content_state, source_id, edges_key, false)
	var result: Dictionary = upsert(existing_edges, edge_data, node_ids)
	if not bool(result.get("success", false)):
		return result
	var old_edge: Dictionary = _edge_by_id(existing_edges, str(edge_data.get("id", "")))
	if not old_edge.is_empty():
		_mirror_legacy_edge(content_state, old_edge, false)
	_mirror_legacy_edge(content_state, edge_data, true)
	source_data = content_state.call("get_source_data", source_id)
	content_data = source_data.get("content", {})
	content_data[edges_key] = result.get("edges", existing_edges)
	source_data["content"] = content_data
	var is_updated: bool = bool(content_state.call("update_source", source_id, source_data))
	if is_updated:
		content_state.call("save_source", source_id)
	result["success"] = is_updated
	return result


func remove_source_edge(
	content_state: Object,
	source_id: String,
	edges_key: String,
	edge_id: String
) -> Dictionary:
	var existing_edges: Array = get_source_edges(content_state, source_id, edges_key, false)
	var old_edge: Dictionary = _edge_by_id(existing_edges, edge_id)
	if old_edge.is_empty():
		var projected_edges: Array = get_source_edges(
			content_state,
			source_id,
			edges_key,
			true
		)
		old_edge = _edge_by_id(projected_edges, edge_id)
		if not old_edge.is_empty():
			_mirror_legacy_edge(content_state, old_edge, false)
			return {
				"success": true,
				"changed": true,
				"edges": existing_edges,
				"errors": [],
			}
	var result: Dictionary = remove(existing_edges, edge_id)
	if not bool(result.get("success", false)):
		return result
	_mirror_legacy_edge(content_state, old_edge, false)
	var source_data: Dictionary = content_state.call("get_source_data", source_id)
	var content_data: Dictionary = source_data.get("content", {})
	content_data[edges_key] = result.get("edges", existing_edges)
	source_data["content"] = content_data
	var is_updated: bool = bool(content_state.call("update_source", source_id, source_data))
	if is_updated:
		content_state.call("save_source", source_id)
	result["success"] = is_updated
	return result


func get_stack_source_edges(
	content_state: Object,
	stack_id: String,
	typed_edges_key: String,
	legacy_edges_key: String
) -> Array:
	var stack_data: Dictionary = content_state.call("get_source_data", stack_id)
	var stack_meta: Dictionary = stack_data.get("meta", {})
	var ai_context: Dictionary = stack_meta.get("ai_context", {})
	var typed_any: Variant = ai_context.get(typed_edges_key, [])
	var typed_edges: Array = []
	if typeof(typed_any) == TYPE_ARRAY:
		typed_edges = (typed_any as Array).duplicate(true)
	var legacy_any: Variant = ai_context.get(legacy_edges_key, [])
	if typeof(legacy_any) != TYPE_ARRAY:
		return typed_edges
	for legacy_edge_any in (legacy_any as Array):
		if typeof(legacy_edge_any) != TYPE_DICTIONARY:
			continue
		var legacy_edge: Dictionary = legacy_edge_any
		var from_id: String = str(legacy_edge.get("from", ""))
		var to_id: String = str(legacy_edge.get("to", ""))
		if _has_endpoint_pair(typed_edges, from_id, to_id):
			continue
		var migrated_edge: Dictionary = RelationshipRegistryScript.make_edge(
			"contains",
			from_id,
			to_id,
			"",
			null,
			[],
			"legacy-stack::%s::%s" % [from_id, to_id]
		)
		typed_edges.append(migrated_edge)
	return typed_edges


func upsert_stack_source_edge(
	content_state: Object,
	stack_id: String,
	typed_edges_key: String,
	edge_data: Dictionary,
	node_ids: Array[String]
) -> Dictionary:
	var stack_data: Dictionary = content_state.call("get_source_data", stack_id)
	var stack_meta: Dictionary = stack_data.get("meta", {})
	var ai_context: Dictionary = stack_meta.get("ai_context", {})
	var stored_any: Variant = ai_context.get(typed_edges_key, [])
	var stored_edges: Array = stored_any if typeof(stored_any) == TYPE_ARRAY else []
	var old_edge: Dictionary = _edge_by_id(stored_edges, str(edge_data.get("id", "")))
	var result: Dictionary = upsert(stored_edges, edge_data, node_ids)
	if not bool(result.get("success", false)):
		return result
	if not old_edge.is_empty():
		content_state.call(
			"remove_stack_edge",
			stack_id,
			str(old_edge.get("from", "")),
			str(old_edge.get("to", ""))
		)
	content_state.call(
		"add_stack_edge",
		stack_id,
		str(edge_data.get("from", "")),
		str(edge_data.get("to", ""))
	)
	stack_data = content_state.call("get_source_data", stack_id)
	stack_meta = stack_data.get("meta", {})
	ai_context = stack_meta.get("ai_context", {})
	ai_context[typed_edges_key] = result.get("edges", stored_edges)
	stack_meta["ai_context"] = ai_context
	stack_data["meta"] = stack_meta
	var is_updated: bool = bool(content_state.call("update_source", stack_id, stack_data))
	if is_updated:
		content_state.call("save_source", stack_id)
	result["success"] = is_updated
	return result


func remove_stack_source_edge(
	content_state: Object,
	stack_id: String,
	typed_edges_key: String,
	edge_id: String
) -> Dictionary:
	var stack_data: Dictionary = content_state.call("get_source_data", stack_id)
	var stack_meta: Dictionary = stack_data.get("meta", {})
	var ai_context: Dictionary = stack_meta.get("ai_context", {})
	var stored_any: Variant = ai_context.get(typed_edges_key, [])
	var stored_edges: Array = stored_any if typeof(stored_any) == TYPE_ARRAY else []
	var old_edge: Dictionary = _edge_by_id(stored_edges, edge_id)
	if old_edge.is_empty():
		var projected_edges: Array = get_stack_source_edges(
			content_state,
			stack_id,
			typed_edges_key,
			"stack_edges"
		)
		old_edge = _edge_by_id(projected_edges, edge_id)
		if not old_edge.is_empty():
			content_state.call(
				"remove_stack_edge",
				stack_id,
				str(old_edge.get("from", "")),
				str(old_edge.get("to", ""))
			)
			return {
				"success": true,
				"changed": true,
				"edges": stored_edges,
				"errors": [],
			}
	var result: Dictionary = remove(stored_edges, edge_id)
	if not bool(result.get("success", false)):
		return result
	var remaining: Array = result.get("edges", stored_edges)
	if not _has_endpoint_pair(
		remaining,
		str(old_edge.get("from", "")),
		str(old_edge.get("to", ""))
	):
		content_state.call(
			"remove_stack_edge",
			stack_id,
			str(old_edge.get("from", "")),
			str(old_edge.get("to", ""))
		)
	stack_data = content_state.call("get_source_data", stack_id)
	stack_meta = stack_data.get("meta", {})
	ai_context = stack_meta.get("ai_context", {})
	ai_context[typed_edges_key] = remaining
	stack_meta["ai_context"] = ai_context
	stack_data["meta"] = stack_meta
	var is_updated: bool = bool(content_state.call("update_source", stack_id, stack_data))
	if is_updated:
		content_state.call("save_source", stack_id)
	result["success"] = is_updated
	return result


func _has_endpoint_pair(edges: Array, from_id: String, to_id: String) -> bool:
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if (
			str(edge_data.get("from", "")) == from_id
			and str(edge_data.get("to", "")) == to_id
		):
			return true
	return false


func _mirror_legacy_edge(
	content_state: Object,
	edge_data: Dictionary,
	is_adding: bool
) -> void:
	var relation_id: String = str(edge_data.get("relation", ""))
	var legacy_kind: String = ""
	match relation_id:
		"contains":
			legacy_kind = "child"
		"depends_on", "precedes":
			legacy_kind = "depends"
		"related_to":
			legacy_kind = "assoc"
	if legacy_kind.is_empty():
		return
	var method_id: String = "add_edge" if is_adding else "remove_edge"
	content_state.call(
		method_id,
		legacy_kind,
		str(edge_data.get("from", "")),
		str(edge_data.get("to", ""))
	)


func _edge_by_id(edges: Array, edge_id: String) -> Dictionary:
	var edge_index: int = _find_edge_index(edges, edge_id.strip_edges())
	if edge_index < 0:
		return {}
	return (edges[edge_index] as Dictionary).duplicate(true)


func _find_edge_index(edges: Array, edge_id: String) -> int:
	for edge_index in range(edges.size()):
		var edge_any: Variant = edges[edge_index]
		if (
			typeof(edge_any) == TYPE_DICTIONARY
			and str((edge_any as Dictionary).get("id", "")).strip_edges() == edge_id
		):
			return edge_index
	return -1


func _node_ids(nodes: Array) -> Array[String]:
	var ids: Array[String] = []
	for node_any in nodes:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_id: String = str((node_any as Dictionary).get("node_id", "")).strip_edges()
		if not node_id.is_empty():
			ids.append(node_id)
	return ids
