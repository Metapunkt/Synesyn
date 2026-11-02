## Purpose: Runtime-safe, domain-neutral Graph Workspace document primitives.
##
## This script owns only the shared semantic envelope and validation rules.
## SynTree Context Graph and Workshop Catalyst Thinking Map must provide their
## domain semantics through separate adapters and artifact contracts.
extends RefCounted
class_name GraphWorkspaceDocument

const GRAPH_SCHEMA_VERSION: int = 1
const REVIEW_STATES := [
	"committed",
	"suggested",
	"accepted",
	"edited",
	"rejected",
]


static func create_empty(graph_kind: String, graph_name: String = "") -> Dictionary:
	return {
		"graph_schema_version": GRAPH_SCHEMA_VERSION,
		"graph_kind": graph_kind.strip_edges(),
		"name": graph_name.strip_edges(),
		"nodes": [],
		"edges": [],
	}


static func validate(document: Dictionary, expected_graph_kind: String = "") -> Dictionary:
	var errors: Array[String] = []
	if int(document.get("graph_schema_version", 0)) != GRAPH_SCHEMA_VERSION:
		errors.append("unsupported_graph_schema_version")

	var graph_kind: String = str(document.get("graph_kind", "")).strip_edges()
	if graph_kind.is_empty():
		errors.append("graph_kind_required")
	var expected_kind: String = expected_graph_kind.strip_edges()
	if not expected_kind.is_empty() and graph_kind != expected_kind:
		errors.append("unexpected_graph_kind:%s" % graph_kind)

	var nodes_any: Variant = document.get("nodes", null)
	var edges_any: Variant = document.get("edges", null)
	if typeof(nodes_any) != TYPE_ARRAY:
		errors.append("nodes_array_required")
	if typeof(edges_any) != TYPE_ARRAY:
		errors.append("edges_array_required")
	if not errors.is_empty() and (
		typeof(nodes_any) != TYPE_ARRAY or typeof(edges_any) != TYPE_ARRAY
	):
		return {"ok": false, "errors": errors}

	var node_ids: Dictionary = {}
	var nodes: Array = nodes_any
	for node_any in nodes:
		if typeof(node_any) != TYPE_DICTIONARY:
			errors.append("node_must_be_object")
			continue
		var node_data: Dictionary = node_any
		var node_id: String = str(node_data.get("id", "")).strip_edges()
		_validate_record(node_data, "node", errors)
		if node_id.is_empty():
			continue
		if node_ids.has(node_id):
			errors.append("duplicate_node_id:%s" % node_id)
		else:
			node_ids[node_id] = true
		if str(node_data.get("kind", "")).strip_edges().is_empty():
			errors.append("node_kind_required:%s" % node_id)

	var edge_ids: Dictionary = {}
	var edges: Array = edges_any
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			errors.append("edge_must_be_object")
			continue
		var edge_data: Dictionary = edge_any
		var edge_id: String = str(edge_data.get("id", "")).strip_edges()
		_validate_record(edge_data, "edge", errors)
		if not edge_id.is_empty():
			if edge_ids.has(edge_id):
				errors.append("duplicate_edge_id:%s" % edge_id)
			else:
				edge_ids[edge_id] = true

		var from_id: String = str(edge_data.get("from", "")).strip_edges()
		var to_id: String = str(edge_data.get("to", "")).strip_edges()
		if from_id.is_empty() or to_id.is_empty():
			errors.append("edge_endpoints_required:%s" % edge_id)
		else:
			if not node_ids.has(from_id):
				errors.append("dangling_edge_from:%s:%s" % [edge_id, from_id])
			if not node_ids.has(to_id):
				errors.append("dangling_edge_to:%s:%s" % [edge_id, to_id])
		if str(edge_data.get("relation", "")).strip_edges().is_empty():
			errors.append("edge_relation_required:%s" % edge_id)

		var confidence_any: Variant = edge_data.get("confidence", null)
		if confidence_any != null:
			if typeof(confidence_any) != TYPE_FLOAT and typeof(confidence_any) != TYPE_INT:
				errors.append("edge_confidence_must_be_numeric:%s" % edge_id)
			else:
				var confidence_value: float = float(confidence_any)
				if confidence_value < 0.0 or confidence_value > 1.0:
					errors.append("edge_confidence_out_of_range:%s" % edge_id)

	return {"ok": errors.is_empty(), "errors": errors}


static func semantic_snapshot(document: Dictionary) -> Dictionary:
	var snapshot: Dictionary = document.duplicate(true)
	snapshot.erase("layout_ref")
	snapshot.erase("viewport")
	snapshot.erase("selection")
	snapshot.erase("focus")
	return snapshot


static func semantic_diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var before_semantic: Dictionary = semantic_snapshot(before)
	var after_semantic: Dictionary = semantic_snapshot(after)
	return {
		"nodes": _diff_records(
			before_semantic.get("nodes", []),
			after_semantic.get("nodes", [])
		),
		"edges": _diff_records(
			before_semantic.get("edges", []),
			after_semantic.get("edges", [])
		),
	}


static func _diff_records(before_any: Variant, after_any: Variant) -> Dictionary:
	var before_by_id: Dictionary = _records_by_id(before_any)
	var after_by_id: Dictionary = _records_by_id(after_any)
	var added: Array[String] = []
	var removed: Array[String] = []
	var changed: Array[String] = []
	for record_id_any in after_by_id:
		var record_id: String = str(record_id_any)
		if not before_by_id.has(record_id):
			added.append(record_id)
		elif before_by_id[record_id] != after_by_id[record_id]:
			changed.append(record_id)
	for before_id_any in before_by_id:
		var before_id: String = str(before_id_any)
		if not after_by_id.has(before_id):
			removed.append(before_id)
	added.sort()
	removed.sort()
	changed.sort()
	return {"added": added, "removed": removed, "changed": changed}


static func _records_by_id(records_any: Variant) -> Dictionary:
	var records_by_id: Dictionary = {}
	if typeof(records_any) != TYPE_ARRAY:
		return records_by_id
	for record_any in (records_any as Array):
		if typeof(record_any) != TYPE_DICTIONARY:
			continue
		var record_data: Dictionary = record_any
		var record_id: String = str(record_data.get("id", "")).strip_edges()
		if not record_id.is_empty():
			records_by_id[record_id] = record_data
	return records_by_id


static func _validate_record(
	record_data: Dictionary,
	record_label: String,
	errors: Array[String]
) -> void:
	var record_id: String = str(record_data.get("id", "")).strip_edges()
	if record_id.is_empty():
		errors.append("%s_id_required" % record_label)

	var review_status: String = str(record_data.get("status", "")).strip_edges()
	if review_status not in REVIEW_STATES:
		errors.append("%s_status_invalid:%s:%s" % [
			record_label,
			record_id,
			review_status,
		])

	var provenance_any: Variant = record_data.get("provenance_refs", null)
	if typeof(provenance_any) != TYPE_ARRAY:
		errors.append("%s_provenance_refs_array_required:%s" % [
			record_label,
			record_id,
		])
