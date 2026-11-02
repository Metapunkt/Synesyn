## Purpose: Map SynTree content and legacy artifacts onto Graph Workspace v1.
extends RefCounted

const GraphWorkspaceDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)
const ContextGraphProvenanceScript = preload(
	"res://addons/syntree/scripts/core/context_graph_provenance.gd"
)

var _provenance: RefCounted = ContextGraphProvenanceScript.new()


func migrate_artifact(payload: Dictionary) -> Dictionary:
	var schema_version: int = int(payload.get("schema_version", 0))
	if schema_version == 2:
		var current_document: Dictionary = payload.duplicate(true)
		var current_validation: Dictionary = GraphWorkspaceDocumentScript.validate(
			current_document,
			"context_graph"
		)
		return {
			"ok": bool(current_validation.get("ok", false)),
			"document": current_document,
			"source_schema_version": 2,
			"requires_commit": false,
			"validation_errors": current_validation.get("errors", []),
			"warnings": [],
		}
	if schema_version != 1:
		return {
			"ok": false,
			"error": "unsupported_context_graph_schema:%d" % schema_version,
		}

	var document: Dictionary = GraphWorkspaceDocumentScript.create_empty(
		"context_graph",
		str(payload.get("name", ""))
	)
	document["schema_version"] = 2
	var warnings: Array[String] = []
	var nodes: Array = []
	var node_ids: Dictionary = {}
	var legacy_nodes_any: Variant = payload.get("nodes", [])
	if typeof(legacy_nodes_any) == TYPE_ARRAY:
		for legacy_node_any in (legacy_nodes_any as Array):
			if typeof(legacy_node_any) != TYPE_DICTIONARY:
				continue
			var legacy_node: Dictionary = legacy_node_any
			var node_data: Dictionary = _migrate_v1_node(legacy_node)
			var node_id: String = str(node_data.get("id", ""))
			if node_id.is_empty() or node_ids.has(node_id):
				continue
			node_ids[node_id] = true
			nodes.append(node_data)
	document["nodes"] = nodes

	var edges: Array = []
	var legacy_edges_any: Variant = payload.get("edges", [])
	if typeof(legacy_edges_any) == TYPE_ARRAY:
		var edge_index: int = 0
		for legacy_edge_any in (legacy_edges_any as Array):
			if typeof(legacy_edge_any) != TYPE_DICTIONARY:
				continue
			var legacy_edge: Dictionary = legacy_edge_any
			var legacy_kind: String = str(legacy_edge.get("kind", "")).strip_edges()
			var relation_id: String = "contains" if legacy_kind == "stack_member" else "related_to"
			if legacy_kind != "stack_member":
				warnings.append("legacy_edge_kind_mapped_to_related_to:%s" % legacy_kind)
			edges.append(_make_edge(
				"legacy-edge-%d" % edge_index,
				str(legacy_edge.get("from", "")),
				str(legacy_edge.get("to", "")),
				relation_id
			))
			edge_index += 1
	document["edges"] = edges
	document["context_sets"] = [_context_set_from_selection(payload.get("selection", {}))]
	var validation: Dictionary = GraphWorkspaceDocumentScript.validate(
		document,
		"context_graph"
	)
	return {
		"ok": bool(validation.get("ok", false)),
		"document": document,
		"source_schema_version": 1,
		"requires_commit": true,
		"validation_errors": validation.get("errors", []),
		"warnings": warnings,
	}


func build_from_sources(
	content_state: Object,
	source_ids: Array[String],
	graph_title: String = ""
) -> Dictionary:
	var document: Dictionary = GraphWorkspaceDocumentScript.create_empty(
		"context_graph",
		graph_title
	)
	document["schema_version"] = 2
	var nodes: Array = []
	var edges: Array = []
	var included_source_ids: Array[String] = _collect_source_ids(content_state, source_ids)
	for source_id in included_source_ids:
		_append_source(content_state, source_id, nodes, edges)
	document["nodes"] = nodes
	document["edges"] = _dedupe_edges(edges)
	document["context_sets"] = _collect_context_sets(
		content_state,
		source_ids,
		included_source_ids
	)
	var validation: Dictionary = GraphWorkspaceDocumentScript.validate(
		document,
		"context_graph"
	)
	return {
		"ok": bool(validation.get("ok", false)),
		"document": document,
		"validation_errors": validation.get("errors", []),
	}


