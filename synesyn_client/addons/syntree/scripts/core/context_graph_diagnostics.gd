## Purpose: Produce deterministic Context Graph health diagnostics and comparisons.
extends RefCounted

const GraphWorkspaceDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)


func analyze(
	document: Dictionary,
	compile_result: Dictionary = {}
) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	var validation: Dictionary = GraphWorkspaceDocumentScript.validate(
		document,
		str(document.get("graph_kind", ""))
	)
	for validation_error_any in validation.get("errors", []):
		var validation_error: String = str(validation_error_any)
		diagnostics.append(_diagnostic(
			"invalid_reference",
			"error",
			validation_error,
			_ids_from_validation_error(validation_error),
			{"action": "inspect_record"}
		))
	var nodes: Array = document.get("nodes", [])
	var edges: Array = document.get("edges", [])
	_append_orphans(nodes, edges, diagnostics)
	_append_duplicates(nodes, diagnostics)
	_append_structural_cycles(nodes, edges, diagnostics)
	_append_provenance_issues(nodes, edges, diagnostics)
	_append_instruction_conflicts(nodes, diagnostics)
	if bool(compile_result.get("is_over_budget", false)):
		diagnostics.append(_diagnostic(
			"token_budget_overflow",
			"error",
			"Compiled context exceeds its token budget.",
			_node_ids(compile_result.get("included_nodes", [])),
			{
				"action": "preview_budget_change",
				"estimated_tokens": compile_result.get(
					"estimated_tokens",
					0
				),
				"token_budget": compile_result.get("token_budget", 0),
			}
		))
	diagnostics.sort_custom(_diagnostic_order)
	return diagnostics


func compare_versions(
	before_document: Dictionary,
	after_document: Dictionary,
	before_compile: Dictionary = {},
	after_compile: Dictionary = {}
) -> Dictionary:
	return {
		"semantic_diff": GraphWorkspaceDocumentScript.semantic_diff(
			before_document,
			after_document
		),
		"compiled_context_diff": {
			"included_order_before": _node_ids(
				before_compile.get("included_nodes", [])
			),
			"included_order_after": _node_ids(
				after_compile.get("included_nodes", [])
			),
			"included_added": _array_difference(
				_node_ids(after_compile.get("included_nodes", [])),
				_node_ids(before_compile.get("included_nodes", []))
			),
			"included_removed": _array_difference(
				_node_ids(before_compile.get("included_nodes", [])),
				_node_ids(after_compile.get("included_nodes", []))
			),
			"estimated_tokens_before": before_compile.get(
				"estimated_tokens",
				0
			),
			"estimated_tokens_after": after_compile.get(
				"estimated_tokens",
				0
			),
			"compiled_text_changed": str(before_compile.get(
				"compiled_text",
				""
			)).sha256_text() != str(after_compile.get(
				"compiled_text",
				""
			)).sha256_text(),
			"compiled_text_hash_before": str(before_compile.get(
				"compiled_text",
				""
			)).sha256_text(),
			"compiled_text_hash_after": str(after_compile.get(
				"compiled_text",
				""
			)).sha256_text(),
		},
		"causation_claimed": false,
	}


func _append_orphans(
	nodes: Array,
	edges: Array,
	diagnostics: Array[Dictionary]
) -> void:
	var connected: Dictionary = {}
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		connected[str(edge_data.get("from", ""))] = true
		connected[str(edge_data.get("to", ""))] = true
	for node_any in nodes:
		var node_data: Dictionary = node_any
		var node_id: String = str(node_data.get("id", ""))
		if not node_id.is_empty() and not connected.has(node_id):
			diagnostics.append(_diagnostic(
				"orphaned_node",
				"warning",
				"Node has no relationships.",
				[node_id],
				{"action": "focus_node", "node_id": node_id}
			))


func _append_duplicates(
	nodes: Array,
	diagnostics: Array[Dictionary]
) -> void:
	var ids_by_label: Dictionary = {}
	for node_any in nodes:
		var node_data: Dictionary = node_any
		var normalized_label: String = str(
			node_data.get("label", "")
		).strip_edges().to_lower()
		if normalized_label.is_empty():
			continue
		if not ids_by_label.has(normalized_label):
			ids_by_label[normalized_label] = []
		(ids_by_label[normalized_label] as Array).append(
			str(node_data.get("id", ""))
		)
	for normalized_label in ids_by_label:
		var duplicate_ids: Array = ids_by_label[normalized_label]
		if duplicate_ids.size() > 1:
			diagnostics.append(_diagnostic(
				"duplicate_node_label",
				"warning",
				"Multiple nodes share the normalized label '%s'."
				% normalized_label,
				duplicate_ids,
				{"action": "preview_merge"}
			))


func _append_structural_cycles(
	nodes: Array,
	edges: Array,
	diagnostics: Array[Dictionary]
) -> void:
	var adjacency: Dictionary = {}
	for node_any in nodes:
		adjacency[str((node_any as Dictionary).get("id", ""))] = []
	for edge_any in edges:
		var edge_data: Dictionary = edge_any
		if str(edge_data.get("relation", "")) == "contains":
			var from_id: String = str(edge_data.get("from", ""))
			(adjacency.get(from_id, []) as Array).append(
				str(edge_data.get("to", ""))
			)
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for node_id_any in adjacency:
		var node_id: String = str(node_id_any)
		var cycle: Array[String] = _find_cycle(
			node_id,
			adjacency,
			visiting,
			visited,
			[]
		)
		if not cycle.is_empty():
			diagnostics.append(_diagnostic(
				"structural_cycle",
				"error",
				"Structural containment contains a cycle.",
				cycle,
				{"action": "preview_disconnect_cycle"}
			))
			return


