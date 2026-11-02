## Purpose: Controlled SynTree Context Graph relationship vocabulary and rules.
extends RefCounted

const RELATIONSHIPS: Dictionary = {
	"contains": {
		"label": "Contains",
		"category": "structural",
		"inverse_label": "Part of",
		"is_structural": true,
		"color": "#6f8fb3",
	},
	"part_of": {
		"label": "Part of",
		"category": "structural",
		"inverse_label": "Contains",
		"is_structural": true,
		"canonical_relation": "contains",
		"reverse_for_canonical": true,
		"color": "#6f8fb3",
	},
	"depends_on": {
		"label": "Depends on",
		"category": "dependency",
		"inverse_label": "Required by",
		"is_structural": false,
		"color": "#b58b4b",
	},
	"precedes": {
		"label": "Precedes",
		"category": "dependency",
		"inverse_label": "Follows",
		"is_structural": false,
		"color": "#b58b4b",
	},
	"supports": {
		"label": "Supports",
		"category": "evidential",
		"inverse_label": "Supported by",
		"is_structural": false,
		"color": "#4f9b72",
	},
	"contradicts": {
		"label": "Contradicts",
		"category": "evidential",
		"inverse_label": "Contradicted by",
		"is_structural": false,
		"color": "#b96666",
	},
	"derived_from": {
		"label": "Derived from",
		"category": "evidential",
		"inverse_label": "Source for",
		"is_structural": false,
		"color": "#4f9b72",
	},
	"refines": {
		"label": "Refines",
		"category": "semantic",
		"inverse_label": "Refined by",
		"is_structural": false,
		"color": "#8a72b5",
	},
	"example_of": {
		"label": "Example of",
		"category": "semantic",
		"inverse_label": "Has example",
		"is_structural": false,
		"color": "#8a72b5",
	},
	"related_to": {
		"label": "Related to",
		"category": "semantic",
		"inverse_label": "Related to",
		"is_structural": false,
		"color": "#7d8792",
	},
}


static func relation_ids() -> Array[String]:
	var ids: Array[String] = []
	for relation_id_any in RELATIONSHIPS:
		ids.append(str(relation_id_any))
	return ids


static func definition(relation_id: String) -> Dictionary:
	return RELATIONSHIPS.get(relation_id.strip_edges(), {}).duplicate(true)


static func canonicalize(
	relation_id: String,
	from_id: String,
	to_id: String
) -> Dictionary:
	var normalized_relation: String = relation_id.strip_edges()
	var relation_definition: Dictionary = definition(normalized_relation)
	if relation_definition.is_empty():
		return {}
	var canonical_relation: String = str(
		relation_definition.get("canonical_relation", normalized_relation)
	)
	if bool(relation_definition.get("reverse_for_canonical", false)):
		return {"relation": canonical_relation, "from": to_id, "to": from_id}
	return {"relation": canonical_relation, "from": from_id, "to": to_id}


static func make_edge(
	relation_id: String,
	from_id: String,
	to_id: String,
	notes: String = "",
	confidence: Variant = null,
	provenance_refs: Array = [],
	edge_id: String = ""
) -> Dictionary:
	var canonical: Dictionary = canonicalize(relation_id, from_id, to_id)
	if canonical.is_empty():
		return {}
	var canonical_relation: String = str(canonical.get("relation", ""))
	var canonical_from: String = str(canonical.get("from", "")).strip_edges()
	var canonical_to: String = str(canonical.get("to", "")).strip_edges()
	var timestamp_text: String = Time.get_datetime_string_from_system(true, true)
	var stable_id: String = edge_id.strip_edges()
	if stable_id.is_empty():
		stable_id = "%s::%s::%s" % [canonical_from, canonical_relation, canonical_to]
	var edge_data: Dictionary = {
		"id": stable_id,
		"from": canonical_from,
		"to": canonical_to,
		"relation": canonical_relation,
		"status": "committed",
		"notes": notes,
		"provenance_refs": provenance_refs.duplicate(true),
		"created_at": timestamp_text,
		"updated_at": timestamp_text,
	}
	if confidence != null:
		edge_data["confidence"] = float(confidence)
	return edge_data


static func validate_edge(
	edge_data: Dictionary,
	node_ids: Array[String],
	existing_edges: Array = []
) -> Dictionary:
	var errors: Array[String] = []
	var edge_id: String = str(edge_data.get("id", "")).strip_edges()
	var from_id: String = str(edge_data.get("from", "")).strip_edges()
	var to_id: String = str(edge_data.get("to", "")).strip_edges()
	var relation_id: String = str(edge_data.get("relation", "")).strip_edges()
	if edge_id.is_empty():
		errors.append("edge_id_required")
	if not RELATIONSHIPS.has(relation_id) or relation_id == "part_of":
		errors.append("unknown_or_noncanonical_relation:%s" % relation_id)
	if from_id == to_id:
		errors.append("self_edge_not_allowed")
	if not node_ids.has(from_id):
		errors.append("from_node_missing:%s" % from_id)
	if not node_ids.has(to_id):
		errors.append("to_node_missing:%s" % to_id)
	for existing_any in existing_edges:
		if typeof(existing_any) != TYPE_DICTIONARY:
			continue
		var existing: Dictionary = existing_any
		if str(existing.get("id", "")) != edge_id and (
			str(existing.get("from", "")) == from_id
			and str(existing.get("to", "")) == to_id
			and str(existing.get("relation", "")) == relation_id
		):
			errors.append("duplicate_edge")
			break
	if relation_id == "contains" and would_create_structural_cycle(
		existing_edges,
		from_id,
		to_id,
		edge_id
	):
		errors.append("structural_cycle")
	return {"ok": errors.is_empty(), "errors": errors}


static func would_create_structural_cycle(
	existing_edges: Array,
	from_id: String,
	to_id: String,
	ignored_edge_id: String = ""
) -> bool:
	var adjacency: Dictionary = {}
	for edge_any in existing_edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if str(edge_data.get("id", "")) == ignored_edge_id:
			continue
		if str(edge_data.get("relation", "")) != "contains":
			continue
		var edge_from: String = str(edge_data.get("from", ""))
		var targets: Array = adjacency.get(edge_from, [])
		targets.append(str(edge_data.get("to", "")))
		adjacency[edge_from] = targets
	var pending: Array[String] = [to_id]
	var visited: Dictionary = {}
	while not pending.is_empty():
		var current_id: String = pending.pop_front()
		if current_id == from_id:
			return true
		if visited.has(current_id):
			continue
		visited[current_id] = true
		var next_nodes: Array = adjacency.get(current_id, [])
		for next_id_any in next_nodes:
			pending.append(str(next_id_any))
	return false