func _collect_source_ids(
	content_state: Object,
	entry_source_ids: Array[String]
) -> Array[String]:
	var included: Dictionary = {}
	var pending: Array[String] = entry_source_ids.duplicate()
	while not pending.is_empty():
		var source_id: String = pending.pop_front()
		if source_id.is_empty() or included.has(source_id):
			continue
		included[source_id] = true
		var source_data: Dictionary = content_state.call("get_source_data", source_id)
		var source_meta: Dictionary = source_data.get("meta", {})
		var ai_context: Dictionary = source_meta.get("ai_context", {})
		var stack_sources_any: Variant = ai_context.get("stack_sources", [])
		if typeof(stack_sources_any) != TYPE_ARRAY:
			continue
		for stack_source_any in (stack_sources_any as Array):
			var child_source_id: String = ""
			if typeof(stack_source_any) == TYPE_DICTIONARY:
				child_source_id = str((stack_source_any as Dictionary).get("id", "")).strip_edges()
			else:
				child_source_id = str(stack_source_any).strip_edges()
			if not child_source_id.is_empty() and not included.has(child_source_id):
				pending.append(child_source_id)
	var result: Array[String] = []
	for source_id_any in included:
		result.append(str(source_id_any))
	result.sort()
	return result


func _append_source(
	content_state: Object,
	source_id: String,
	nodes: Array,
	edges: Array
) -> void:
	var source_data: Dictionary = content_state.call("get_source_data", source_id)
	if source_data.is_empty():
		return
	var source_meta: Dictionary = source_data.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	var is_stack: bool = bool(ai_context.get("is_stack", false))
	var source_provenance: Dictionary = _provenance.call(
		"normalize",
		source_meta.get("provenance", {}),
		"source:%s" % source_id
	)
	nodes.append({
		"id": source_id,
		"kind": "stack" if is_stack else "content_source",
		"label": str(source_meta.get("name", source_id)),
		"status": "committed",
		"activation": _activation_from(ai_context.get("activation", {})),
		"annotations": {
			"source_type": str(source_meta.get("source_type", "")),
			"is_active": bool(ai_context.get("is_active", false)),
			"is_metaprompt": bool(ai_context.get("metaprompt", false)),
		},
		"provenance": source_provenance,
		"provenance_refs": _provenance.call("refs", source_provenance),
	})
	if is_stack:
		_append_stack_edges(source_id, ai_context, edges)
	var content_data: Dictionary = source_data.get("content", {})
	var content_nodes_any: Variant = content_data.get("nodes", [])
	if typeof(content_nodes_any) != TYPE_ARRAY:
		return
	for content_node_any in (content_nodes_any as Array):
		if typeof(content_node_any) != TYPE_DICTIONARY:
			continue
		var content_node: Dictionary = content_node_any
		_append_content_node(source_id, content_node, nodes, edges)
	var rich_edges_any: Variant = content_data.get("context_graph_edges", [])
	if typeof(rich_edges_any) == TYPE_ARRAY:
		_append_rich_edges(source_id, rich_edges_any, edges)


func _append_stack_edges(source_id: String, ai_context: Dictionary, edges: Array) -> void:
	var stack_sources_any: Variant = ai_context.get("stack_sources", [])
	if typeof(stack_sources_any) != TYPE_ARRAY:
		return
	for stack_source_any in (stack_sources_any as Array):
		var child_source_id: String = ""
		if typeof(stack_source_any) == TYPE_DICTIONARY:
			child_source_id = str((stack_source_any as Dictionary).get("id", "")).strip_edges()
		else:
			child_source_id = str(stack_source_any).strip_edges()
		if not child_source_id.is_empty():
			edges.append(_make_edge(
				_edge_id(source_id, "contains", child_source_id),
				source_id,
				child_source_id,
				"contains"
			))


