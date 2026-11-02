## Purpose: Read and persist normalized provenance on source/content nodes.
extends RefCounted

const ContextGraphProvenanceScript = preload(
	"res://addons/syntree/scripts/core/context_graph_provenance.gd"
)

var _provenance: RefCounted = ContextGraphProvenanceScript.new()


func get_provenance(
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
		return _provenance.call("normalize", {})
	var source_data: Dictionary = location.get("source_data", {})
	var target_source_id: String = str(location.get("source_id", source_id))
	var raw_provenance: Dictionary = {}
	if bool(location.get("is_source_node", false)):
		var source_meta: Dictionary = source_data.get("meta", {})
		raw_provenance = source_meta.get("provenance", {})
		var location_any: Variant = raw_provenance.get(
			"source_location",
			{}
		)
		var has_uri: bool = (
			typeof(location_any) == TYPE_DICTIONARY
			and (location_any as Dictionary).has("uri")
		)
		if not has_uri:
			raw_provenance["source_location"] = {
				"uri": str(source_meta.get("path", "")),
			}
	else:
		var content_data: Dictionary = source_data.get("content", {})
		var nodes: Array = content_data.get("nodes", [])
		var node_index: int = int(location.get("node_index", -1))
		if node_index >= 0 and node_index < nodes.size():
			var node_data: Dictionary = nodes[node_index]
			raw_provenance = node_data.get("provenance", {})
	return _provenance.call(
		"normalize",
		raw_provenance,
		"source:%s" % target_source_id
	)


func set_provenance(
	content_state: Object,
	source_id: String,
	node_id: String,
	provenance: Dictionary
) -> Dictionary:
	var location: Dictionary = _resolve_location(
		content_state,
		source_id,
		node_id
	)
	if location.is_empty():
		return {"ok": false, "errors": ["node_not_found"]}
	var source_data: Dictionary = location.get("source_data", {})
	var target_source_id: String = str(location.get("source_id", source_id))
	var normalized: Dictionary = _provenance.call(
		"normalize",
		provenance,
		"source:%s" % target_source_id
	)
	if bool(location.get("is_source_node", false)):
		var source_meta: Dictionary = source_data.get("meta", {})
		source_meta["provenance"] = normalized
		source_data["meta"] = source_meta
	else:
		var content_data: Dictionary = source_data.get("content", {})
		var nodes: Array = content_data.get("nodes", [])
		var node_index: int = int(location.get("node_index", -1))
		var node_data: Dictionary = nodes[node_index]
		node_data["provenance"] = normalized
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
		"provenance": normalized,
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
	var nodes: Array = (
		source_data.get("content", {}) as Dictionary
	).get("nodes", [])
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