func _find_cycle(
	node_id: String,
	adjacency: Dictionary,
	visiting: Dictionary,
	visited: Dictionary,
	path: Array[String]
) -> Array[String]:
	if bool(visiting.get(node_id, false)):
		var cycle_start: int = path.find(node_id)
		return path.slice(cycle_start) if cycle_start >= 0 else [node_id]
	if bool(visited.get(node_id, false)):
		return []
	visiting[node_id] = true
	path.append(node_id)
	for child_id_any in adjacency.get(node_id, []):
		var cycle: Array[String] = _find_cycle(
			str(child_id_any),
			adjacency,
			visiting,
			visited,
			path.duplicate()
		)
		if not cycle.is_empty():
			return cycle
	visiting.erase(node_id)
	visited[node_id] = true
	return []


func _append_provenance_issues(
	nodes: Array,
	edges: Array,
	diagnostics: Array[Dictionary]
) -> void:
	for record_any in nodes + edges:
		var record: Dictionary = record_any
		var provenance: Dictionary = record.get("provenance", {})
		var record_id: String = str(record.get("id", ""))
		if (
			provenance.is_empty()
			or str(provenance.get("origin_ref", "unknown")) == "unknown"
		):
			diagnostics.append(_diagnostic(
				"missing_provenance",
				"warning",
				"Record provenance is unknown.",
				[record_id],
				{"action": "open_provenance"}
			))
		var authorship_kind: String = str(
			provenance.get("authorship_kind", "unknown")
		)
		if (
			authorship_kind in ["ai_summary", "ai_inference"]
			and str(provenance.get("review_status", "unknown")) != (
				"reviewed"
			)
		):
			diagnostics.append(_diagnostic(
				"unreviewed_ai_record",
				"warning",
				"AI-authored record has not been reviewed.",
				[record_id],
				{"action": "open_provenance"}
			))
		if (
			not str(provenance.get("source_artifact_id", "")).is_empty()
			and str(provenance.get("source_version_id", "")).is_empty()
		):
			diagnostics.append(_diagnostic(
				"stale_or_unpinned_source",
				"warning",
				"Source artifact reference is not version-pinned.",
				[record_id],
				{"action": "select_source_version"}
			))


func _append_instruction_conflicts(
	nodes: Array,
	diagnostics: Array[Dictionary]
) -> void:
	var active_metaprompts: Array[String] = []
	for node_any in nodes:
		var node_data: Dictionary = node_any
		var annotations: Dictionary = node_data.get("annotations", {})
		if (
			bool(annotations.get("is_metaprompt", false))
			and bool(annotations.get("is_active", false))
		):
			active_metaprompts.append(str(node_data.get("id", "")))
	if active_metaprompts.size() > 1:
		diagnostics.append(_diagnostic(
			"conflicting_active_instructions",
			"warning",
			"Multiple active metaprompt sources require review.",
			active_metaprompts,
			{"action": "preview_activation_change"}
		))


func _diagnostic(
	diagnostic_type: String,
	severity: String,
	message: String,
	affected_ids: Array,
	repair_preview: Dictionary
) -> Dictionary:
	var id_seed: String = "%s|%s" % [
		diagnostic_type,
		JSON.stringify(affected_ids),
	]
	return {
		"id": "diag_%s" % id_seed.sha256_text().substr(0, 16),
		"type": diagnostic_type,
		"severity": severity,
		"message": message,
		"affected_record_ids": affected_ids.duplicate(),
		"repair_preview": repair_preview.duplicate(true),
	}


func _ids_from_validation_error(error_text: String) -> Array[String]:
	var parts: PackedStringArray = error_text.split(":")
	var result: Array[String] = []
	for part_index in range(1, parts.size()):
		if not parts[part_index].is_empty():
			result.append(parts[part_index])
	return result


func _node_ids(records: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(records) != TYPE_ARRAY:
		return result
	for record_any in records:
		if typeof(record_any) != TYPE_DICTIONARY:
			continue
		var node_id: String = str(
			(record_any as Dictionary).get("node_id", "")
		)
		if not node_id.is_empty():
			result.append(node_id)
	return result


func _array_difference(
	left: Array[String],
	right: Array[String]
) -> Array[String]:
	var result: Array[String] = []
	for value_id in left:
		if not right.has(value_id):
			result.append(value_id)
	result.sort()
	return result


func _diagnostic_order(left: Dictionary, right: Dictionary) -> bool:
	var severity_order: Dictionary = {
		"error": 0,
		"warning": 1,
		"information": 2,
	}
	var left_rank: int = int(
		severity_order.get(str(left.get("severity", "")), 3)
	)
	var right_rank: int = int(
		severity_order.get(str(right.get("severity", "")), 3)
	)
	if left_rank != right_rank:
		return left_rank < right_rank
	return str(left.get("id", "")) < str(right.get("id", ""))
