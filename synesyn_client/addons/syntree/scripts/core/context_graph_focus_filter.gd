## Purpose: Deterministically select visible Context Graph records for focus/filter UI.
extends RefCounted


func evaluate(
	document: Dictionary,
	options: Dictionary
) -> Dictionary:
	var nodes: Array = document.get("nodes", [])
	var edges: Array = document.get("edges", [])
	var search_text: String = str(
		options.get("search_text", "")
	).strip_edges().to_lower()
	var tag_filter: String = str(
		options.get("tag", "")
	).strip_edges().to_lower()
	var relation_types: Array[String] = _strings(
		options.get("relationship_types", [])
	)
	var activation_modes: Array[String] = _strings(
		options.get("activation_modes", [])
	)
	var authorship_kinds: Array[String] = _strings(
		options.get("authorship_kinds", [])
	)
	var review_states: Array[String] = _strings(
		options.get("review_states", [])
	)
	var candidate_ids: Array[String] = []
	for node_any in nodes:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		if not _matches_node(
			node_data,
			search_text,
			tag_filter,
			activation_modes,
			authorship_kinds,
			review_states,
			options
		):
			continue
		candidate_ids.append(str(node_data.get("id", "")))
	var allowed_edges: Array = []
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if (
			not relation_types.is_empty()
			and not relation_types.has(str(edge_data.get("relation", "")))
		):
			continue
		if (
			not bool(options.get("show_low_confidence", true))
			and float(edge_data.get("confidence", 1.0)) < float(
				options.get("confidence_threshold", 0.5)
			)
		):
			continue
		allowed_edges.append(edge_data)
	var focus_id: String = str(options.get("focus_node_id", ""))
	if not focus_id.is_empty():
		var neighborhood: Array[String] = _neighborhood(
			focus_id,
			allowed_edges,
			maxi(0, int(options.get("focus_depth", 1)))
		)
		candidate_ids = _intersection(candidate_ids, neighborhood)
	if not bool(options.get("show_unrelated", true)):
		candidate_ids = _connected_ids(candidate_ids, allowed_edges)
	var collapsed_ids: Array[String] = _ids(
		options.get("collapsed_node_ids", [])
	)
	var hidden_descendants: Array[String] = _structural_descendants(
		collapsed_ids,
		allowed_edges
	)
	candidate_ids = _difference(candidate_ids, hidden_descendants)
	var visible_edges: Array[String] = []
	for edge_any in allowed_edges:
		var edge_data: Dictionary = edge_any
		if (
			candidate_ids.has(str(edge_data.get("from", "")))
			and candidate_ids.has(str(edge_data.get("to", "")))
		):
			visible_edges.append(str(edge_data.get("id", "")))
	candidate_ids.sort()
	visible_edges.sort()
	return {
		"visible_node_ids": candidate_ids,
		"visible_edge_ids": visible_edges,
		"hidden_node_count": nodes.size() - candidate_ids.size(),
		"hidden_edge_count": edges.size() - visible_edges.size(),
	}


func _matches_node(
	node_data: Dictionary,
	search_text: String,
	tag_filter: String,
	activation_modes: Array[String],
	authorship_kinds: Array[String],
	review_states: Array[String],
	options: Dictionary
) -> bool:
	var node_id: String = str(node_data.get("id", ""))
	var label_text: String = str(node_data.get("label", ""))
	if (
		not search_text.is_empty()
		and not ("%s %s" % [node_id, label_text]).to_lower().contains(
			search_text
		)
	):
		return false
	var annotations: Dictionary = node_data.get("annotations", {})
	var tags: Array[String] = _strings(annotations.get("tags", []))
	if not tag_filter.is_empty() and not tags.has(tag_filter):
		return false
	var activation: Dictionary = node_data.get("activation", {})
	if (
		not activation_modes.is_empty()
		and not activation_modes.has(str(activation.get("mode", "")))
	):
		return false
	var provenance: Dictionary = node_data.get("provenance", {})
	if (
		not authorship_kinds.is_empty()
		and not authorship_kinds.has(str(
			provenance.get("authorship_kind", "unknown")
		))
	):
		return false
	if (
		not review_states.is_empty()
		and not review_states.has(str(node_data.get("status", "")))
	):
		return false
	if (
		not bool(options.get("show_inactive", true))
		and not bool(annotations.get("is_active", false))
	):
		return false
	if (
		not bool(options.get("show_rejected", false))
		and str(node_data.get("status", "")) == "rejected"
	):
		return false
	return true


func _neighborhood(
	focus_id: String,
	edges: Array,
	depth: int
) -> Array[String]:
	var visible_ids: Array[String] = [focus_id]
	var frontier: Array[String] = [focus_id]
	for _depth_index in range(depth):
		var next_frontier: Array[String] = []
		for edge_any in edges:
			var edge_data: Dictionary = edge_any
			var from_id: String = str(edge_data.get("from", ""))
			var to_id: String = str(edge_data.get("to", ""))
			if frontier.has(from_id) and not visible_ids.has(to_id):
				visible_ids.append(to_id)
				next_frontier.append(to_id)
			if frontier.has(to_id) and not visible_ids.has(from_id):
				visible_ids.append(from_id)
				next_frontier.append(from_id)
		frontier = next_frontier
		if frontier.is_empty():
			break
	return visible_ids


func _connected_ids(
	candidate_ids: Array[String],
	edges: Array
) -> Array[String]:
	var connected: Array[String] = []
	for edge_any in edges:
		var edge_data: Dictionary = edge_any
		var from_id: String = str(edge_data.get("from", ""))
		var to_id: String = str(edge_data.get("to", ""))
		if candidate_ids.has(from_id) and candidate_ids.has(to_id):
			if not connected.has(from_id):
				connected.append(from_id)
			if not connected.has(to_id):
				connected.append(to_id)
	return connected


func _structural_descendants(
	collapsed_ids: Array[String],
	edges: Array
) -> Array[String]:
	var hidden: Array[String] = []
	var frontier: Array[String] = collapsed_ids.duplicate()
	while not frontier.is_empty():
		var parent_id: String = frontier.pop_front()
		for edge_any in edges:
			var edge_data: Dictionary = edge_any
			if (
				str(edge_data.get("relation", "")) != "contains"
				or str(edge_data.get("from", "")) != parent_id
			):
				continue
			var child_id: String = str(edge_data.get("to", ""))
			if not hidden.has(child_id):
				hidden.append(child_id)
				frontier.append(child_id)
	return hidden


func _intersection(
	left: Array[String],
	right: Array[String]
) -> Array[String]:
	var result: Array[String] = []
	for value_id in left:
		if right.has(value_id):
			result.append(value_id)
	return result


func _difference(
	left: Array[String],
	right: Array[String]
) -> Array[String]:
	var result: Array[String] = []
	for value_id in left:
		if not right.has(value_id):
			result.append(value_id)
	return result


func _strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item_any in value:
		var item_text: String = str(item_any).strip_edges().to_lower()
		if not item_text.is_empty() and not result.has(item_text):
			result.append(item_text)
	return result


func _ids(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item_any in value:
		var item_text: String = str(item_any).strip_edges()
		if not item_text.is_empty() and not result.has(item_text):
			result.append(item_text)
	return result