func _append_content_node(
	source_id: String,
	content_node: Dictionary,
	nodes: Array,
	edges: Array
) -> void:
	var local_node_id: String = str(content_node.get("node_id", "")).strip_edges()
	if local_node_id.is_empty():
		return
	var node_id: String = _composed_node_id(source_id, local_node_id)
	var node_label: String = str(content_node.get("title", content_node.get("content", local_node_id)))
	var node_provenance: Dictionary = _provenance.call(
		"normalize",
		content_node.get("provenance", {}),
		"source:%s" % source_id
	)
	nodes.append({
		"id": node_id,
		"kind": str(content_node.get("node_type", "chunk")),
		"label": node_label,
		"status": "committed",
		"activation": _activation_from(content_node.get("activation", {})),
		"annotations": {"source_id": source_id, "local_node_id": local_node_id},
		"provenance": node_provenance,
		"provenance_refs": _provenance.call("refs", node_provenance),
	})
	edges.append(_make_edge(
		_edge_id(source_id, "contains", node_id),
		source_id,
		node_id,
		"contains"
	))
	var relationships: Dictionary = content_node.get("relationships", {})
	_append_relationship_edges(source_id, node_id, relationships, "children", "contains", edges)
	_append_relationship_edges(source_id, node_id, relationships, "dependencies", "depends_on", edges)
	_append_relationship_edges(source_id, node_id, relationships, "associations", "related_to", edges)


func _append_relationship_edges(
	source_id: String,
	from_id: String,
	relationships: Dictionary,
	relationship_key: String,
	relation_id: String,
	edges: Array
) -> void:
	var targets_any: Variant = relationships.get(relationship_key, [])
	if typeof(targets_any) != TYPE_ARRAY:
		return
	for target_any in (targets_any as Array):
		var target_id: String = _composed_node_id(source_id, str(target_any))
		edges.append(_make_edge(
			_edge_id(from_id, relation_id, target_id),
			from_id,
			target_id,
			relation_id
		))


func _append_rich_edges(source_id: String, rich_edges: Array, edges: Array) -> void:
	for edge_any in rich_edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var local_edge: Dictionary = edge_any
		var mapped_edge: Dictionary = local_edge.duplicate(true)
		mapped_edge["id"] = "%s::%s" % [source_id, str(local_edge.get("id", ""))]
		mapped_edge["from"] = _composed_node_id(
			source_id,
			str(local_edge.get("from", ""))
		)
		mapped_edge["to"] = _composed_node_id(
			source_id,
			str(local_edge.get("to", ""))
		)
		var edge_provenance: Dictionary = _provenance.call(
			"normalize",
			local_edge.get("provenance", {}),
			"source:%s" % source_id
		)
		mapped_edge["provenance"] = edge_provenance
		mapped_edge["provenance_refs"] = _provenance.call(
			"refs",
			edge_provenance
		)
		edges.append(mapped_edge)


func _dedupe_edges(edges: Array) -> Array:
	var by_semantics: Dictionary = {}
	var ordered_keys: Array[String] = []
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		var semantic_key: String = "%s|%s|%s" % [
			str(edge_data.get("from", "")),
			str(edge_data.get("relation", "")),
			str(edge_data.get("to", "")),
		]
		if not by_semantics.has(semantic_key):
			ordered_keys.append(semantic_key)
		by_semantics[semantic_key] = edge_data
	var result: Array = []
	for ordered_key in ordered_keys:
		result.append(by_semantics[ordered_key])
	return result


func _migrate_v1_node(legacy_node: Dictionary) -> Dictionary:
	var node_id: String = str(legacy_node.get("id", "")).strip_edges()
	var legacy_meta: Dictionary = legacy_node.get("meta", {})
	var node_provenance: Dictionary = _provenance.call(
		"normalize",
		{},
		"source:%s" % node_id
	)
	return {
		"id": node_id,
		"kind": str(legacy_node.get("kind", "content_source")),
		"label": str(legacy_meta.get("name", node_id)),
		"status": "committed",
		"annotations": {"legacy_meta": legacy_meta.duplicate(true)},
		"provenance": node_provenance,
		"provenance_refs": _provenance.call("refs", node_provenance),
	}


func _context_set_from_selection(selection_any: Variant) -> Dictionary:
	var active_ids: Array[String] = []
	if typeof(selection_any) == TYPE_DICTIONARY:
		var selected_any: Variant = (selection_any as Dictionary).get("active_source_ids", [])
		if typeof(selected_any) == TYPE_ARRAY:
			for selected_id_any in (selected_any as Array):
				active_ids.append(str(selected_id_any))
	return _make_context_set(active_ids)


func _make_context_set(entry_node_ids: Array[String]) -> Dictionary:
	return {
		"id": "active-sources",
		"label": "Active Sources",
		"entry_node_ids": entry_node_ids.duplicate(),
		"allowed_relationship_types": [],
		"traversal_depth": 0,
		"activation_rules": {"mode": "manual"},
		"budget_policy": {},
	}


func _collect_context_sets(
	content_state: Object,
	active_source_ids: Array[String],
	included_source_ids: Array[String]
) -> Array:
	var context_sets: Array = [_make_context_set(active_source_ids)]
	for owner_source_id in included_source_ids:
		var source_data: Dictionary = content_state.call(
			"get_source_data",
			owner_source_id
		)
		var source_meta: Dictionary = source_data.get("meta", {})
		var ai_context: Dictionary = source_meta.get("ai_context", {})
		var stored_sets_any: Variant = ai_context.get("context_sets", [])
		if typeof(stored_sets_any) != TYPE_ARRAY:
			continue
		for stored_set_any in (stored_sets_any as Array):
			if typeof(stored_set_any) != TYPE_DICTIONARY:
				continue
			var stored_set: Dictionary = (
				stored_set_any as Dictionary
			).duplicate(true)
			var local_set_id: String = str(stored_set.get("id", ""))
			if local_set_id.is_empty():
				continue
			stored_set["local_id"] = local_set_id
			stored_set["owner_source_id"] = owner_source_id
			stored_set["id"] = "%s::%s" % [owner_source_id, local_set_id]
			var mapped_entries: Array[String] = []
			for entry_id_any in stored_set.get("entry_node_ids", []):
				var entry_id: String = str(entry_id_any)
				if (
					entry_id.contains("::")
					or included_source_ids.has(entry_id)
				):
					mapped_entries.append(entry_id)
				else:
					mapped_entries.append(
						_composed_node_id(owner_source_id, entry_id)
					)
			stored_set["entry_node_ids"] = mapped_entries
			context_sets.append(stored_set)
	return context_sets


func _make_edge(
	edge_id: String,
	from_id: String,
	to_id: String,
	relation_id: String
) -> Dictionary:
	var edge_provenance: Dictionary = _provenance.call(
		"normalize",
		{}
	)
	return {
		"id": edge_id,
		"from": from_id.strip_edges(),
		"to": to_id.strip_edges(),
		"relation": relation_id,
		"status": "committed",
		"provenance": edge_provenance,
		"provenance_refs": [],
	}


func _composed_node_id(source_id: String, local_node_id: String) -> String:
	return "%s::%s" % [source_id.strip_edges(), local_node_id.strip_edges()]


func _activation_from(activation_any: Variant) -> Dictionary:
	if typeof(activation_any) != TYPE_DICTIONARY:
		return {"mode": "when_relevant", "conditions": {}, "priority": 0}
	var activation: Dictionary = (activation_any as Dictionary).duplicate(true)
	if not activation.has("mode"):
		activation["mode"] = "when_relevant"
	return activation


func _edge_id(from_id: String, relation_id: String, to_id: String) -> String:
	return "%s::%s::%s" % [from_id, relation_id, to_id]
